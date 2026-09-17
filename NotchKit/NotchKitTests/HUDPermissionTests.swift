//
//  HUDPermissionTests.swift
//  NotchKitTests
//
//  The HUD input-access flow: one host-owned capability source, a non-prompting
//  status read, an explicit request, the tap attempt as the authoritative
//  capability test, and a permission/operational-failure split.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import CoreGraphics
import XCTest
@testable import NotchKit

@MainActor
final class HUDPermissionTests: XCTestCase {
    // MARK: - Fakes

    private final class FakeInputAccess: InputAccessAuthorizing {
        var currentStatus: HUDInputAccessStatus
        private(set) var requests = 0
        var diagnostics = "fake"

        init(status: HUDInputAccessStatus = .requiresPermission) {
            self.currentStatus = status
        }

        func status() -> HUDInputAccessStatus { currentStatus }
        func requestAccess() { requests += 1 }
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

    private func makeFeature(
        inputAccess: FakeInputAccess,
        interceptor: FakeHUDInterceptor
    ) -> HUDFeature {
        HUDFeature(
            context: makeContext(permissions: HostPermissionService(inputAccess: inputAccess)),
            interceptor: interceptor,
            inputAccess: inputAccess
        )
    }

    // MARK: - HUD activation

    /// Access present: the tap installs and activation succeeds without prompting.
    func testInputAccessStartsInterceptionWithoutPrompting() async throws {
        let inputAccess = FakeInputAccess(status: .granted)
        let interceptor = FakeHUDInterceptor(result: true)

        try await makeFeature(inputAccess: inputAccess, interceptor: interceptor).activate()

        XCTAssertEqual(interceptor.startCount, 1)
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(inputAccess.requests, 0, "activation must never prompt")
    }

    /// No access and the tap fails: a grantable permission gate, with cleanup.
    func testNoInputAccessBlocksAsPermissionGate() async {
        let inputAccess = FakeInputAccess(status: .requiresPermission)
        let interceptor = FakeHUDInterceptor(result: false)

        do {
            try await makeFeature(inputAccess: inputAccess, interceptor: interceptor).activate()
            XCTFail("expected a permission gate")
        } catch {
            XCTAssertEqual(error as? ExtensionActivationError, .permissionRequired(.accessibility))
        }
        XCTAssertEqual(interceptor.startCount, 1, "the tap attempt is the capability test")
        XCTAssertEqual(interceptor.stopCount, 1, "partial startup must be torn down")
    }

    /// Access present but the tap still fails: an operational failure, not a
    /// permission gate the user can never satisfy.
    func testTapFailureWithAccessIsOperationalAndCleansUp() async {
        let inputAccess = FakeInputAccess(status: .granted)
        let interceptor = FakeHUDInterceptor(result: false)

        do {
            try await makeFeature(inputAccess: inputAccess, interceptor: interceptor).activate()
            XCTFail("expected an operational failure")
        } catch {
            XCTAssertEqual(error as? HUDActivationFailure, .mediaKeyInterceptionUnavailable)
        }
        XCTAssertEqual(interceptor.stopCount, 1)
        XCTAssertFalse(interceptor.isRunning)
    }

    func testStatusCheckFailureIsActionableAndCleansUp() async {
        let inputAccess = FakeInputAccess(status: .checkFailed("transport unavailable"))
        let interceptor = FakeHUDInterceptor(result: false)

        do {
            try await makeFeature(inputAccess: inputAccess, interceptor: interceptor).activate()
            XCTFail("expected a status-check failure")
        } catch {
            XCTAssertEqual(error as? HUDActivationFailure, .statusCheckFailed("transport unavailable"))
        }
        XCTAssertEqual(interceptor.stopCount, 1)
    }

    // MARK: - Status vs request

