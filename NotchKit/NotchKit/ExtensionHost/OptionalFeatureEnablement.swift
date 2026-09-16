//
//  OptionalFeatureEnablement.swift
//  NotchKit
//
//  Decides when the expanded notch should present the "no features enabled"
//  empty state.
//
//  The decision reads the authoritative enablement state rather than the
//  contribution list, because an enabled extension can legitimately contribute
//  nothing at a given moment. Required infrastructure (Home) and features that
//  are not registered in this build (Battery in `NotchKitCoreOnly`) are excluded.
//

import NotchExtensionSDK
import NotchExtensionRuntime

/// Pure decision helpers for the all-off empty state.
enum OptionalFeatureEnablement {
    /// Whether a feature counts as "on" for the empty state.
    ///
    /// The authoritative desired state wins: a feature the user enabled still
    /// counts as on while it is activating, active, failed, or waiting on a
    /// permission, so enablement guidance is never shown for a feature the user
    /// already turned on. A feature being torn down also stays on until it
    /// reaches `.inactive`, so the empty state never flashes mid-transition.
    static func isOn(isEnabled: Bool, phase: ExtensionRuntimePhase) -> Bool {
        if isEnabled { return true }
        switch phase {
        case .inactive:
            return false
        case .activating, .active, .deactivating, .failed, .requiresPermission:
            return true
        }
    }

    /// Registered optional features: everything except required infrastructure
    /// such as Home. Features that are not registered in this build (for example
    /// Battery in `NotchKitCoreOnly`) are naturally absent.
    static func optionalFeatureIdentities(
        fromRegistered registered: [ExtensionIdentity]
    ) -> [ExtensionIdentity] {
        registered.filter { $0 != BuiltInExtensionIDs.home }
    }

    /// Whether every available optional feature is off.
    static func shouldShowEmptyState(
        optionalFeatures: [ExtensionIdentity],
        isEnabled: (ExtensionIdentity) -> Bool,
        phase: (ExtensionIdentity) -> ExtensionRuntimePhase
    ) -> Bool {
        !optionalFeatures.contains { isOn(isEnabled: isEnabled($0), phase: phase($0)) }
    }
}

extension NotchKitRuntime {
    /// Registered optional features for the all-off empty state.
    var availableOptionalFeatureIdentities: [ExtensionIdentity] {
        OptionalFeatureEnablement.optionalFeatureIdentities(
            fromRegistered: registry.metadata.map(\.id)
        )
    }

    /// Whether the expanded notch should present the empty state instead of the
    /// Home content.
    var shouldShowEmptyState: Bool {
        OptionalFeatureEnablement.shouldShowEmptyState(
            optionalFeatures: availableOptionalFeatureIdentities,
            isEnabled: { manager.isEnabled($0) },
            phase: { host.phase(for: $0) }
        )
    }
}
