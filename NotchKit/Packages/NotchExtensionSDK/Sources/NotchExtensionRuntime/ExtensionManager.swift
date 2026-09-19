//
//  ExtensionManager.swift
//  NotchExtensionRuntime
//
//  Owns enabled/disabled state and reconciles it with the registry.
//

import Foundation
import NotchExtensionSDK

/// Owns extension enabled state, reconciles defaults, and persists changes.
///
/// Reconciliation:
/// - registers newly discovered definitions using their `defaultEnabled` value,
/// - preserves choices for definitions that already have state,
/// - drops state for definitions that no longer exist.
///
/// `onEnabledChanged` fires only when a value actually changes, so the lifecycle
/// host can react without repeatedly activating an already-active extension.
public final class ExtensionManager {
    private let registry: ExtensionRegistry
    private let store: ExtensionStateStore
    private var snapshot: ExtensionStateSnapshot
    private var externalEnabled: [ExtensionIdentity: Bool] = [:]

    /// Called when an extension's enabled state changes. Invoked on the caller's
    /// thread; the app host calls from the main thread.
    public var onEnabledChanged: ((ExtensionIdentity, Bool) -> Void)?

    public init(registry: ExtensionRegistry, store: ExtensionStateStore) {
        self.registry = registry
        self.store = store
        self.snapshot = store.load() ?? ExtensionStateSnapshot()
    }

    /// The persisted snapshot. Exposed for diagnostics and migration.
    public var state: ExtensionStateSnapshot {
        snapshot
    }

    /// Applies defaults for new definitions and removes stale entries.
    public func reconcile() {
        let registered = registry.metadata
        var enabled = snapshot.enabled

        let validKeys = Set(registered.map(\.id.rawValue))
        enabled = enabled.filter { validKeys.contains($0.key) }

        for metadata in registered where enabled[metadata.id.rawValue] == nil {
            enabled[metadata.id.rawValue] = metadata.defaultEnabled
        }

        snapshot.enabled = enabled
        snapshot.schemaVersion = ExtensionStateSnapshot.currentSchemaVersion
        store.save(snapshot)
    }

    public func isEnabled(_ id: ExtensionIdentity) -> Bool {
        if registry.definition(for: id) == nil, let enabled = externalEnabled[id] {
            return enabled
        }
        return snapshot.enabled[id.rawValue] ?? false
    }

    /// Sets transient enabled state for an identity not owned by the registry.
    public func setExternalEnabled(_ enabled: Bool, for id: ExtensionIdentity) {
        externalEnabled[id] = enabled
    }

    /// Removes transient enabled state for an identity not owned by the registry.
    public func removeExternalEnabledState(for id: ExtensionIdentity) {
        externalEnabled.removeValue(forKey: id)
    }

    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity) {
        guard snapshot.enabled[id.rawValue] != enabled else { return }
        snapshot.enabled[id.rawValue] = enabled
        store.save(snapshot)
        onEnabledChanged?(id, enabled)
    }

    /// Registered definitions whose extension is enabled.
    public var enabledMetadata: [ExtensionMetadata] {
        registry.metadata.filter { isEnabled($0.id) }
    }

    /// Registered definitions whose extension is disabled.
    public var disabledMetadata: [ExtensionMetadata] {
        registry.metadata.filter { !isEnabled($0.id) }
    }

    /// Identities whose extension is enabled, sorted.
    public var enabledIDs: [ExtensionIdentity] {
        enabledMetadata.map(\.id)
    }
}
