import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
import ZIPFoundation

public enum ExtensionToolError: Error, Equatable, LocalizedError {
    case validation(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case let .validation(message), let .io(message): message
        }
    }
}

public struct ExtensionToolEntryPoint: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let presentationMode: String
    public let sceneName: String?
}

public struct ExtensionToolInspection: Codable, Equatable, Sendable {
    public let teamIdentifier: String
    public let signerRequirement: String
    public let identity: String
    public let version: String
    public let permissions: [ExtensionDeclaredPermission]
    public let hostActions: [String]
    public let entryPoints: [ExtensionToolEntryPoint]

    public func humanReadable() -> String {
        let permissionLines = permissions.map {
            "  \($0.kind.rawValue) (\($0.owner.rawValue), \($0.required ? "required" : "optional"))"
        }
        let actionLines = hostActions.map { "  \($0)" }
        let entryLines = entryPoints.map {
            "  \($0.id) [\($0.kind), \($0.presentationMode)\($0.sceneName.map { ", scene=\($0)" } ?? "")]"
        }
        return ([
            "Identity: \(identity)",
            "Version: \(version)",
            "Team: \(teamIdentifier)",
            "Signer: \(signerRequirement)",
            "Permissions:",
        ] + (permissionLines.isEmpty ? ["  none"] : permissionLines) + [
            "Host actions:",
        ] + (actionLines.isEmpty ? ["  none"] : actionLines) + [
            "Entry points:",
        ] + entryLines).joined(separator: "\n")
    }
}

public struct ExtensionToolService {
    private let archiveValidator: any PackageArchiveValidating
    private let packageValidator: any ExtractedPackageValidating
    private let signatureValidator: any CodeSignatureValidating
    private let fileManager: FileManager

    public init(
        archiveValidator: any PackageArchiveValidating = ZIPPackageArchiveValidator(),
        packageValidator: any ExtractedPackageValidating = DefaultExtractedPackageValidator(),
        signatureValidator: any CodeSignatureValidating = SecurityCodeSignatureValidator(),
        fileManager: FileManager = .default
    ) {
        self.archiveValidator = archiveValidator
        self.packageValidator = packageValidator
        self.signatureValidator = signatureValidator
        self.fileManager = fileManager
    }

    public func validate(archiveURL: URL) throws {
        _ = try inspect(archiveURL: archiveURL)
    }

