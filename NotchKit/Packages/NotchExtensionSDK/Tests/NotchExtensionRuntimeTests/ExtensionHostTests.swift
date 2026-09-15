//
//  ExtensionHostTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class ExtensionHostTests: XCTestCase {
    private func makeHost(
        definitions: [ExtensionDefinition],
        store: ExtensionStateStore = InMemoryExtensionStateStore()
    ) -> (host: ExtensionHost, registry: ExtensionRegistry, manager: ExtensionManager) {
        let registry = TestFactory.registry()
        for definition in definitions {
            try! registry.register(definition)
        }
        let manager = ExtensionManager(registry: registry, store: store)
        let host = ExtensionHost(registry: registry, manager: manager) { id, bag in
            ExtensionContext(
                identity: id,
                cancellation: bag,
                presentation: TestPresentationService(),
                store: TestScopedStore(),
                permissions: TestPermissionService()
            )
        }
        return (host, registry, manager)
    }

    private func lifecycleDefinition(
        id: ExtensionIdentity,
        defaultEnabled: Bool,
        make: @escaping @MainActor (ExtensionContext) -> TestLifecycleExtension
    ) -> ExtensionDefinition {
        let metadata = TestFactory.metadata(
            id: id,
            defaultEnabled: defaultEnabled,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)
            ]
        )
        return ExtensionDefinition(metadata: metadata) { context in make(context) }
    }

    func testMetadataListingDoesNotInstantiate() throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        var instantiated = false
        let metadata = TestFactory.metadata(
            id: id,
            defaultEnabled: false,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)
            ]
        )
        let definition = ExtensionDefinition(metadata: metadata) { context in
            instantiated = true
            return StaticExtension()
        }
        let harness = makeHost(definitions: [definition])
        harness.host.start()
        XCTAssertFalse(instantiated)
        XCTAssertEqual(harness.host.phase(for: id), .inactive)
    }

    func testEnableActivatesAndPublishesContributions() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")
        let harness = makeHost(
            definitions: [TestFactory.definition(id: id, openDestinations: [destination])]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .active)
        XCTAssertEqual(harness.host.contributions.openDestinations.map(\.id), [destination.id])
    }

    func testDisableDeactivatesAndRemovesContributions() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")
        let harness = makeHost(
            definitions: [TestFactory.definition(id: id, openDestinations: [destination])]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        harness.host.setEnabled(false, for: id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertTrue(harness.host.contributions.openDestinations.isEmpty)
    }

    func testRapidToggleCoalescesWithoutDuplicateServices() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let instance = TestLifecycleExtension()
        instance.activateDelay = .milliseconds(50)
        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    instance.lastContext = context
                    return instance
                }
            ]
        )

        harness.host.start()
        harness.host.setEnabled(false, for: id)   // arrives during activation
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertEqual(instance.activateCount, 1)
        XCTAssertGreaterThanOrEqual(instance.deactivateCount, 1)
        XCTAssertTrue(harness.host.contributions.openDestinations.isEmpty)
    }

    func testActivationFailureIsRecordedAndTornDown() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let instance = TestLifecycleExtension()
        instance.failOnActivate = true
        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    instance.lastContext = context
                    return instance
                }
            ]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()

        guard case .failed = harness.host.phase(for: id) else {
            return XCTFail("expected failed phase, got \(harness.host.phase(for: id))")
        }
        XCTAssertTrue(harness.host.contributions.openDestinations.isEmpty)
        XCTAssertGreaterThanOrEqual(instance.deactivateCount, 1)
    }

    func testRepeatedEnableDoesNotDuplicateInstance() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let instance = TestLifecycleExtension()
        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    instance.lastContext = context
                    return instance
                }
            ]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        harness.host.setEnabled(true, for: id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(instance.activateCount, 1)
        XCTAssertEqual(harness.host.phase(for: id), .active)
    }

    func testRemoveStopsAndDeregisters() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")
        let harness = makeHost(
            definitions: [TestFactory.definition(id: id, openDestinations: [destination])]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        harness.host.remove(id)

        XCTAssertNil(harness.registry.definition(for: id))
        XCTAssertEqual(harness.host.phase(for: id), .inactive)
        XCTAssertTrue(harness.host.contributions.openDestinations.isEmpty)
    }

    func testReEnableDuringDeactivationActivatesAgain() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let instance = TestLifecycleExtension()
        instance.activateDelay = .milliseconds(50)
        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    instance.lastContext = context
                    return instance
                }
            ]
        )

        harness.host.start()
        harness.host.setEnabled(false, for: id)   // begins deactivation during activation
        harness.host.setEnabled(true, for: id)    // arrives while .deactivating
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .active)
        XCTAssertEqual(harness.host.contributions.openDestinations.count, 1)
    }

    func testReconcileNowRetriesFailedEnabledExtension() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let instance = TestLifecycleExtension()
        instance.failOnActivate = true
        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    instance.lastContext = context
                    return instance
                }
            ]
        )

        harness.host.start()
        await harness.host.waitForQuiescence()
        guard case .failed = harness.host.phase(for: id) else {
            return XCTFail("expected failed phase, got \(harness.host.phase(for: id))")
        }

        // Persisted enabled state is already true, so a Retry must not rely on
        // setEnabled(true) (a no-op). It must actually re-run activation.
        XCTAssertTrue(harness.manager.isEnabled(id))
        instance.failOnActivate = false
        harness.host.reconcileNow()
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .active)
        XCTAssertEqual(instance.activateCount, 2)
    }

    func testReAddAfterRemoveActivatesCleanlyDespiteStaleTask() async throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        let failing = TestLifecycleExtension()
        failing.failOnActivate = true
        failing.activateDelay = .milliseconds(50)

        let harness = makeHost(
            definitions: [
                lifecycleDefinition(id: id, defaultEnabled: true) { context in
                    failing.lastContext = context
                    return failing
                }
            ]
        )

        harness.host.start()          // slow, failing activation in flight
        harness.host.remove(id)       // cancels it and deregisters

        let replacement = StaticExtension(
            open: [TestFactory.destination("com.notchkit.alpha.open")]
        )
        let replacementMetadata = TestFactory.metadata(
            id: id,
            defaultEnabled: true,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.alpha.open", kind: .openDestination)
            ]
        )
        try harness.registry.register(
            ExtensionDefinition(metadata: replacementMetadata) { _ in replacement }
        )
        harness.host.setEnabled(true, for: id)
        await harness.host.waitForQuiescence()

        XCTAssertEqual(harness.host.phase(for: id), .active)
        XCTAssertEqual(harness.host.contributions.openDestinations.count, 1)
    }
}