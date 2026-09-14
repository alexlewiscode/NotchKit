//
//  ExtensionManagerTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

final class ExtensionManagerTests: XCTestCase {
    func testReconcileAppliesDefaultEnabledState() throws {
        let registry = TestFactory.registry()
        let enabled = try TestFactory.identity("com.notchkit.alpha")
        let disabled = try TestFactory.identity("com.notchkit.beta")
        try registry.register(TestFactory.definition(id: enabled, defaultEnabled: true))
        try registry.register(TestFactory.definition(id: disabled, defaultEnabled: false))

        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        manager.reconcile()

        XCTAssertTrue(manager.isEnabled(enabled))
        XCTAssertFalse(manager.isEnabled(disabled))
        XCTAssertEqual(manager.enabledMetadata.map(\.id), [enabled])
    }

    func testReconcilePreservesExistingChoice() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id, defaultEnabled: true))

        let store = InMemoryExtensionStateStore(
            snapshot: ExtensionStateSnapshot(enabled: [id.rawValue: false])
        )
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()

        XCTAssertFalse(manager.isEnabled(id))
    }

    func testSetEnabledPersistsThroughStore() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id, defaultEnabled: true))

        let store = InMemoryExtensionStateStore()
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()
        manager.setEnabled(false, for: id)

        let reloaded = ExtensionManager(registry: registry, store: store)
        XCTAssertFalse(reloaded.isEnabled(id))
    }

    func testReconcileDropsStaleEntries() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id))

        let store = InMemoryExtensionStateStore(
            snapshot: ExtensionStateSnapshot(enabled: ["com.notchkit.removed": true])
        )
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()

        XCTAssertNil(manager.state.enabled["com.notchkit.removed"])
        XCTAssertEqual(manager.state.schemaVersion, ExtensionStateSnapshot.currentSchemaVersion)
    }

    func testOnEnabledChangedFiresOnlyOnChange() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id, defaultEnabled: true))
        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        manager.reconcile()

        var changes: [(ExtensionIdentity, Bool)] = []
        manager.onEnabledChanged = { changes.append(($0, $1)) }

        manager.setEnabled(true, for: id)   // no change
        manager.setEnabled(false, for: id)  // change
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, id)
        XCTAssertEqual(changes.first?.1, false)
    }
}
