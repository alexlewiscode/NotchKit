import Foundation
import NotchExtensionSDK

public struct ValidatedPackage: Sendable {
    public let packageRootURL: URL
    public let packageManifest: ExtensionPackageManifest
    public var manifest: ExtensionMetadata { packageManifest.metadata }
    public let manifestData: Data
    public let providerURL: URL
    public let providerBundleIdentifier: String
    public let extensionURLs: [URL]
    public let extensionBundleIdentifiers: [String]
}

public enum ExtractedPackageError: Error, Equatable {
    case missingManifest
    case invalidManifest
    case unsupportedManifestSchema(Int)
    case invalidArtifact
    case invalidPackageLayout
    case missingEmbeddedManifest
    case embeddedManifestMismatch
    case invalidProviderPlist
    case invalidProviderIdentity
    case invalidProviderVersion
    case missingExtensions
    case invalidExtensionPlist(String)
    case invalidExtensionIdentity(String)
    case metadataIdentityMatchesExtensionBundle
    case invalidExtensionVersion(String)
    case invalidExtensionPoint(String)
    case unexpectedAppExtension(String)
}

public protocol ExtractedPackageValidating: Sendable {
    func validate(packageRootURL: URL) throws -> ValidatedPackage
}

public struct DefaultExtractedPackageValidator: ExtractedPackageValidating, Sendable {
    private let manifestValidator: StrictExtensionPackageManifestValidator

    public init(manifestValidator: StrictExtensionPackageManifestValidator = StrictExtensionPackageManifestValidator()) {
        self.manifestValidator = manifestValidator
    }

    public func validate(packageRootURL: URL) throws -> ValidatedPackage {
        let manifestURL = packageRootURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw ExtractedPackageError.missingManifest
        }
        let packageManifest: ExtensionPackageManifest
        do { packageManifest = try manifestValidator.decodeAndValidate(data: manifestData) }
        catch { throw ExtractedPackageError.invalidManifest }
        guard packageManifest.artifact.kind == .appExtension,
              let artifact = packageManifest.artifact.appExtension
        else { throw ExtractedPackageError.invalidArtifact }
        let manifest = packageManifest.metadata
        guard manifest.id.rawValue != artifact.extensionBundleIdentifier else {
            throw ExtractedPackageError.metadataIdentityMatchesExtensionBundle
        }

        let rootItems = (try? FileManager.default.contentsOfDirectory(
            at: packageRootURL,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        guard Set(rootItems.map(\.lastPathComponent)) == ["manifest.json", "payload"] else {
            throw ExtractedPackageError.invalidPackageLayout
        }

        let payload = packageRootURL.appendingPathComponent("payload", isDirectory: true)
        let payloadItems = (try? FileManager.default.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let providers = payloadItems.filter { $0.pathExtension == "app" }
        guard providers.count == 1, payloadItems.count == 1 else {
            throw ExtractedPackageError.invalidPackageLayout
        }
        let providerURL = providers[0]
        let embeddedManifestURL = providerURL
            .appendingPathComponent("Contents/Resources/NotchKitExtension/manifest.json")
        guard let embedded = try? Data(contentsOf: embeddedManifestURL) else {
            throw ExtractedPackageError.missingEmbeddedManifest
        }
        guard embedded == manifestData else { throw ExtractedPackageError.embeddedManifestMismatch }

        let providerInfo = try plist(at: providerURL.appendingPathComponent("Contents/Info.plist"), error: .invalidProviderPlist)
        guard let providerID = providerInfo["CFBundleIdentifier"] as? String, !providerID.isEmpty else {
            throw ExtractedPackageError.invalidProviderIdentity
        }
        guard providerID == artifact.providerBundleIdentifier else {
            throw ExtractedPackageError.invalidProviderIdentity
        }
        guard version(in: providerInfo) == manifest.extensionVersion.description else {
            throw ExtractedPackageError.invalidProviderVersion
        }

        let extensionsURL = providerURL.appendingPathComponent("Contents/Extensions", isDirectory: true)
        let expectedExtensionURL = extensionsURL.appendingPathComponent(
            "\(artifact.extensionBundleIdentifier.split(separator: ".").last!).appex",
            isDirectory: true
        )
        let nestedItems = (try? FileManager.default.contentsOfDirectory(
            at: extensionsURL,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        guard nestedItems.count == 1, nestedItems[0].standardizedFileURL == expectedExtensionURL.standardizedFileURL else {
            throw ExtractedPackageError.missingExtensions
        }
        let allNestedAppExtensions = recursiveAppExtensions(in: providerURL)
        guard allNestedAppExtensions.count == 1,
              allNestedAppExtensions[0].standardizedFileURL == expectedExtensionURL.standardizedFileURL
        else { throw ExtractedPackageError.unexpectedAppExtension(allNestedAppExtensions.first?.lastPathComponent ?? "unknown") }
        let extensionInfo = try plist(
            at: expectedExtensionURL.appendingPathComponent("Contents/Info.plist"),
            error: .invalidExtensionPlist(expectedExtensionURL.lastPathComponent)
        )
        guard extensionInfo["CFBundleIdentifier"] as? String == artifact.extensionBundleIdentifier else {
            throw ExtractedPackageError.invalidExtensionIdentity(expectedExtensionURL.lastPathComponent)
        }
        guard version(in: extensionInfo) == manifest.extensionVersion.description else {
            throw ExtractedPackageError.invalidExtensionVersion(artifact.extensionBundleIdentifier)
        }
        guard let attributes = extensionInfo["EXAppExtensionAttributes"] as? [String: Any],
              attributes["EXExtensionPointIdentifier"] as? String == artifact.extensionPointIdentifier
        else { throw ExtractedPackageError.invalidExtensionPoint(artifact.extensionBundleIdentifier) }
        return ValidatedPackage(
            packageRootURL: packageRootURL,
            packageManifest: packageManifest,
            manifestData: manifestData,
            providerURL: providerURL,
            providerBundleIdentifier: providerID,
            extensionURLs: [expectedExtensionURL],
            extensionBundleIdentifiers: [artifact.extensionBundleIdentifier]
        )
    }

    private func plist(at url: URL, error: ExtractedPackageError) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = value as? [String: Any]
        else { throw error }
        return dictionary
    }

    private func version(in plist: [String: Any]) -> String? {
        plist["CFBundleShortVersionString"] as? String
    }

    private func recursiveAppExtensions(in providerURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: providerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "appex" {
            result.append(url)
            enumerator.skipDescendants()
        }
        return result
    }
}
