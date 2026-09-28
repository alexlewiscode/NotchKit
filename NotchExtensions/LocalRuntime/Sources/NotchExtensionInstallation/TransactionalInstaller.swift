import CryptoKit
import Foundation
import NotchExtensionSDK

public protocol ExtensionRegistrationServicing: Sendable {
    func register(providerAt url: URL) async throws
    func unregister(providerAt url: URL) async throws
}

public struct NoOpExtensionRegistrationService: ExtensionRegistrationServicing, Sendable {
    public init() {}
    public func register(providerAt url: URL) async throws {}
    public func unregister(providerAt url: URL) async throws {}
}

public enum ExtensionInstallerError: Error, Equatable {
    case teamMismatch
    case updateTeamMismatch
    case unmanagedInstallPath
    case notInstalled
    case noPreviousRelease
    case operationMismatch
    case rollbackFailed
    case installedCopyMismatch
    case marketplaceReceiptMismatch
    case archiveDigestMismatch
    case archiveSizeMismatch
    case incompatibleMarketplaceRelease
    case revokedMarketplaceRelease
    case staleMarketplaceEvidence
    case originTransitionNotAllowed
}

private actor InstallerMutationGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { locked = false }
        else { waiters.removeFirst().resume() }
    }
}

public final class TransactionalExtensionInstaller: @unchecked Sendable {
    public let rootURL: URL
    private let archiveValidator: any PackageArchiveValidating
    private let packageValidator: any ExtractedPackageValidating
    private let signatureValidator: any CodeSignatureValidating
    private let registrationService: any ExtensionRegistrationServicing
    private let store: any InstalledExtensionStore
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let mutationGate = InstallerMutationGate()

    public init(
        rootURL: URL,
        archiveValidator: any PackageArchiveValidating = ZIPPackageArchiveValidator(),
        packageValidator: any ExtractedPackageValidating = DefaultExtractedPackageValidator(),
        signatureValidator: any CodeSignatureValidating = SecurityCodeSignatureValidator(),
        registrationService: any ExtensionRegistrationServicing,
        store: (any InstalledExtensionStore)? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.archiveValidator = archiveValidator
        self.packageValidator = packageValidator
        self.signatureValidator = signatureValidator
        self.registrationService = registrationService
        self.store = store ?? JSONInstalledExtensionStore(rootURL: rootURL, fileManager: fileManager)
        self.fileManager = fileManager
        self.now = now
    }

    /// Preserves the original user-selected local developer install behavior.
    @discardableResult
    public func install(archiveURL: URL) async throws -> InstalledExtensionRecord {
        try await install(ExtensionInstallRequest(
            archiveURL: archiveURL,
            operation: .installOrUpdate,
            trustPolicy: .localDeveloper
        ))
    }

    @discardableResult
    public func install(_ request: ExtensionInstallRequest) async throws -> InstalledExtensionRecord {
        await mutationGate.acquire()
        do {
            let record = try await installUnlocked(request)
            await mutationGate.release()
            return record
        } catch {
            await mutationGate.release()
            throw error
        }
    }

    public func uninstall(id: ExtensionIdentity) async throws {
        await mutationGate.acquire()
        do {
            try await uninstallUnlocked(id: id)
            await mutationGate.release()
        } catch {
            await mutationGate.release()
            throw error
        }
    }

    @discardableResult
    public func rollback(
        id: ExtensionIdentity,
        marketplaceReceipt: MarketplaceReleaseReceipt? = nil
    ) async throws -> InstalledExtensionRecord {
        await mutationGate.acquire()
        do {
            let record = try await rollbackUnlocked(id: id, marketplaceReceipt: marketplaceReceipt)
            await mutationGate.release()
            return record
        } catch {
            await mutationGate.release()
            throw error
        }
    }

