import Foundation
import CryptoKit
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
    case rollbackFailed
    case installedCopyMismatch
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

    @discardableResult
    public func install(archiveURL: URL) async throws -> InstalledExtensionRecord {
        var snapshot = try store.load()
        let transaction = rootURL.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        let extracted = transaction.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transaction) }
        try archiveValidator.validateAndExtract(archiveURL: archiveURL, to: extracted)
        let package = try packageValidator.validate(packageRootURL: extracted)
        let signature = try signatureEvidence(for: package)

        let existingIndex = snapshot.records.firstIndex { $0.id == package.manifest.id }
        if let existingIndex,
           snapshot.records[existingIndex].signature.teamIdentifier != signature.teamIdentifier {
            throw ExtensionInstallerError.updateTeamMismatch
        }
        let relativePath = managedRelativePath(for: package.manifest.id)
        let destination = rootURL.appendingPathComponent(relativePath, isDirectory: true)
        let incoming = transaction.appendingPathComponent("Incoming", isDirectory: true)
        try fileManager.moveItem(at: extracted, to: incoming)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backup = transaction.appendingPathComponent("Backup", isDirectory: true)
        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting { try fileManager.moveItem(at: destination, to: backup) }
        var installedProvider: URL?
        do {
            try fileManager.moveItem(at: incoming, to: destination)
            let installedPackage = try packageValidator.validate(packageRootURL: destination)
            guard installedPackage.packageManifest == package.packageManifest,
                  installedPackage.manifestData == package.manifestData
            else { throw ExtensionInstallerError.installedCopyMismatch }
            let installedSignature = try signatureEvidence(for: installedPackage)
            guard installedSignature.teamIdentifier == signature.teamIdentifier else {
                throw ExtensionInstallerError.installedCopyMismatch
            }
            if let existingIndex,
               snapshot.records[existingIndex].signature.teamIdentifier != installedSignature.teamIdentifier {
                throw ExtensionInstallerError.updateTeamMismatch
            }
            let provider = installedPackage.providerURL
            installedProvider = provider
            try await registrationService.register(providerAt: provider)
            let timestamp = now()
            let existing = existingIndex.map { snapshot.records[$0] }
            let record = InstalledExtensionRecord(
                id: installedPackage.manifest.id,
                extensionVersion: installedPackage.manifest.extensionVersion,
                providerBundleIdentifier: installedPackage.providerBundleIdentifier,
                extensionBundleIdentifiers: installedPackage.extensionBundleIdentifiers,
                relativeInstallPath: relativePath,
                manifestSHA256: SHA256.hash(data: installedPackage.manifestData).map { String(format: "%02x", $0) }.joined(),
                declaredPermissions: installedPackage.packageManifest.permissions,
                declaredHostActions: installedPackage.packageManifest.hostActions,
                signature: installedSignature,
                installedAt: existing?.installedAt ?? timestamp,
                updatedAt: timestamp,
                desiredEnabled: existing?.desiredEnabled ?? installedPackage.manifest.defaultEnabled,
                localStatus: .installed,
                systemAuthorityStatus: existing?.systemAuthorityStatus ?? .unknown
            )
            if let existingIndex { snapshot.records[existingIndex] = record }
            else { snapshot.records.append(record) }
            do { try store.save(snapshot) }
            catch {
                throw error
            }
            if hadExisting { try? fileManager.removeItem(at: backup) }
            return record
        } catch {
            if let installedProvider {
                try? await registrationService.unregister(providerAt: installedProvider)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            if hadExisting, fileManager.fileExists(atPath: backup.path) {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                    if let restoredProvider = try? providerURL(in: destination) {
                        try? await registrationService.register(providerAt: restoredProvider)
                    }
                }
                catch { throw ExtensionInstallerError.rollbackFailed }
            }
            throw error
        }
    }

    public func uninstall(id: ExtensionIdentity) async throws {
        var snapshot = try store.load()
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else {
            throw ExtensionInstallerError.notInstalled
        }
        let record = snapshot.records[index]
        let expectedRelativePath = managedRelativePath(for: id)
        guard record.relativeInstallPath == expectedRelativePath else {
            throw ExtensionInstallerError.unmanagedInstallPath
        }
        let destination = rootURL.appendingPathComponent(expectedRelativePath, isDirectory: true).standardizedFileURL
        guard destination.path.hasPrefix(rootURL.path + "/") else {
            throw ExtensionInstallerError.unmanagedInstallPath
        }
        let providerURL = try providerURL(in: destination)
        let transaction = rootURL.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        let backup = transaction.appendingPathComponent("Backup", isDirectory: true)
        try fileManager.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: transaction) }
        try await registrationService.unregister(providerAt: providerURL)
        do { try fileManager.moveItem(at: destination, to: backup) }
        catch {
            try? await registrationService.register(providerAt: providerURL)
            throw error
        }
        snapshot.records.remove(at: index)
        do { try store.save(snapshot) }
        catch {
            try fileManager.moveItem(at: backup, to: destination)
            try? await registrationService.register(providerAt: providerURL)
            throw error
        }
    }

    private func managedRelativePath(for id: ExtensionIdentity) -> String {
        "Extensions/\(id.rawValue)"
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

}