    public func inspect(archiveURL: URL) throws -> ExtensionToolInspection {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ExtensionToolError.io("Archive does not exist: \(archiveURL.path)")
        }
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        do {
            try archiveValidator.validateAndExtract(archiveURL: archiveURL, to: root)
            let package = try packageValidator.validate(packageRootURL: root)
            let signature = try validateSignatures(package)
            return inspection(package: package, signature: signature)
        } catch let error as ExtensionToolError {
            throw error
        } catch {
            throw ExtensionToolError.validation(String(describing: error))
        }
    }

    @discardableResult
    public func package(providerURL: URL, outputURL: URL) throws -> ExtensionToolInspection {
        guard providerURL.pathExtension == "app",
              fileManager.fileExists(atPath: providerURL.path)
        else { throw ExtensionToolError.io("Provider app does not exist: \(providerURL.path)") }
        guard outputURL.pathExtension == "notchkitextension" else {
            throw ExtensionToolError.io("Output must use the .notchkitextension extension")
        }
        let outputParent = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputParent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExtensionToolError.io("Output directory does not exist: \(outputParent.path)")
        }

        let embeddedManifestURL = providerURL
            .appendingPathComponent("Contents/Resources/NotchKitExtension/manifest.json")
        let manifestData: Data
        do { manifestData = try Data(contentsOf: embeddedManifestURL) }
        catch { throw ExtensionToolError.validation("Missing embedded manifest") }
        do { _ = try StrictExtensionPackageManifestValidator().decodeAndValidate(data: manifestData) }
        catch { throw ExtensionToolError.validation(String(describing: error)) }

        let workspace = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = workspace.appendingPathComponent("package", isDirectory: true)
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        let stagedProvider = payload.appendingPathComponent(providerURL.lastPathComponent, isDirectory: true)
        let temporaryArchive = outputParent.appendingPathComponent(".\(UUID().uuidString).notchkitextension")
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: temporaryArchive)
        }

        do {
            try rejectSymbolicLinks(in: providerURL)
            try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
            try fileManager.copyItem(at: providerURL, to: stagedProvider)
            try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            let package = try packageValidator.validate(packageRootURL: staging)
            _ = try validateSignatures(package)
            try writeArchive(from: staging, to: temporaryArchive)
            let inspection = try inspect(archiveURL: temporaryArchive)
            if fileManager.fileExists(atPath: outputURL.path) {
                _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryArchive)
            } else {
                try fileManager.moveItem(at: temporaryArchive, to: outputURL)
            }
            return inspection
        } catch let error as ExtensionToolError {
            throw error
        } catch let error as PackageArchiveError {
            throw ExtensionToolError.validation(String(describing: error))
        } catch let error as ExtractedPackageError {
            throw ExtensionToolError.validation(String(describing: error))
        } catch let error as CodeSignatureValidationError {
            throw ExtensionToolError.validation(String(describing: error))
        } catch {
            throw ExtensionToolError.io(error.localizedDescription)
        }
    }

    private func validateSignatures(_ package: ValidatedPackage) throws -> CodeSignatureInfo {
        let provider = try signatureValidator.validateCode(at: package.providerURL)
        for extensionURL in package.extensionURLs {
            let nested = try signatureValidator.validateCode(at: extensionURL)
            guard nested.teamIdentifier == provider.teamIdentifier else {
                throw ExtensionToolError.validation("Provider and app extension signing teams do not match")
            }
        }
        return provider
    }

    private func inspection(package: ValidatedPackage, signature: CodeSignatureInfo) -> ExtensionToolInspection {
        ExtensionToolInspection(
            teamIdentifier: signature.teamIdentifier,
            signerRequirement: signature.designatedRequirement,
            identity: package.manifest.id.rawValue,
            version: package.manifest.extensionVersion.description,
            permissions: package.packageManifest.permissions.sorted { $0.kind.rawValue < $1.kind.rawValue },
            hostActions: package.packageManifest.hostActions.map(\.rawValue).sorted(),
            entryPoints: package.packageManifest.entryPoints.map {
                ExtensionToolEntryPoint(
                    id: $0.id,
                    kind: $0.entryPoint.kind.rawValue,
                    presentationMode: $0.presentationMode.rawValue,
                    sceneName: $0.sceneName
                )
            }
        )
    }

    private func rejectSymbolicLinks(in root: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw ExtensionToolError.io("Cannot enumerate provider app") }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ExtensionToolError.validation("Symbolic links are not permitted: \(url.path)")
            }
        }
    }

    private func writeArchive(from root: URL, to archiveURL: URL) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw ExtensionToolError.io("Cannot enumerate package staging directory") }
        let urls = enumerator.compactMap { $0 as? URL }.sorted {
            relativePath(of: $0, under: root) < relativePath(of: $1, under: root)
        }
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let fixedDate = Date(timeIntervalSince1970: 315_532_800)
        for url in urls {
            let values = try url.resourceValues(forKeys: Set(keys))
            let path = relativePath(of: url, under: root)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
            if values.isDirectory == true {
                try archive.addEntry(
                    with: path + "/",
                    type: .directory,
                    uncompressedSize: Int64(0),
                    modificationDate: fixedDate,
                    permissions: permissions,
                    compressionMethod: .none
                ) { _, _ in Data() }
            } else if values.isRegularFile == true {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try archive.addEntry(
                    with: path,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    modificationDate: fixedDate,
                    permissions: permissions,
                    compressionMethod: .deflate
                ) { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<min(start + size, data.count))
                }
            } else {
                throw ExtensionToolError.validation("Unsupported package item: \(path)")
            }
        }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }
}
