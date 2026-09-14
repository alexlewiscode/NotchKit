# NotchKit Extension API

Status: Phase 1. API version `1.0.0`.

This document specifies the public contracts in the `NotchExtensionSDK` module and the
behaviour guaranteed by the `NotchExtensionRuntime` runtime. See
[`extensions.md`](extensions.md) for architectural context.

## Compatibility rules

- `ExtensionAPIVersion.current` is `1.0.0`.
- A descriptor is compatible when its major version equals the running core's
  major version.
- Incompatible descriptors are rejected at registration; they are never
  silently dropped at render time.
- The API is semantic-versioned. Minor releases are additive; major releases may
  remove or change symbols.

## Identity

```swift
public struct ExtensionIdentity: Hashable, Comparable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws       // validates reverse-DNS
    public init(validating rawValue: String) throws
}
```

Validation rules match [`extensions.md`](extensions.md#extension-identity).
Invalid identities fail with `ExtensionIdentityError.invalidFormat`.

## Descriptor

```swift
public struct ExtensionDescriptor: Identifiable, Sendable {
    public let id: ExtensionIdentity
    public let displayName: String
    public let summary: String?
    public let iconSystemName: String
    public let apiVersion: ExtensionAPIVersion
    public let source: ExtensionSource
    public let capabilities: Set<ExtensionCapability>
    public let defaultEnabled: Bool
    public let openDestinations: [NotchOpenDestination]
    public let closedNotchContributions: [ClosedNotchContribution]
    public let settingsDestinations: [ExtensionSettingsDestination]
}
```

- `source` is `.firstParty` in Phase 1.
- `capabilities` declares the kinds of contributions present; the registry
  validates that declared capabilities match supplied contributions.
- `defaultEnabled` seeds `ExtensionManager` reconciliation on first run.

## Open destinations

```swift
public struct NotchOpenDestination: Identifiable, Sendable {
    public let id: DestinationID
    public let title: String
    public let iconSystemName: String
    public let order: Int
    public let isAvailable: @Sendable (ClosedNotchRenderSnapshot) -> Bool
    public let makeView: @MainActor @Sendable () -> AnyView
}
```

- `id` is a stable string (reverse-DNS by convention), unique across the
  registry.
- `order` determines tab ordering; ties break on `title`, then `id`.
- `isAvailable` gates visibility. `NotchRouter` falls back to Home when the
  active destination becomes unavailable or its extension is disabled.

## Closed-notch contributions

```swift
public enum ClosedNotchRegion: String, CaseIterable, Sendable {
    case leading, exclusion, trailing
}

public struct ClosedNotchContribution: Identifiable, Sendable {
    public let id: ContributionID
    public let extensionID: ExtensionIdentity
    public let region: ClosedNotchRegion
    public let priority: Int
    public let tieBreaker: String
    public let isAvailable: @Sendable (ClosedNotchRenderSnapshot) -> Bool
    public let makeView: @MainActor @Sendable () -> AnyView
    public let preferredChinWidth: (@Sendable (ClosedNotchRenderSnapshot) -> CGFloat)?
}
```

Selection order per region is defined in
[`extensions.md`](extensions.md#deterministic-closed-notch-selection).
`preferredChinWidth` lets a winning contribution drive the closed chin width
deterministically; when `nil`, core uses its default geometry.

## Settings destinations

```swift
public struct ExtensionSettingsDestination: Identifiable, Sendable {
    public let id: DestinationID
    public let title: String
    public let iconSystemName: String
    public let isAvailable: @Sendable (ClosedNotchRenderSnapshot) -> Bool
    public let makeView: @MainActor @Sendable () -> AnyView
}
```

Phase 1 keeps existing feature settings in place. The Extensions hub only needs
to route to a declared destination; it does not own those settings.

## Render snapshot

```swift
public struct ClosedNotchRenderSnapshot: Sendable {
    public let isNotchOpen: Bool
    public let isHiddenOnClosed: Bool
    public let isMediaActive: Bool
    public let isMediaIdle: Bool
    public let hasInlineHUD: Bool
    public let hasExpandingView: Bool
    public let expandingViewKind: String?
    public let sneakPeekKind: String?
    public let isSneakPeekVisible: Bool
    public let flags: [String: Bool]
}
```

The snapshot contains only render-relevant primitives; it never exposes
`BoringViewModel`, managers, or window types. Core builds it once per render and
passes the same value to availability predicates and the renderer so selection
is deterministic within a frame.

## Registry

```swift
public final class ExtensionRegistry {
    public func register(_ descriptor: ExtensionDescriptor) throws
    public var descriptors: [ExtensionDescriptor] { get }
    public func descriptor(for id: ExtensionIdentity) -> ExtensionDescriptor?
    public func openDestination(for id: DestinationID) -> NotchOpenDestination?
    public func settingsDestination(for id: DestinationID) -> ExtensionSettingsDestination?
    public var openDestinations: [NotchOpenDestination] { get }
    public var closedNotchContributions: [ClosedNotchContribution] { get }
}
```

`register` throws on:

- `duplicateExtensionID`,
- `duplicateDestinationID`,
- `incompatibleAPIVersion`,
- `capabilityMismatch`.

## Manager

```swift
public final class ExtensionManager {
    public init(registry: ExtensionRegistry, store: ExtensionStateStore)
    public func reconcile()                       // apply defaults for new descriptors
    public func isEnabled(_ id: ExtensionIdentity) -> Bool
    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity)
    public var enabledDescriptors: [ExtensionDescriptor] { get }
}
```

- Enabled state is persisted through `ExtensionStateStore`, defaulting to
  `UserDefaultsExtensionStateStore`.
- Reconciliation adds newly registered descriptors using `defaultEnabled`,
  preserves existing choices, and drops state for descriptors that no longer
  exist.
- The store records a schema version so the persistence format can migrate.

## Router

```swift
@MainActor
public final class NotchRouter: ObservableObject {
    public init(registry: ExtensionRegistry, manager: ExtensionManager, homeID: DestinationID)
    @Published public private(set) var activeDestinationID: DestinationID
    public func select(_ id: DestinationID)
    public var availableDestinations: [NotchOpenDestination] { get }
    public func destinationView(for id: DestinationID) -> AnyView?
}
```

- Selection is by stable id, not an enum.
- `select` rejects unavailable or disabled destinations and falls back to Home.
- If the active destination becomes unavailable (for example its extension is
  disabled), the router falls back to Home.

## Closed-notch selection

```swift
public enum ClosedNotchSelection {
    public static func select(
        from contributions: [ClosedNotchContribution],
        snapshot: ClosedNotchRenderSnapshot,
        recency: [ContributionID: Int]
    ) -> [ClosedNotchRegion: ClosedNotchContribution]
}
```

Pure and deterministic. Core supplies available contributions (already filtered
for disablement) and recency ranks.

## What the API intentionally omits

- No generic event bus or "run arbitrary code on every event" hook.
- No direct window, geometry, monitor, or permission APIs.
- No remote manifest or installer surface.
- No `ExtensionFoundation`/`ExtensionKit` types.
