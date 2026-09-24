import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
import ZIPFoundation

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeArchive(at url: URL, entries: [(String, Data)], compression: CompressionMethod = .none) throws {
    let archive = try Archive(url: url, accessMode: .create)
    for (path, data) in entries {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: compression
        ) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<min(start + size, data.count))
        }
    }
}

func metadata(
    id: String = "com.example.feature.timer",
    version: String = "1.2.3",
    source: ExtensionSource = .localDeveloper
) throws -> ExtensionMetadata {
    ExtensionMetadata(
        id: try ExtensionIdentity(id),
        displayName: "Example",
        iconSystemName: "puzzlepiece",
        extensionVersion: ExtensionVersion(version)!,
        supportedHostVersions: ExtensionVersionRange(minimum: ExtensionVersion("1.0.0")!),
        supportedSDKVersions: ExtensionVersionRange(minimum: ExtensionVersion("1.0.0")!),
        capabilities: [.openDestination],
        artifactKind: .appExtension,
        entryPoints: [ExtensionEntryPoint(id: "example.main", kind: .openDestination)],
        defaultEnabled: false,
        source: source
    )
}

func packageManifest(
    id: String = "com.example.feature.timer",
    version: String = "1.2.3",
    source: ExtensionSource = .localDeveloper
) throws -> ExtensionPackageManifest {
    let metadata = try metadata(id: id, version: version, source: source)
    return ExtensionPackageManifest(
        metadata: metadata,
        artifact: ExtensionPackageArtifact(
            kind: .appExtension,
            appExtension: AppExtensionArtifactMetadata(
                providerBundleIdentifier: "com.example.provider",
                extensionBundleIdentifier: "com.example.provider.TimerExtension",
                extensionPointIdentifier: "com.example.extension-point",
                minimumMacOSVersion: ExtensionVersion("26.0.0")!,
                protocolVersions: ExtensionProtocolVersionRange(minimum: 1, maximum: 1),
                architectures: [.arm64]
            )
        ),
        permissions: [.camera(usageDescriptionKey: "NSCameraUsageDescription")],
        hostActions: [.openDestination],
        entryPoints: [ExtensionPackageEntryPoint(
            entryPoint: metadata.entryPoints[0],
            presentationMode: .remoteScene,
            sceneName: "main"
        )]
    )
}

func makeExtractedPackage(
    at root: URL,
    embeddedData: Data? = nil,
    version: String = "1.2.3",
    source: ExtensionSource = .localDeveloper
) throws -> Data {
    let manifest = try JSONEncoder().encode(packageManifest(version: version, source: source))
    let provider = root.appendingPathComponent("payload/Provider.app/Contents", isDirectory: true)
    let extensionURL = provider.appendingPathComponent("Extensions/TimerExtension.appex/Contents", isDirectory: true)
    let resource = provider.appendingPathComponent("Resources/NotchKitExtension", isDirectory: true)
    try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
    try manifest.write(to: root.appendingPathComponent("manifest.json"))
    try (embeddedData ?? manifest).write(to: resource.appendingPathComponent("manifest.json"))
    try writePlist([
        "CFBundleIdentifier": "com.example.provider",
        "CFBundleShortVersionString": version,
    ], to: provider.appendingPathComponent("Info.plist"))
    try writePlist([
        "CFBundleIdentifier": "com.example.provider.TimerExtension",
        "CFBundleShortVersionString": version,
        "EXAppExtensionAttributes": [
            "EXExtensionPointIdentifier": "com.example.extension-point",
        ],
    ], to: extensionURL.appendingPathComponent("Info.plist"))
    return manifest
}

func writePlist(_ value: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    try data.write(to: url)
}

struct FakeSignatureValidator: CodeSignatureValidating {
    let team: String
    var extensionTeam: String?
    var isDeveloperID = true

    func validateCode(at url: URL) throws -> CodeSignatureInfo {
        let selected = url.pathExtension == "appex" ? (extensionTeam ?? team) : team
        return CodeSignatureInfo(
            teamIdentifier: selected,
            designatedRequirement: "anchor \(selected) \(url.lastPathComponent)",
            isDeveloperID: isDeveloperID
        )
    }
}

final class CountingSignatureValidator: CodeSignatureValidating, @unchecked Sendable {
    private(set) var validatedURLs: [URL] = []

    func validateCode(at url: URL) throws -> CodeSignatureInfo {
        validatedURLs.append(url)
        return CodeSignatureInfo(teamIdentifier: "TEAM", designatedRequirement: "anchor \(url.lastPathComponent)")
    }
}

final class CountingPackageValidator: ExtractedPackageValidating, @unchecked Sendable {
    private(set) var validatedRoots: [URL] = []

    func validate(packageRootURL: URL) throws -> ValidatedPackage {
        validatedRoots.append(packageRootURL)
        return try DefaultExtractedPackageValidator().validate(packageRootURL: packageRootURL)
    }
}

final class FakeRegistrationService: ExtensionRegistrationServicing, @unchecked Sendable {
    var registered: [URL] = []
    var unregistered: [URL] = []
    var registrationError: Error?

    func register(providerAt url: URL) async throws {
        if let registrationError { throw registrationError }
        registered.append(url)
    }

    func unregister(providerAt url: URL) async throws { unregistered.append(url) }
}

struct CopyingArchiveValidator: PackageArchiveValidating {
    let source: URL
    func validateAndExtract(archiveURL: URL, to destinationURL: URL) throws -> PackageArchivePreflight {
        try FileManager.default.copyItem(at: source, to: destinationURL)
        return PackageArchivePreflight(entryCount: 1, compressedBytes: 1, expandedBytes: 1)
    }
}

enum TestError: Error, Equatable { case expected }

final class FailingStore: InstalledExtensionStore, @unchecked Sendable {
    var snapshot: InstalledExtensionSnapshot
    var failSave = false
    init(_ snapshot: InstalledExtensionSnapshot = InstalledExtensionSnapshot()) { self.snapshot = snapshot }
    func load() throws -> InstalledExtensionSnapshot { snapshot }
    func save(_ snapshot: InstalledExtensionSnapshot) throws {
        if failSave { throw TestError.expected }
        self.snapshot = snapshot
    }
}
