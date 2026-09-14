//
//  ExtensionManagerTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

final class ExtensionManagerTests: XCTestCase {
    func testReconcileAppliesDefaultEnabledState() throws {
        let registry = ExtensionRegistry()
        let enabled = try TestFactory.identity("com.boringnotch.alpha")
        let disabled = try TestFactory.identity("com.boringnotch.beta")
        try registry.register(TestFactory.descriptor(id: enabled, defaultEnabled: true))
        try registry.register(TestFactory.descriptor(id: disabled, defaultEnabled: false))

        let store = InMemoryExtensionStateStore()
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()

        XCTAssertTrue(manager.isEnabled(enabled))
        XCTAssertFalse(manager.isEnabled(disabled))
        XCTAssertEqual(manager.enabledDescriptors.map(\.id), [enabled])
    }

    func testReconcilePreservesExistingChoice() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        try registry.register(TestFactory.descriptor(id: id, defaultEnabled: true))

        let store = InMemoryExtensionStateStore(
            snapshot: ExtensionStateSnapshot(enabled: [id.rawValue: false])
        )
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()

        XCTAssertFalse(manager.isEnabled(id))
    }

    func testSetEnabledPersistsThroughStore() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        try registry.register(TestFactory.descriptor(id: id, defaultEnabled: true))

        let store = InMemoryExtensionStateStore()
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()
        manager.setEnabled(false, for: id)

        let reloaded = ExtensionManager(registry: registry, store: store)
        XCTAssertFalse(reloaded.isEnabled(id))
    }

    func testReconcileDropsStaleEntries() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        try registry.register(TestFactory.descriptor(id: id))

        let store = InMemoryExtensionStateStore(
            snapshot: ExtensionStateSnapshot(enabled: ["com.boringnotch.removed": true])
        )
        let manager = ExtensionManager(registry: registry, store: store)
        manager.reconcile()

        XCTAssertNil(manager.state.enabled["com.boringnotch.removed"])
        XCTAssertEqual(manager.state.schemaVersion, ExtensionStateSnapshot.currentSchemaVersion)
    }
}