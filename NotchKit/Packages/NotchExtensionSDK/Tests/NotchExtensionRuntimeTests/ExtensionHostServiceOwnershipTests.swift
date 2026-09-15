//
//  ExtensionHostServiceOwnershipTests.swift
//  NotchExtensionRuntimeTests
//
//  Deterministic coverage for shared-service ownership across rapid lifecycle
//  transitions. These reproduce the race where a superseded deactivation could
//  stop a service that a newer activation had just started.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class ExtensionHostServiceOwnershipTests: XCTestCase {

    /// A shared, app-wide service (the role `BatteryMonitor` plays in the host).
    /// Counts every start/stop so overlapping ownership is observable.
    final class SharedService {
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var isRunning: Bool { startCount > stopCount }

        func start() { startCount += 1 }
        func stop() { stopCount += 1 }
    }

    /// An extension instance that starts/stops the shared service. A fresh
    /// instance is created per activation, mirroring Battery.
    @MainActor
    final class ServiceOwningExtension: NotchExtension {
        let service: SharedService
        var activateDelay: Duration = .zero
        var failOnActivate = false
        var contributedDestination: NotchOpenDestination?
        private(set) var activateCount = 0
        private(set) var deactivateCount = 0
        private(set) var isActive = false

        init(service: SharedService) { self.service = service }

        func openDestinations() -> [NotchOpenDestination] {
            guard isActive, let contributedDestination else { return [] }
            return [contributedDestination]
        }

        func activate() async throws {
            activateCount += 1
            if activateDelay > .zero {
                try? await Task.sleep(for: activateDelay)
            }
            if failOnActivate {
                throw TestError.activationFailed
            }
            isActive = true
            service.start()
        }

        func deactivate() {
            deactivateCount += 1
            isActive = false
            service.stop()
        }

        enum TestError: Error { case activationFailed }
    }

    private struct Harness {
        let host: ExtensionHost
        let registry: ExtensionRegistry
        let manager: ExtensionManager
        let instances: InstanceBox
    }

    /// Identity box so the definition factory can append instances without
    /// capturing a mutable local in a `@MainActor` closure.
    @MainActor
    final class InstanceBox {
        var values: [ServiceOwningExtension] = []
        var last: ServiceOwningExtension? { values.last }
    }

    private func makeHarness(
        id: ExtensionIdentity,
        service: SharedService,
        defaultEnabled: Bool = true,
        entryPoints: [ExtensionEntryPoint],
        configure: @escaping @MainActor (ServiceOwningExtension) -> Void = { _ in }
    ) -> Harness {
        let registry = TestFactory.registry()
        let metadata = TestFactory.metadata(
            id: id,
            defaultEnabled: defaultEnabled,
            entryPoints: entryPoints
        )
        let box = InstanceBox()
        let definition = ExtensionDefinition(metadata: metadata) { _ in
            let instance = ServiceOwningExtension(service: service)
            configure(instance)
            box.values.append(instance)
            return instance
        }
        try! registry.register(definition)
        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        let host = ExtensionHost(registry: registry, manager: manager, contributions: ContributionStore()) { id, bag in
            ExtensionContext(
                identity: id,
                cancellation: bag,
                presentation: TestPresentationService(),
                store: TestScopedStore(),
                permissions: TestPermissionService()
            )
        }
        return Harness(host: host, registry: registry, manager: manager, instances: box)
    }

    private func drain(_ iterations: Int = 16) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    /// The regression: disable then immediately re-enable. The pending
    /// deactivation must not tear the shared service down again after the new
    /// instance has started it.
    func testSupersededDeactivationDoesNotStopNewlyStartedSharedService() async throws {
        let id = try TestFactory.identity("com.notchkit.battery")
        let service = SharedService()
        let harness = makeHarness(
            id: id,
            service: service,
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.battery.open", kind: .openDestination)]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        XCTAssertEqual(harness.instances.values.count, 1)
        XCTAssertTrue(service.isRunning)

        // Rapid disable -> enable before the deactivation task is given a
        // chance to run.
        harness.host.setEnabled(false, for: id)
        harness.host.setEnabled(true, for: id)
        await harness.host.waitForQuiescence()
        await drain()

        XCTAssertEqual(harness.instances.values.count, 2, "re-enable must create a new instance")
        XCTAssertEqual(
            harness.instances.values[0].deactivateCount,
            1,
            "the superseded deactivation must not tear the previous instance down twice"
        )
        XCTAssertEqual(service.startCount, 2)
        XCTAssertEqual(
            service.stopCount,
            1,
            "only the transition that owned teardown may stop the shared service"
        )
        XCTAssertTrue(service.isRunning, "the shared service must still be running after re-enable")
        XCTAssertEqual(harness.host.phase(for: id), .active)
    }

    /// Many rapid toggles ending enabled must leave exactly one live owner.
    func testRapidTogglesLeaveSharedServiceRunningWithSingleOwner() async throws {
        let id = try TestFactory.identity("com.notchkit.battery")
        let service = SharedService()
        let harness = makeHarness(
            id: id,
            service: service,
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.battery.open", kind: .openDestination)]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()

        for _ in 0..<12 {
            harness.host.setEnabled(false, for: id)
            harness.host.setEnabled(true, for: id)
        }
        await harness.host.waitForQuiescence()
        await drain(64)

        XCTAssertEqual(harness.host.phase(for: id), .active)
        XCTAssertTrue(service.isRunning, "the final enable must own a running service")
        XCTAssertEqual(
            service.startCount - service.stopCount,
            1,
            "exactly one service start must remain live"
        )
        // The current instance owns the service.
        XCTAssertEqual(harness.instances.last?.isActive, true)
    }

    /// Disabling must withdraw contributions immediately, before the async
    /// cleanup finishes, so nothing stale is presented while cleaning up.
    func testDisableWithdrawsContributionsBeforeCleanupCompletes() async throws {
        let id = try TestFactory.identity("com.notchkit.battery")
        let service = SharedService()
        let destination = TestFactory.destination("com.notchkit.battery.open")
        let harness = makeHarness(
            id: id,
            service: service,
            entryPoints: [ExtensionEntryPoint(id: destination.id.rawValue, kind: .openDestination)]
        ) { instance in
            instance.contributedDestination = destination
        }

        harness.host.start()
        await harness.host.waitForQuiescence()
        XCTAssertEqual(harness.host.contributions.openDestinations.count, 1)

        harness.host.setEnabled(false, for: id)
        // Still within the same synchronous turn: phase is deactivating and
        // contributions are gone, so nothing stale is presented.
        XCTAssertEqual(harness.host.phase(for: id), .deactivating)
        XCTAssertTrue(
            harness.host.contributions.openDestinations.isEmpty,
            "contributions withdraw immediately"
        )

        await harness.host.waitForQuiescence()
        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertFalse(service.isRunning)
    }

    /// Disabling while activation is still in flight must not leave a running
    /// service or an active instance behind.
    func testDisableDuringDelayedActivationLeavesNoRunningService() async throws {
        let id = try TestFactory.identity("com.notchkit.battery")
        let service = SharedService()
        let harness = makeHarness(
            id: id,
            service: service,
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.battery.open", kind: .openDestination)]
        ) { instance in
            instance.activateDelay = .milliseconds(50)
        }

        harness.host.start()
        harness.host.setEnabled(false, for: id) // arrives during activation
        await harness.host.waitForQuiescence()
        // Let the cancelled, delayed activation resume and prove it cannot
        // leave the service running after the disable.
        try? await Task.sleep(for: .milliseconds(120))
        await drain()

        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertFalse(service.isRunning, "a cancelled activation must not leave the service running")
    }

    /// Removal while a transition is pending must stop the shared service and
    /// never leave a stale owner behind.
    func testRemoveDuringPendingTransitionStopsSharedService() async throws {
        let id = try TestFactory.identity("com.notchkit.battery")
        let service = SharedService()
        let harness = makeHarness(
            id: id,
            service: service,
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.battery.open", kind: .openDestination)]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        XCTAssertTrue(service.isRunning)

        harness.host.setEnabled(false, for: id)
        harness.host.remove(id)
        await harness.host.waitForQuiescence()
        await drain()

        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertFalse(service.isRunning, "removal must stop the shared service")
        XCTAssertFalse(service.isRunning)
        // No instance may be left active after removal.
        for instance in harness.instances.values {
            XCTAssertFalse(instance.isActive)
        }
    }
}
