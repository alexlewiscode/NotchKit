import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
@testable import NotchExtensionToolSupport
import XCTest

final class ExtensionToolTests: XCTestCase {
    func testParserAcceptsDocumentedCommandsAndResolvesRelativePaths() throws {
        let current = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
        XCTAssertEqual(
            try ExtensionToolCommandParser.parse(["validate", "one.notchkitextension"], currentDirectoryURL: current),
            .validate(archiveURL: URL(fileURLWithPath: "/tmp/work/one.notchkitextension"))
        )
        XCTAssertEqual(
            try ExtensionToolCommandParser.parse(["inspect", "/tmp/one.notchkitextension", "--json"], currentDirectoryURL: current),
            .inspect(archiveURL: URL(fileURLWithPath: "/tmp/one.notchkitextension"), json: true)
        )
        XCTAssertEqual(
            try ExtensionToolCommandParser.parse(
                ["package", "Provider.app", "--output", "out.notchkitextension"],
                currentDirectoryURL: current
            ),
            .package(
                providerURL: URL(fileURLWithPath: "/tmp/work/Provider.app"),
                outputURL: URL(fileURLWithPath: "/tmp/work/out.notchkitextension"),
                context: .localDeveloper
            )
        )
        XCTAssertEqual(
            try ExtensionToolCommandParser.parse(
                ["package", "Provider.app", "--output", "marketplace.notchkitextension", "--marketplace"],
                currentDirectoryURL: current
            ),
            .package(
                providerURL: URL(fileURLWithPath: "/tmp/work/Provider.app"),
                outputURL: URL(fileURLWithPath: "/tmp/work/marketplace.notchkitextension"),
                context: .marketplace
            )
        )
    }

    func testParserRejectsUnknownFlagsAndArgumentOrders() {
        let current = URL(fileURLWithPath: "/tmp", isDirectory: true)
        for arguments in [
            [],
            ["inspect"],
            ["inspect", "a", "--verbose"],
            ["package", "Provider.app", "out.notchkitextension"],
            ["package", "Provider.app", "out.notchkitextension", "--output"],
        ] {
            XCTAssertThrowsError(try ExtensionToolCommandParser.parse(arguments, currentDirectoryURL: current)) {
                XCTAssertEqual($0 as? ExtensionToolUsageError, .invalidArguments)
            }
        }
    }

    func testPackageBuildsAndRevalidatesArchiveWithInjectedSigner() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let provider = workspace.appendingPathComponent("Provider.app", isDirectory: true)
        let manifest = try makeProvider(at: provider)
        let output = workspace.appendingPathComponent("timer.notchkitextension")
        let signer = FakeSignatureValidator()
        let service = ExtensionToolService(signatureValidator: signer)

        let packaged = try service.package(providerURL: provider, outputURL: output)
        let inspected = try service.inspect(archiveURL: output)

        XCTAssertEqual(packaged, inspected)
        XCTAssertEqual(inspected.identity, manifest.metadata.id.rawValue)
        XCTAssertEqual(inspected.version, manifest.metadata.extensionVersion.description)
        XCTAssertEqual(inspected.teamIdentifier, "TEAM")
        XCTAssertEqual(inspected.hostActions, ["open-destination"])
        XCTAssertEqual(inspected.entryPoints.map(\.id), ["main"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(signer.validatedURLs.count, 6)
    }

    func testPackageRejectsProviderSymlink() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let provider = workspace.appendingPathComponent("Provider.app", isDirectory: true)
        _ = try makeProvider(at: provider)
        try FileManager.default.createSymbolicLink(
            at: provider.appendingPathComponent("Contents/link"),
            withDestinationURL: provider.appendingPathComponent("Contents/Info.plist")
        )

        XCTAssertThrowsError(try ExtensionToolService(signatureValidator: FakeSignatureValidator()).package(
            providerURL: provider,
            outputURL: workspace.appendingPathComponent("out.notchkitextension")
        )) {
            guard case .validation = $0 as? ExtensionToolError else {
                return XCTFail("Expected validation error, got \($0)")
            }
        }
    }

