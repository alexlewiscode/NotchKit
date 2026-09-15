//
//  ExtensionHostPermissionTests.swift
//  NotchExtensionRuntimeTests
//
//  The permission-gate lifecycle: a permission-blocked activation is not a
//  failure, is not reported active, is not auto-retried, and can be retried
//  explicitly after the user grants access.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class ExtensionHostPermissionTests: XCTestCase {
    private struct Harness {
        let host: ExtensionHost
        let manager: ExtensionManager
        let id: ExtensionIdentity
        let instance: TestLifecycleExtension
    }

    private func makeHarness(
        defaultEnabled: Bool = false
    ) throws -> Harness {
        let id = try TestFactory.identity("com.notchkit.permission")
        let instance = TestLifecycleExtension()
        let metadata = TestFactory.metadata(
            id: id,
            defaultEnabled: defaultEnabled,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)
            ]
        )
        let definition = ExtensionDefinition(metadata: metadata) { context in
            instance.lastContext = context
            return instance
        }
        let registry = TestFactory.registry()
        try registry.register(definition)
        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        let host = ExtensionHost(registry: registry, manager: manager) { id, bag in
            ExtensionContext(
                identity: id,
                cancellation: bag,
                presentation: TestPresentationService(),
                store: TestScopedStore(),
                permissions: TestPermissionService()
            )
        }
        host.start()
        return Harness(host: host, manager: manager, id: id, instance: instance)
    }

    func testPermissionRequiredIsRecordedAsGateNotActive() async throws {
        let harness = try makeHarness()
        harness.instance.activationError = ExtensionActivationError.permissionRequired(.accessibility)

        harness.host.setEnabled(true, for: harness.id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(
            harness.host.phase(for: harness.id),
            .requiresPermission("accessibility permission required")
        )
        XCTAssertFalse(harness.instance.isActive)
        XCTAssertTrue(harness.manager.isEnabled(harness.id), "desired state stays on")
        XCTAssertTrue(harness.host.contributions.openDestinations.isEmpty)
    }

    func testReconcileDoesNotAutoRetryPermissionGate() async throws {
        let harness = try makeHarness()
        harness.instance.activationError = ExtensionActivationError.permissionRequired(.accessibility)

        harness.host.setEnabled(true, for: harness.id)
        await harness.host.waitForQuiescence()
        let countAfterFirst = harness.instance.activateCount

        harness.host.reconcileNow()
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.instance.activateCount, countAfterFirst)
        XCTAssertEqual(
            harness.host.phase(for: harness.id),
            .requiresPermission("accessibility permission required")
        )
    }

    func testExplicitRetryActivatesAfterGrant() async throws {
        let harness = try makeHarness()
        harness.instance.activationError = ExtensionActivationError.permissionRequired(.accessibility)

        harness.host.setEnabled(true, for: harness.id)
        await harness.host.waitForQuiescence()

        // Simulate the user granting access, then the explicit retry.
        harness.instance.activationError = nil
        harness.host.retry(harness.id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: harness.id), .active)
        XCTAssertTrue(harness.instance.isActive)
        XCTAssertEqual(harness.instance.activateCount, 2)
        XCTAssertFalse(harness.host.contributions.openDestinations.isEmpty)
    }

    func testDisablingPermissionBlockedFeatureClearsToInactive() async throws {
        let harness = try makeHarness()
        harness.instance.activationError = ExtensionActivationError.permissionRequired(.accessibility)

        harness.host.setEnabled(true, for: harness.id)
        await harness.host.waitForQuiescence()
        harness.host.setEnabled(false, for: harness.id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: harness.id), .inactive)
        XCTAssertFalse(harness.manager.isEnabled(harness.id))
    }

    func testDeviceUnavailableIsAFailureWithItsReason() async throws {
        let harness = try makeHarness()
        harness.instance.activationError = ExtensionActivationError.deviceUnavailable("No camera devices available")

        harness.host.setEnabled(true, for: harness.id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: harness.id), .failed("No camera devices available"))
        XCTAssertFalse(harness.instance.isActive)
    }
}