    func testStatusReadNeverPromptsAndRequestPrompts() async {
        let inputAccess = FakeInputAccess(status: .granted)
        let service = HostPermissionService(inputAccess: inputAccess)

        XCTAssertTrue(service.hasHUDInputAccess)
        XCTAssertEqual(service.status(for: .accessibility), .authorized)
        XCTAssertEqual(inputAccess.requests, 0, "status must never prompt")

        service.requestHUDInputAccess()
        XCTAssertEqual(inputAccess.requests, 1)
    }

    func testHasInputAccessIsFalseWithoutAnySignal() {
        let service = HostPermissionService(inputAccess: FakeInputAccess())
        XCTAssertFalse(service.hasHUDInputAccess)
        XCTAssertEqual(service.hudInputAccessStatus, .requiresPermission)
    }

    // MARK: - MediaKeyInterceptor

    func testInterceptorInstallsOnceAndDoesNotPrompt() async {
        let inputAccess = FakeInputAccess(status: .granted)
        var installs = 0
        let interceptor = MediaKeyInterceptor(
            inputAccess: inputAccess,
            installOverride: { installs += 1; return true }
        )

        let first = await interceptor.start()
        let second = await interceptor.start()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(installs, 1, "a running tap must not be installed twice")
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(inputAccess.requests, 0)
    }

    func testInterceptorTapFailureReportsNotRunning() async {
        let interceptor = MediaKeyInterceptor(
            inputAccess: FakeInputAccess(),
            installOverride: { false }
        )

        let running = await interceptor.start()

        XCTAssertFalse(running)
        XCTAssertFalse(interceptor.isRunning)
    }

    func testInterceptorRecoversFromCoreGraphicsDisableNotifications() async {
        var recoveryAttempts = 0
        let interceptor = MediaKeyInterceptor(
            inputAccess: FakeInputAccess(status: .granted),
            installOverride: { true },
            reenableOverride: { recoveryAttempts += 1; return true }
        )
        let event = CGEvent(source: nil)!

        let started = await interceptor.start()
        XCTAssertTrue(started)
        _ = interceptor.handleEvent(type: .tapDisabledByTimeout, event: event)
        _ = interceptor.handleEvent(type: .tapDisabledByUserInput, event: event)

        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(recoveryAttempts, 2)
    }

    func testInterceptorFailedRecoveryTearsDownAndReinstalls() async {
        var installs = 0
        let reinstalled = expectation(description: "tap reinstalled")
        let interceptor = MediaKeyInterceptor(
            inputAccess: FakeInputAccess(status: .granted),
            installOverride: {
                installs += 1
                if installs == 2 { reinstalled.fulfill() }
                return true
            },
            reenableOverride: { false },
            recoveryDelayNanoseconds: 0
        )

        let firstStart = await interceptor.start()
        XCTAssertTrue(firstStart)
        _ = interceptor.handleEvent(type: .tapDisabledByUserInput, event: CGEvent(source: nil)!)
        XCTAssertFalse(interceptor.isRunning)

        await fulfillment(of: [reinstalled], timeout: 1)
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(installs, 2)
    }

    func testInterceptorStopCancelsPendingRecovery() async throws {
        var installs = 0
        let interceptor = MediaKeyInterceptor(
            inputAccess: FakeInputAccess(status: .granted),
            installOverride: { installs += 1; return true },
            reenableOverride: { false },
            recoveryDelayNanoseconds: 50_000_000
        )

        let started = await interceptor.start()
        XCTAssertTrue(started)
        _ = interceptor.handleEvent(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        interceptor.stop()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(interceptor.isRunning)
        XCTAssertEqual(installs, 1)
    }

    func testInterceptorStopDuringInstallSupersedesInstalledTap() async {
        var interceptor: MediaKeyInterceptor!
        interceptor = MediaKeyInterceptor(
            inputAccess: FakeInputAccess(status: .granted),
            installOverride: {
                interceptor.stop()
                return true
            }
        )

        let started = await interceptor.start()

        XCTAssertFalse(started)
        XCTAssertFalse(interceptor.isRunning)
    }
}