    func testRunnerUsesStableExitCodes() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = workspace.appendingPathComponent("bad.notchkitextension")
        try Data().write(to: archive)
        var errors: [String] = []
        let runner = ExtensionToolRunner(
            service: ExtensionToolService(
                archiveValidator: RejectingArchiveValidator(),
                signatureValidator: FakeSignatureValidator()
            ),
            output: { _ in },
            errorOutput: { errors.append($0) }
        )

        XCTAssertEqual(runner.run(arguments: [], currentDirectoryURL: workspace), 2)
        XCTAssertEqual(
            runner.run(arguments: ["validate", archive.path], currentDirectoryURL: workspace),
            1
        )
        XCTAssertEqual(
            runner.run(arguments: ["validate", "missing.notchkitextension"], currentDirectoryURL: workspace),
            2
        )
        XCTAssertEqual(errors.count, 3)
    }
}

private final class FakeSignatureValidator: CodeSignatureValidating, @unchecked Sendable {
    private(set) var validatedURLs: [URL] = []

    func validateCode(at url: URL) throws -> CodeSignatureInfo {
        validatedURLs.append(url)
        return CodeSignatureInfo(teamIdentifier: "TEAM", designatedRequirement: "anchor apple generic")
    }
}

private struct RejectingArchiveValidator: PackageArchiveValidating {
    func validateAndExtract(archiveURL: URL, to destinationURL: URL) throws -> PackageArchivePreflight {
        throw PackageArchiveError.unreadableArchive
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func makeProvider(at provider: URL) throws -> ExtensionPackageManifest {
    let id = try ExtensionIdentity("com.example.timer")
    let version = ExtensionVersion("1.2.3")!
    let entryPoint = ExtensionEntryPoint(id: "main", kind: .openDestination)
    let manifest = ExtensionPackageManifest(
        metadata: ExtensionMetadata(
            id: id,
            displayName: "Timer",
            iconSystemName: "timer",
            extensionVersion: version,
            supportedHostVersions: .init(minimum: ExtensionVersion("1.0.0")!),
            supportedSDKVersions: .init(minimum: ExtensionVersion("1.0.0")!),
            capabilities: [.openDestination],
            artifactKind: .appExtension,
            entryPoints: [entryPoint],
            defaultEnabled: true,
            source: .localDeveloper
        ),
        artifact: .init(kind: .appExtension, appExtension: .init(
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifier: "com.example.provider.Timer",
            extensionPointIdentifier: "com.example.point",
            minimumMacOSVersion: ExtensionVersion("26.0.0")!,
            protocolVersions: .init(minimum: 1, maximum: 1),
            architectures: [.arm64]
        )),
        permissions: [.camera(usageDescriptionKey: "NSCameraUsageDescription")],
        hostActions: [.openDestination],
        entryPoints: [.init(entryPoint: entryPoint, presentationMode: .declarative)]
    )
    let contents = provider.appendingPathComponent("Contents", isDirectory: true)
    let extensionContents = contents.appendingPathComponent("Extensions/Timer.appex/Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources/NotchKitExtension", isDirectory: true)
    try FileManager.default.createDirectory(at: extensionContents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try writePlist([
        "CFBundleIdentifier": "com.example.provider",
        "CFBundleShortVersionString": "1.2.3",
    ], to: contents.appendingPathComponent("Info.plist"))
    try writePlist([
        "CFBundleIdentifier": "com.example.provider.Timer",
        "CFBundleShortVersionString": "1.2.3",
        "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": "com.example.point"],
    ], to: extensionContents.appendingPathComponent("Info.plist"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(manifest).write(to: resources.appendingPathComponent("manifest.json"))
    return manifest
}

private func writePlist(_ value: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    try data.write(to: url)
}
