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
import XCTest
@testable import NotchKit

@MainActor
final class HUDPermissionTests: XCTestCase {
    // MARK: - Fakes

    private final class FakeInputAccess: InputAccessAuthorizing {
        var observe: Bool
        var modify: Bool
        var axTrusted: Bool
        private(set) var observationRequests = 0
        private(set) var modificationRequests = 0

        init(observe: Bool = false, modify: Bool = false, axTrusted: Bool = false) {
            self.observe = observe
            self.modify = modify
            self.axTrusted = axTrusted
        }

        func canObserveInput() -> Bool { observe }
        func canModifyInput() -> Bool { modify }
        func isAccessibilityTrusted() -> Bool { axTrusted }
        func requestObservationAccess() { observationRequests += 1 }
        func requestModificationAccess() { modificationRequests += 1 }
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
        let inputAccess = FakeInputAccess(modify: true)
        let interceptor = FakeHUDInterceptor(result: true)

        try await makeFeature(inputAccess: inputAccess, interceptor: interceptor).activate()

        XCTAssertEqual(interceptor.startCount, 1)
        XCTAssertTrue(interceptor.isRunning)
        XCTAssertEqual(inputAccess.observationRequests, 0)
        XCTAssertEqual(inputAccess.modificationRequests, 0, "activation must never prompt")
    }

    /// No access and the tap fails: a grantable permission gate, with cleanup.
    func testNoInputAccessBlocksAsPermissionGate() async {
        let inputAccess = FakeInputAccess(modify: false, axTrusted: false)
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
        let inputAccess = FakeInputAccess(modify: true)
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

    // MARK: - Status vs request

    func testStatusReadNeverPromptsAndRequestPrompts() async {
        let inputAccess = FakeInputAccess(modify: false, axTrusted: true)
        let service = HostPermissionService(inputAccess: inputAccess)

        XCTAssertTrue(service.hasHUDInputAccess)
        XCTAssertEqual(service.status(for: .accessibility), .authorized)
        XCTAssertEqual(inputAccess.observationRequests, 0, "status must never prompt")
        XCTAssertEqual(inputAccess.modificationRequests, 0)

        service.requestHUDInputAccess()
        XCTAssertEqual(inputAccess.observationRequests, 1)
        XCTAssertEqual(inputAccess.modificationRequests, 1)
    }

    func testHasInputAccessIsFalseWithoutAnySignal() {
        let service = HostPermissionService(inputAccess: FakeInputAccess())
        XCTAssertFalse(service.hasHUDInputAccess)
        XCTAssertFalse(service.canModifyInput)
        XCTAssertFalse(service.canObserveInput)
    }

    // MARK: - MediaKeyInterceptor

    func testInterceptorInstallsOnceAndDoesNotPrompt() async {
        let inputAccess = FakeInputAccess(modify: true)
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
        XCTAssertEqual(inputAccess.observationRequests, 0)
        XCTAssertEqual(inputAccess.modificationRequests, 0)
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
}
