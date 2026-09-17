//
//  PermissionRefreshCoordinator.swift
//  NotchKit
//
//  The targeted reconciliation used after an explicit status refresh or on app
//  reactivation. It re-attempts a single feature that is desired-enabled and
//  waiting on a permission the user has now granted.
//
//  It is deliberately pure and injectable so it can be tested without a real
//  extension host, and deliberately narrow so it never retries unrelated
//  extensions (in particular, it never touches `.failed` features).
//

import NotchExtensionSDK
import NotchExtensionRuntime

@MainActor
enum PermissionRefreshCoordinator {
    /// Persistently disables a running feature whose required permission was
    /// revoked. A feature still waiting for its initial grant is left enabled.
    static func disableActiveFeatureIfRevoked(
        feature: ExtensionIdentity,
        isEnabled: (ExtensionIdentity) -> Bool,
        phase: (ExtensionIdentity) -> ExtensionRuntimePhase,
        isPermissionGranted: () -> Bool,
        disable: (ExtensionIdentity) -> Void
    ) {
        guard isEnabled(feature), !isPermissionGranted() else { return }
        switch phase(feature) {
        case .activating, .active:
            disable(feature)
        case .inactive, .deactivating, .failed, .requiresPermission:
            break
        }
    }

    /// Re-attempts `feature` when, and only when:
    /// - it is still desired-enabled (refresh must never enable a feature), and
    /// - it is currently blocked on a permission, and
    /// - the permission is now granted.
    ///
    /// Idempotent: every failed guard is a no-op, so repeated refreshes cannot
    /// start duplicate work.
    static func reconcileIfGranted(
        feature: ExtensionIdentity,
        isEnabled: (ExtensionIdentity) -> Bool,
        phase: (ExtensionIdentity) -> ExtensionRuntimePhase,
        isPermissionGranted: () -> Bool,
        retry: (ExtensionIdentity) -> Void
    ) {
        guard isEnabled(feature) else { return }
        guard case .requiresPermission = phase(feature) else { return }
        guard isPermissionGranted() else { return }
        retry(feature)
    }
}
