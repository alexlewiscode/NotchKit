//
//  ExtensionManager.swift
//  NotchExtensions
//
//  Owns enabled/disabled state and reconciles it with the registry.
//

import Foundation
import NotchAPI

/// Owns extension enabled state, reconciles defaults, and persists changes.
///
/// Reconciliation:
/// - registers newly discovered descriptors using their `defaultEnabled` value,
/// - preserves choices for descriptors that already have state,
/// - drops state for descriptors that no longer exist.
public final class ExtensionManager {
    private let registry: ExtensionRegistry
    private let store: ExtensionStateStore
    private var snapshot: ExtensionStateSnapshot

    public init(registry: ExtensionRegistry, store: ExtensionStateStore) {
        self.registry = registry
        self.store = store
        self.snapshot = store.load() ?? ExtensionStateSnapshot()
    }

    /// The persisted snapshot. Exposed for diagnostics and migration.
    public var state: ExtensionStateSnapshot {
        snapshot
    }

    /// Applies defaults for new descriptors and removes stale entries.
    public func reconcile() {
        let registered = registry.descriptors
        var enabled = snapshot.enabled

        let validKeys = Set(registered.map(\.id.rawValue))
        enabled = enabled.filter { validKeys.contains($0.key) }

        for descriptor in registered where enabled[descriptor.id.rawValue] == nil {
            enabled[descriptor.id.rawValue] = descriptor.defaultEnabled
        }

        snapshot.enabled = enabled
        snapshot.schemaVersion = ExtensionStateSnapshot.currentSchemaVersion
        store.save(snapshot)
    }

    public func isEnabled(_ id: ExtensionIdentity) -> Bool {
        snapshot.enabled[id.rawValue] ?? false
    }

    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity) {
        snapshot.enabled[id.rawValue] = enabled
        store.save(snapshot)
    }

    /// Registered descriptors whose extension is enabled.
    public var enabledDescriptors: [ExtensionDescriptor] {
        registry.descriptors.filter { isEnabled($0.id) }
    }

    /// Registered descriptors whose extension is disabled.
    public var disabledDescriptors: [ExtensionDescriptor] {
        registry.descriptors.filter { !isEnabled($0.id) }
    }
}
