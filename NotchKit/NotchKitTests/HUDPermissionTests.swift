//
//  HUDPermissionTests.swift
//  NotchKitTests
//
//  The HUD accessibility flow: one app-side permission source, a non-prompting
//  status read, an explicit app-side request, targeted refresh reconciliation,
//  and a permission/operational-failure split.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest
@testable import NotchKit

@MainActor
final class HUDPermissionTests: XCTestCase {
    // MARK: - Fakes

    private final class FakeAccessibilityAuthorizer: AccessibilityAuthorizing {
        var authorized: Bool
        private(set) var requestCount = 0

        init(authorized: Bool) {
            self.authorized = authorized
        }

        func isAuthorized() -> Bool { authorized }

        func requestAuthorization() { requestCount += 1 }
    }

    private final class FakeHUDInterceptor: HUDIntercepting {
        var result: Bool
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var isRunning = false

        init(result: Bool) {
            self.result = result
        }

        func start() async -> Bool {
            startCount += 1
            isRunning = result
            return result
        }

        func stop() {
            stopCount += 1
            isRunning = false
        }
    }

    @MainActor
    private final class FakePresentationService: NotchPresentationService {
        var availableDisplays: [DisplayID] { [] }
        func request(_ request: PresentationRequest, target: PresentationTarget) {}
    }

    private final class FakeScopedStore: ExtensionScopedStore {
        var schemaVersion: Int { 1 }
        func data(forKey key: String) -> Data? { nil }
        func set(_ data: Data?, forKey key: String) {}
    }

    private func hudIdentity() -> ExtensionIdentity {
        // Mirrors BuiltInExtensionIDs.hud so the test does not depend on the app
        // target's identity constants.
        guard let id = try? ExtensionIdentity("com.notchkit.hud") else {
            fatalError("invalid HUD identity")
        }
        return id
    }

    private func makeContext(permissions: NotchPermissionService) -> ExtensionContext {
        ExtensionContext(
            identity: hudIdentity(),
            cancellation: ExtensionCancellationBag(),
            presentation: FakePresentationService(),
            store: FakeScopedStore(),
            permissions: permissions
        )
    }

    // MARK: - HUD activation gate

    /// App trusted / helper untrusted: the app-side source alone decides, so HUD
    /// is not blocked by the XPC helper's (different) TCC identity.
    func testAppTrustedStartsInterceptionWithoutPrompting() async throws {
        let authorizer = FakeAccessibilityAuthorizer(authorized: true)
        let interceptor = FakeHUDInterceptor(result: true)
        let feature = HUDFeature(
            context: makeContext(permissions: HostPermissionService(accessibility: authorizer)),
            interceptor: interceptor
        )

        try await feature.activate()

        XCTAssertEqual(interceptor.startCount, 1)
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(authorizer.requestCount, 0, "activation must never prompt")
    }

    /// App untrusted: a grantable permission gate, and no tap is attempted.
    func testAppUntrustedRequiresPermissionWithoutStartingInterception() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: false)
        let interceptor = FakeHUDInterceptor(result: true)
        let feature = HUDFeature(
            context: makeContext(permissions: HostPermissionService(accessibility: authorizer)),
            interceptor: interceptor
        )

        do {
            try await feature.activate()
            XCTFail("expected a permission gate")
        } catch {
            XCTAssertEqual(error as? ExtensionActivationError, .permissionRequired(.accessibility))
        }
        XCTAssertEqual(interceptor.startCount, 0)
        XCTAssertEqual(authorizer.requestCount, 0)
    }

    /// Granted but the tap cannot install: an operational failure (`.failed`),
    /// not a permission gate, and the partial startup is cleaned up.
    func testGrantedButTapFailureIsOperationalAndCleansUp() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: true)
        let interceptor = FakeHUDInterceptor(result: false)
        let feature = HUDFeature(
            context: makeContext(permissions: HostPermissionService(accessibility: authorizer)),
            interceptor: interceptor
        )

        do {
            try await feature.activate()
            XCTFail("expected an operational failure")
        } catch {
            XCTAssertEqual(error as? HUDActivationFailure, .mediaKeyInterceptionUnavailable)
        }
        XCTAssertEqual(interceptor.startCount, 1)
        XCTAssertEqual(interceptor.stopCount, 1, "partial startup must be torn down")
        XCTAssertFalse(interceptor.isRunning)
    }

    // MARK: - Status reads vs explicit requests

    func testStatusReadNeverPromptsAndRequestPromptsAppSide() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: false)
        let service = HostPermissionService(accessibility: authorizer)

        XCTAssertEqual(service.status(for: .accessibility), .notDetermined)
        XCTAssertEqual(authorizer.requestCount, 0, "status must never prompt")

        _ = await service.request(.accessibility)
        XCTAssertEqual(authorizer.requestCount, 1)

        // A request is not a grant.
        XCTAssertEqual(service.status(for: .accessibility), .notDetermined)
        XCTAssertFalse(service.isAccessibilityAuthorized)
    }

    // MARK: - MediaKeyInterceptor

    func testInterceptorStartIsNonPromptingAndDeduplicates() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: true)
        var installs = 0
        let interceptor = MediaKeyInterceptor(
            accessibility: authorizer,
            installOverride: { installs += 1; return true }
        )

        let first = await interceptor.start()
        let second = await interceptor.start()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(installs, 1, "a running tap must not be installed twice")
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(authorizer.requestCount, 0)

        interceptor.stop()
        XCTAssertFalse(interceptor.isRunning)
    }

    func testInterceptorStartReturnsFalseWhenUntrusted() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: false)
        var installs = 0
        let interceptor = MediaKeyInterceptor(
            accessibility: authorizer,
            installOverride: { installs += 1; return true }
        )

        let running = await interceptor.start()

        XCTAssertFalse(running)
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(authorizer.requestCount, 0, "start must never prompt")
    }

    func testInterceptorTapFailureReportsNotRunning() async {
        let authorizer = FakeAccessibilityAuthorizer(authorized: true)
        let interceptor = MediaKeyInterceptor(
            accessibility: authorizer,
            installOverride: { false }
        )

        let running = await interceptor.start()

        XCTAssertFalse(running)
        XCTAssertFalse(interceptor.isRunning)
    }
}
