//
//  HostServices.swift
//  NotchExtensionSDK
//
//  Narrow, geometry-independent capabilities the host offers to an activated
//  extension. Extensions never reach app internals or singletons directly.
//

import Foundation

/// Opaque identity of a presentation surface (a display).
///
/// The host maps a `DisplayID` to a concrete window/screen; extensions never
/// see `NSScreen`, `NSWindow`, geometry, or window-management APIs.
public struct DisplayID: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: DisplayID, rhs: DisplayID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where a presentation request should be applied.
public enum PresentationScope: String, Codable, Sendable {
    /// The display currently interacting with the notch.
    case active
    /// Every display.
    case all
    /// One explicit display.
    case display
}

/// An explicit, display-targeted presentation target.
public struct PresentationTarget: Hashable, Codable, Sendable {
    public let scope: PresentationScope
    public let display: DisplayID?

    public init(scope: PresentationScope, display: DisplayID? = nil) {
        self.scope = scope
        self.display = display
    }

    /// The currently active display.
    public static let active = PresentationTarget(scope: .active)
    /// Every display.
    public static let all = PresentationTarget(scope: .all)
    /// One explicit display.
    public static func display(_ id: DisplayID) -> PresentationTarget {
        PresentationTarget(scope: .display, display: id)
    }
}

/// A geometry-independent request to change presentation state.
///
/// These are requests, not commands: core decides how (and whether) to present.
public enum PresentationRequest: Equatable, Sendable {
    /// Open the notch and select a destination.
    case open(DestinationID)
    /// Close the notch.
    case close
    /// Show a transient sneak peek.
    case showSneakPeek(kind: String, value: Double?, duration: TimeInterval)
    /// Hide any transient sneak peek.
    case hideSneakPeek
}

/// Display-targeted presentation requests.
@MainActor
public protocol NotchPresentationService: AnyObject {
    /// Displays the host can currently present on.
    var availableDisplays: [DisplayID] { get }
    /// Applies a presentation request to a target.
    func request(_ request: PresentationRequest, target: PresentationTarget)
}

/// Namespaced, versioned persistence scoped to one extension.
public protocol ExtensionScopedStore: AnyObject {
    /// Schema version of the stored payloads.
    var schemaVersion: Int { get }
    /// Reads the raw payload for a key, if present.
    func data(forKey key: String) -> Data?
    /// Writes (or removes, when `nil`) the raw payload for a key.
    func set(_ data: Data?, forKey key: String)
}

/// A capability an extension may need the user to grant.
public enum NotchPermission: String, Codable, CaseIterable, Sendable {
    case accessibility
    case mediaControl
    case camera
    case screenRecording
}

/// The current state of a permission.
public enum NotchPermissionStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
}

/// Queries and requests permissions through the host.
///
/// Extensions never talk to TCC, the XPC helper, or event taps directly.
@MainActor
public protocol NotchPermissionService: AnyObject {
    func status(for permission: NotchPermission) -> NotchPermissionStatus
    func request(_ permission: NotchPermission) async -> NotchPermissionStatus
}
