import XCTest
@testable import NativeExtensionShared

final class ManifestValidatorTests: XCTestCase {
    func testValidNativeManifestPasses() throws {
        XCTAssertNoThrow(try NativeExtensionManifestValidator.validate(makeManifest()))
    }

    func testNativeExtensionRequiresMacOS26() {
        XCTAssertThrowsError(
            try NativeExtensionManifestValidator.validate(makeManifest(minimumMacOSVersion: "14.0.0"))
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionManifestError,
                .unsupportedMinimumMacOSVersion("14.0.0")
            )
        }
    }

    func testDuplicateEntryPointsAreRejected() {
        let entryPoint = NativeExtensionManifest.EntryPoint(
            id: "com.notchkit.prototype.pomodoro.main",
            kind: .openDestination,
            sceneName: "main"
        )
        XCTAssertThrowsError(
            try NativeExtensionManifestValidator.validate(
                makeManifest(entryPoints: [entryPoint, entryPoint])
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionManifestError,
                .duplicateEntryPoint(entryPoint.id)
            )
        }
    }

    func testEmptySceneNameIsRejected() {
        let entryPoint = NativeExtensionManifest.EntryPoint(
            id: "com.notchkit.prototype.pomodoro.main",
            kind: .openDestination,
            sceneName: "  "
        )
        XCTAssertThrowsError(
            try NativeExtensionManifestValidator.validate(makeManifest(entryPoints: [entryPoint]))
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionManifestError,
                .missingSceneName(entryPoint.id)
            )
        }
    }

    func testExtensionBundleMustBeContainedByProviderIdentity() {
        let manifest = NativeExtensionManifest(
            schemaVersion: 1,
            id: "com.notchkit.prototype.pomodoro",
            displayName: "Pomodoro",
            summary: "Timer",
            extensionVersion: "1.0.0",
            minimumHostVersion: "1.0.0",
            minimumMacOSVersion: "26.0.0",
            artifactKind: .appExtension,
            providerBundleIdentifier: "com.notchkit.prototype.pomodoro.provider",
            extensionBundleIdentifier: "com.notchkit.prototype.pomodoro.extension",
            entryPoints: [
                .init(
                    id: "com.notchkit.prototype.pomodoro.main",
                    kind: .openDestination,
                    sceneName: "main"
                ),
            ]
        )

        XCTAssertThrowsError(try NativeExtensionManifestValidator.validate(manifest)) { error in
            XCTAssertEqual(
                error as? NativeExtensionManifestError,
                .extensionIsNotContainedByProvider
            )
        }
    }
}

func makeManifest(
    minimumMacOSVersion: String = "26.0.0",
    entryPoints: [NativeExtensionManifest.EntryPoint]? = nil
) -> NativeExtensionManifest {
    NativeExtensionManifest(
        schemaVersion: 1,
        id: "com.notchkit.prototype.pomodoro",
        displayName: "Pomodoro",
        summary: "A native remote Pomodoro timer",
        extensionVersion: "1.0.0",
        minimumHostVersion: "1.0.0",
        minimumMacOSVersion: minimumMacOSVersion,
        artifactKind: .appExtension,
        providerBundleIdentifier: "com.notchkit.prototype.pomodoro.provider",
        extensionBundleIdentifier: "com.notchkit.prototype.pomodoro.provider.extension",
        entryPoints: entryPoints ?? [
            .init(
                id: "com.notchkit.prototype.pomodoro.main",
                kind: .openDestination,
                sceneName: "main"
            ),
        ]
    )
}
