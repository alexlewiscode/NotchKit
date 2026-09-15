//
//  NotchExtension.swift
//  NotchExtensionSDK
//
//  The runtime instance model. Metadata is separate; instantiating an
//  extension is what creates feature services.
//

import SwiftUI

/// The activated, in-process instance of an extension.
///
/// Metadata listing never creates one of these. The host creates an instance
/// only when the extension is enabled, calls `activate()`, and calls
/// `deactivate()` when the extension is disabled or removed.
///
/// This protocol and its content factories are for **trusted, compiled-in**
/// extensions only. Its closures are never encoded or sent across a process
/// boundary.
@MainActor
public protocol NotchExtension: AnyObject {
    /// Starts the extension and any services it owns.
    ///
    /// A throw marks the extension failed; the host then calls `deactivate()`
    /// and discards the instance.
    func activate() async throws

    /// Stops the extension. Must be safe to call after a partial or failed
    /// `activate()`, and safe to call more than once.
    func deactivate()

    /// Open-notch destinations this instance contributes while active.
    func openDestinations() -> [NotchOpenDestination]

    /// Closed-notch contributions this instance contributes while active.
    func closedNotchContributions() -> [ClosedNotchContribution]

    /// Settings destinations this instance contributes while active.
    ///
    /// - Deprecated: Settings are declared lifecycle-independently on
    ///   `ExtensionDefinition.settings`, so a disabled or failed extension keeps
    ///   a reachable configuration page. The host no longer publishes instance
    ///   settings destinations into the contribution store. This requirement is
    ///   kept as a compatibility surface and ignores its return value.
    @available(
        *,
        deprecated,
        message: "Declare settings on ExtensionDefinition.settings; the host no longer reads instance settings destinations."
    )
    func settingsDestinations() -> [ExtensionSettingsDestination]
}

public extension NotchExtension {
    func activate() async throws {}
    func deactivate() {}
    func openDestinations() -> [NotchOpenDestination] { [] }
    func closedNotchContributions() -> [ClosedNotchContribution] { [] }
    func settingsDestinations() -> [ExtensionSettingsDestination] { [] }
}

/// State of an extension's runtime instance.
public enum ExtensionRuntimePhase: Equatable, Sendable {
    /// Registered but not enabled.
    case inactive
    /// Activation is in progress.
    case activating
    /// Activated; contributions are live.
    case active
    /// Deactivation is in progress.
    case deactivating
    /// Activation threw; the instance was torn down.
    case failed(String)
    /// The user's desired state is enabled, but activation is blocked on a
    /// permission the user must grant. Unlike `.failed`, this is not an error
    /// state: the toggle stays on and the host waits for an explicit retry.
    case requiresPermission(String)
}

/// A typed activation failure an extension can throw to let the host present
/// an accurate, actionable state instead of a generic error.
public enum ExtensionActivationError: Error, Equatable {
    /// Activation needs a permission the user has not granted. The host records
    /// `.requiresPermission` and does not report the extension as active.
    case permissionRequired(NotchPermission)
    /// Activation needs a device that is currently unavailable.
    case deviceUnavailable(String)
}

/// A point-in-time runtime state for one extension.
public struct ExtensionRuntimeState: Equatable, Sendable {
    public let id: ExtensionIdentity
    public let phase: ExtensionRuntimePhase

    public init(id: ExtensionIdentity, phase: ExtensionRuntimePhase) {
        self.id = id
        self.phase = phase
    }
}