    private func installUnlocked(_ request: ExtensionInstallRequest) async throws -> InstalledExtensionRecord {
        var snapshot = try store.load()
        let transaction = try managedURL(relativePath: "Staging/\(UUID().uuidString)")
        let extracted = transaction.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transaction) }
        let context: ExtensionPackageValidationContext
        let origin: InstalledExtensionOrigin
        let receipt: MarketplaceReleaseReceipt?
        let archiveURL: URL
        switch request.trustPolicy {
        case .localDeveloper:
            context = .localDeveloper
            origin = .localDeveloper
            receipt = nil
            archiveURL = request.archiveURL
        case let .marketplace(value, maximumEvidenceAge):
            try validateMarketplaceEvidence(value, maximumAge: maximumEvidenceAge)
            let authenticatedArchive = transaction.appendingPathComponent("Authenticated.notchkitextension")
            try fileManager.copyItem(at: request.archiveURL, to: authenticatedArchive)
            try validateArchive(authenticatedArchive, against: value)
            context = .marketplace
            origin = .marketplace
            receipt = value
            archiveURL = authenticatedArchive
        }

        try archiveValidator.validateAndExtract(archiveURL: archiveURL, to: extracted)
        let package = try packageValidator.validate(packageRootURL: extracted, context: context)
        let signature = try signatureEvidence(for: package)
        if let receipt { try validate(package: package, signature: signature, against: receipt) }

        let existingIndex = snapshot.records.firstIndex { $0.id == package.manifest.id }
        switch (request.operation, existingIndex) {
        case (.install, .some), (.update, .none): throw ExtensionInstallerError.operationMismatch
        default: break
        }
        if let existingIndex,
           snapshot.records[existingIndex].signature.teamIdentifier != signature.teamIdentifier {
            throw ExtensionInstallerError.updateTeamMismatch
        }
        if let existingIndex,
           snapshot.records[existingIndex].origin == .marketplace,
           origin == .localDeveloper {
            throw ExtensionInstallerError.originTransitionNotAllowed
        }

        let relativePath = managedRelativePath(for: package.manifest.id)
        let previousRelativePath = managedPreviousRelativePath(for: package.manifest.id)
        let destination = try managedURL(relativePath: relativePath)
        let previousDestination = try managedURL(relativePath: previousRelativePath)
        let incoming = transaction.appendingPathComponent("Incoming", isDirectory: true)
        let backup = transaction.appendingPathComponent("Backup", isDirectory: true)
        let olderPrevious = transaction.appendingPathComponent("OlderPrevious", isDirectory: true)
        try fileManager.moveItem(at: extracted, to: incoming)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: previousDestination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let hadExisting = fileManager.fileExists(atPath: destination.path)
        let hadPrevious = fileManager.fileExists(atPath: previousDestination.path)
        let existingProvider = hadExisting ? try providerURL(in: destination) : nil
        if let existingProvider { try await registrationService.unregister(providerAt: existingProvider) }
        do {
            if hadExisting { try fileManager.moveItem(at: destination, to: backup) }
            if hadPrevious { try fileManager.moveItem(at: previousDestination, to: olderPrevious) }
        } catch {
            do {
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.moveItem(at: backup, to: destination)
                }
                if fileManager.fileExists(atPath: olderPrevious.path) {
                    try fileManager.moveItem(at: olderPrevious, to: previousDestination)
                }
                if let existingProvider {
                    try await registrationService.register(providerAt: existingProvider)
                }
            } catch {
                throw ExtensionInstallerError.rollbackFailed
            }
            throw error
        }
        var installedProvider: URL?
        do {
            try fileManager.moveItem(at: incoming, to: destination)
            let installedPackage = try packageValidator.validate(packageRootURL: destination, context: context)
            guard installedPackage.packageManifest == package.packageManifest,
                  installedPackage.manifestData == package.manifestData
            else { throw ExtensionInstallerError.installedCopyMismatch }
            let installedSignature = try signatureEvidence(for: installedPackage)
            guard installedSignature == signature else { throw ExtensionInstallerError.installedCopyMismatch }
            if let receipt { try validate(package: installedPackage, signature: installedSignature, against: receipt) }

            installedProvider = installedPackage.providerURL
            try await registrationService.register(providerAt: installedPackage.providerURL)
            if hadExisting { try fileManager.moveItem(at: backup, to: previousDestination) }
            let timestamp = now()
            let existing = existingIndex.map { snapshot.records[$0] }
            let record = InstalledExtensionRecord(
                id: installedPackage.manifest.id,
                extensionVersion: installedPackage.manifest.extensionVersion,
                providerBundleIdentifier: installedPackage.providerBundleIdentifier,
                extensionBundleIdentifiers: installedPackage.extensionBundleIdentifiers,
                relativeInstallPath: relativePath,
                manifestSHA256: sha256(installedPackage.manifestData),
                declaredPermissions: installedPackage.packageManifest.permissions,
                declaredHostActions: installedPackage.packageManifest.hostActions,
                signature: installedSignature,
                origin: origin,
                marketplaceReceipt: receipt,
                previousRelease: existing.map { InstalledExtensionRelease(record: $0, relativeInstallPath: previousRelativePath) },
                marketplaceRevocationStatus: receipt?.revocation.status ?? .notRevoked,
                installedAt: existing?.installedAt ?? timestamp,
                updatedAt: timestamp,
                desiredEnabled: existing?.desiredEnabled ?? installedPackage.manifest.defaultEnabled,
                localStatus: .installed,
                systemAuthorityStatus: existing?.systemAuthorityStatus ?? .unknown
            )
            if let existingIndex { snapshot.records[existingIndex] = record }
            else { snapshot.records.append(record) }
            try store.save(snapshot)
            return record
        } catch {
            var recoveryFailed = false
            if let installedProvider {
                do { try await registrationService.unregister(providerAt: installedProvider) }
                catch { recoveryFailed = true }
            }
            if fileManager.fileExists(atPath: destination.path) {
                do { try fileManager.removeItem(at: destination) }
                catch { recoveryFailed = true }
            }
            if hadExisting {
                let restore = fileManager.fileExists(atPath: backup.path) ? backup : previousDestination
                do {
                    try fileManager.moveItem(at: restore, to: destination)
                    let provider = try providerURL(in: destination)
                    try await registrationService.register(providerAt: provider)
                } catch { recoveryFailed = true }
            }
            if hadPrevious, fileManager.fileExists(atPath: olderPrevious.path) {
                do { try fileManager.moveItem(at: olderPrevious, to: previousDestination) }
                catch { recoveryFailed = true }
            }
            if recoveryFailed { throw ExtensionInstallerError.rollbackFailed }
            throw error
        }
    }

    private func uninstallUnlocked(id: ExtensionIdentity) async throws {
        var snapshot = try store.load()
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else {
            throw ExtensionInstallerError.notInstalled
        }
        let record = snapshot.records[index]
        let expectedRelativePath = managedRelativePath(for: id)
        guard record.relativeInstallPath == expectedRelativePath else {
            throw ExtensionInstallerError.unmanagedInstallPath
        }
        let destination = try managedURL(relativePath: expectedRelativePath)
        let previousDestination = try managedURL(relativePath: managedPreviousRelativePath(for: id))
        let provider = try providerURL(in: destination)
        let transaction = try managedURL(relativePath: "Staging/\(UUID().uuidString)")
        let backup = transaction.appendingPathComponent("Backup", isDirectory: true)
        let previousBackup = transaction.appendingPathComponent("Previous", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transaction) }
        try await registrationService.unregister(providerAt: provider)
        do {
            try fileManager.moveItem(at: destination, to: backup)
            if fileManager.fileExists(atPath: previousDestination.path) {
                try fileManager.moveItem(at: previousDestination, to: previousBackup)
            }
            snapshot.records.remove(at: index)
            try store.save(snapshot)
        } catch {
            do {
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.moveItem(at: backup, to: destination)
                }
                if fileManager.fileExists(atPath: previousBackup.path) {
                    try fileManager.moveItem(at: previousBackup, to: previousDestination)
                }
                try await registrationService.register(providerAt: provider)
            } catch {
                throw ExtensionInstallerError.rollbackFailed
            }
            throw error
        }
    }

    private func rollbackUnlocked(
        id: ExtensionIdentity,
        marketplaceReceipt refreshedReceipt: MarketplaceReleaseReceipt?
    ) async throws -> InstalledExtensionRecord {
        var snapshot = try store.load()
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else {
            throw ExtensionInstallerError.notInstalled
        }
        let current = snapshot.records[index]
        guard let previous = current.previousRelease else { throw ExtensionInstallerError.noPreviousRelease }
        let marketplaceReceipt: MarketplaceReleaseReceipt?
        if previous.origin == .marketplace {
            guard let refreshedReceipt,
                  refreshedReceipt.releaseIdentifier == previous.marketplaceReceipt?.releaseIdentifier,
                  refreshedReceipt.archiveSHA256 == previous.marketplaceReceipt?.archiveSHA256
            else { throw ExtensionInstallerError.staleMarketplaceEvidence }
            try validateMarketplaceEvidence(refreshedReceipt, maximumAge: 24 * 60 * 60)
            marketplaceReceipt = refreshedReceipt
        } else {
            marketplaceReceipt = nil
        }
        guard current.relativeInstallPath == managedRelativePath(for: id),
              previous.relativeInstallPath == managedPreviousRelativePath(for: id)
        else { throw ExtensionInstallerError.unmanagedInstallPath }

        let destination = try managedURL(relativePath: current.relativeInstallPath)
        let previousDestination = try managedURL(relativePath: previous.relativeInstallPath)
        let transaction = try managedURL(relativePath: "Staging/\(UUID().uuidString)")
        let currentBackup = transaction.appendingPathComponent("Current", isDirectory: true)
        let rollbackPrevious = transaction.appendingPathComponent("RollbackPrevious", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transaction) }
        let currentProvider = try providerURL(in: destination)
        try await registrationService.unregister(providerAt: currentProvider)
        var registeredRollbackProvider: URL?
        do {
            try fileManager.moveItem(at: destination, to: currentBackup)
            try fileManager.moveItem(at: previousDestination, to: destination)
            let package = try packageValidator.validate(
                packageRootURL: destination,
                context: previous.origin == .marketplace ? .marketplace : .localDeveloper
            )
            let signature = try signatureEvidence(for: package)
            guard package.manifest.id == id,
                  package.manifest.extensionVersion == previous.extensionVersion,
                  package.providerBundleIdentifier == previous.providerBundleIdentifier,
                  package.extensionBundleIdentifiers == previous.extensionBundleIdentifiers,
                  sha256(package.manifestData) == previous.manifestSHA256,
                  signature == previous.signature
            else { throw ExtensionInstallerError.installedCopyMismatch }
            if let receipt = marketplaceReceipt {
                try validate(package: package, signature: signature, against: receipt)
            }
            try await registrationService.register(providerAt: package.providerURL)
            registeredRollbackProvider = package.providerURL
            try fileManager.moveItem(at: currentBackup, to: previousDestination)
            let timestamp = now()
            let record = InstalledExtensionRecord(
                id: id,
                extensionVersion: previous.extensionVersion,
                providerBundleIdentifier: previous.providerBundleIdentifier,
                extensionBundleIdentifiers: previous.extensionBundleIdentifiers,
                relativeInstallPath: current.relativeInstallPath,
                manifestSHA256: previous.manifestSHA256,
                declaredPermissions: previous.declaredPermissions,
                declaredHostActions: previous.declaredHostActions,
                signature: previous.signature,
                origin: previous.origin,
                marketplaceReceipt: marketplaceReceipt,
                previousRelease: InstalledExtensionRelease(record: current, relativeInstallPath: previous.relativeInstallPath),
                marketplaceRevocationStatus: marketplaceReceipt?.revocation.status ?? .notRevoked,
                installedAt: current.installedAt,
                updatedAt: timestamp,
                desiredEnabled: current.desiredEnabled,
                localStatus: .installed,
                systemAuthorityStatus: current.systemAuthorityStatus
            )
            snapshot.records[index] = record
            try store.save(snapshot)
            return record
        } catch {
            var recoveryFailed = false
            if let registeredRollbackProvider {
                do { try await registrationService.unregister(providerAt: registeredRollbackProvider) }
                catch { recoveryFailed = true }
            }
            if fileManager.fileExists(atPath: destination.path) {
                do { try fileManager.moveItem(at: destination, to: rollbackPrevious) }
                catch { recoveryFailed = true }
            }
            if fileManager.fileExists(atPath: currentBackup.path) {
                do { try fileManager.moveItem(at: currentBackup, to: destination) }
                catch { recoveryFailed = true }
            } else if fileManager.fileExists(atPath: previousDestination.path) {
                do { try fileManager.moveItem(at: previousDestination, to: destination) }
                catch { recoveryFailed = true }
            }
            if fileManager.fileExists(atPath: rollbackPrevious.path) {
                do { try fileManager.moveItem(at: rollbackPrevious, to: previousDestination) }
                catch { recoveryFailed = true }
            }
            do {
                let provider = try providerURL(in: destination)
                try await registrationService.register(providerAt: provider)
            } catch {
                recoveryFailed = true
            }
            if recoveryFailed { throw ExtensionInstallerError.rollbackFailed }
            throw error
        }
    }

    private func validateMarketplaceEvidence(
        _ receipt: MarketplaceReleaseReceipt,
        maximumAge: TimeInterval
    ) throws {
        let timestamp = now()
        guard receipt.revocation.status == .notRevoked else {
            throw ExtensionInstallerError.revokedMarketplaceRelease
        }
        guard maximumAge >= 0,
              receipt.compatibility.evaluatedAt <= timestamp,
              receipt.revocation.checkedAt <= timestamp,
              timestamp.timeIntervalSince(receipt.compatibility.evaluatedAt) <= maximumAge,
              timestamp.timeIntervalSince(receipt.revocation.checkedAt) <= maximumAge
        else { throw ExtensionInstallerError.staleMarketplaceEvidence }
    }

    private func validateArchive(_ archiveURL: URL, against receipt: MarketplaceReleaseReceipt) throws {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 0, UInt64(size) == receipt.archiveByteCount else {
            throw ExtensionInstallerError.archiveSizeMismatch
        }
        guard try archiveSHA256(archiveURL) == receipt.archiveSHA256.lowercased() else {
            throw ExtensionInstallerError.archiveDigestMismatch
        }
    }

    private func validate(
        package: ValidatedPackage,
        signature: InstalledCodeSignature,
        against receipt: MarketplaceReleaseReceipt
    ) throws {
        guard receipt.validationPolicyVersion == 1,
              package.manifest.id == receipt.extensionIdentity,
              package.manifest.extensionVersion == receipt.extensionVersion,
              package.providerBundleIdentifier == receipt.providerBundleIdentifier,
              package.extensionBundleIdentifiers == receipt.extensionBundleIdentifiers,
              signature.teamIdentifier == receipt.teamIdentifier,
              receipt.manifestSHA256.map({ sha256(package.manifestData) == $0.lowercased() }) ?? true
        else { throw ExtensionInstallerError.marketplaceReceiptMismatch }

        let evidence = receipt.compatibility
        let sdkVersion = ExtensionVersion(
            major: evidence.sdkVersion.major,
            minor: evidence.sdkVersion.minor,
            patch: evidence.sdkVersion.patch
        )
        guard let artifact = package.packageManifest.artifact.appExtension,
              package.manifest.supportedHostVersions.contains(evidence.hostVersion),
              package.manifest.supportedSDKVersions.contains(sdkVersion),
              package.manifest.apiVersion.major == evidence.sdkVersion.major,
              artifact.minimumMacOSVersion <= evidence.macOSVersion,
              artifact.protocolVersions.contains(evidence.protocolVersion),
              artifact.architectures.contains(evidence.architecture)
        else { throw ExtensionInstallerError.incompatibleMarketplaceRelease }
    }

    private func managedRelativePath(for id: ExtensionIdentity) -> String {
        "Extensions/\(id.rawValue)"
    }

    private func managedPreviousRelativePath(for id: ExtensionIdentity) -> String {
        "RetainedReleases/\(id.rawValue)"
    }

    private func managedURL(relativePath: String) throws -> URL {
        var componentURL = rootURL
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }),
              (try? fileManager.destinationOfSymbolicLink(atPath: rootURL.path)) == nil
        else { throw ExtensionInstallerError.unmanagedInstallPath }
        for component in components {
            componentURL.appendPathComponent(String(component))
            if (try? fileManager.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                throw ExtensionInstallerError.unmanagedInstallPath
            }
        }
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let result = rootURL
            .appendingPathComponent(relativePath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard result.path.hasPrefix(resolvedRoot.path + "/") else {
            throw ExtensionInstallerError.unmanagedInstallPath
        }
        return result
    }

    private func providerURL(in destination: URL) throws -> URL {
        let payload = destination.appendingPathComponent("payload", isDirectory: true)
        let apps = try fileManager.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw ExtractedPackageError.invalidPackageLayout }
        return apps[0]
    }

    private func signatureEvidence(for package: ValidatedPackage) throws -> InstalledCodeSignature {
        let provider = try signatureValidator.validateCode(at: package.providerURL)
        var extensionRequirements: [String: String] = [:]
        for (url, identifier) in zip(package.extensionURLs, package.extensionBundleIdentifiers) {
            let signature = try signatureValidator.validateCode(at: url)
            guard signature.teamIdentifier == provider.teamIdentifier else {
                throw ExtensionInstallerError.teamMismatch
            }
            extensionRequirements[identifier] = signature.designatedRequirement
        }
        return InstalledCodeSignature(
            teamIdentifier: provider.teamIdentifier,
            providerDesignatedRequirement: provider.designatedRequirement,
            extensionDesignatedRequirements: extensionRequirements
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func archiveSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
