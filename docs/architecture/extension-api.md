# NotchKit Extension API

Status: Phase 1 contracts plus the runtime lifecycle. API version `1.0.0`.

This document specifies the public contracts in the `NotchExtensionSDK` module
and the behaviour guaranteed by the `NotchExtensionRuntime` module. See
[`extensions.md`](extensions.md) for architectural context and
[`adr/0002-extension-distribution-tiers.md`](adr/0002-extension-distribution-tiers.md)
for the distribution tiers. Both modules are statically linked into the macOS
app; they are not downloadable extensions, and this phase has no catalog,
download, installation, or dynamic loading mechanism.

## Compatibility rules

- `ExtensionAPIVersion.current` is `1.0.0`.
- Compatibility is **not** major-only. `ExtensionCompatibility.validate` rejects
  a manifest when:
  - its `artifactKind` is not supported by this host build (only `.compiledIn`);
  - the running host version is outside `supportedHostVersions`;
  - the running SDK version is outside `supportedSDKVersions`;
  - an entry point's kind lacks a declared capability, or a declared capability
    has no matching entry point;
  - two entry points share an id.
- Incompatible manifests are rejected at registration; they are never silently
  dropped at render time.

## Identity

```swift
public struct ExtensionIdentity: Hashable, Comparable, Codable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws       // validates reverse-DNS
    public init(validating rawValue: String) throws
}
```

Validation rules match [`extensions.md`](extensions.md#extension-identity).
Invalid identities fail with `ExtensionIdentityError.invalidFormat`.
`DestinationID` and `ContributionID` are similarly-validated stable strings.

## Metadata (the manifest)

`ExtensionMetadata` is the runtime-free, `Codable` manifest. It never contains
closures, views, or services. It is the canonical shape of
`NotchExtensions/manifests/manifest.schema.json`.

```swift
public struct ExtensionMetadata: Identifiable, Codable, Hashable, Sendable {
    public let id: ExtensionIdentity
    public let displayName: String
    public let summary: String?
    public let iconSystemName: String
    public let extensionVersion: ExtensionVersion
    public let apiVersion: ExtensionAPIVersion
    public let supportedHostVersions: ExtensionVersionRange
    public let supportedSDKVersions: ExtensionVersionRange
    public let capabilities: Set<ExtensionCapability>
    public let artifactKind: ExtensionArtifactKind
    public let entryPoints: [ExtensionEntryPoint]
    public let defaultEnabled: Bool
    public let source: ExtensionSource
}
```

`ExtensionEntryPoint` declares an attachment (`id`, `kind`, optional reserved
`sceneName`, free-form `metadata`) without carrying content.

## Definition and runtime instance

```swift
public struct ExtensionDefinition {
    public let metadata: ExtensionMetadata
    public let makeInstance: @MainActor (ExtensionContext) -> any NotchExtension
}

@MainActor
public protocol NotchExtension: AnyObject {
    func activate() async throws
    func deactivate()
    func openDestinations() -> [NotchOpenDestination]
    func closedNotchContributions() -> [ClosedNotchContribution]
    func settingsDestinations() -> [ExtensionSettingsDestination]
}
```

- **Metadata listing never instantiates an extension.** `makeInstance` is called
  only on activation.
- `makeView`-style factories are for **trusted, compiled-in** extensions only;
  they are never encoded or sent across a process boundary.

## Host services

```swift
@MainActor
public final class ExtensionContext {
    public let identity: ExtensionIdentity
    public let cancellation: ExtensionCancellationBag
    public let presentation: any NotchPresentationService
    public let store: any ExtensionScopedStore
    public let permissions: any NotchPermissionService
}

@MainActor
public protocol NotchPresentationService: AnyObject {
    var availableDisplays: [DisplayID] { get }
    func request(_ request: PresentationRequest, target: PresentationTarget)
}

public protocol ExtensionScopedStore: AnyObject {
    var schemaVersion: Int { get }
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

@MainActor
public protocol NotchPermissionService: AnyObject {
    func status(for permission: NotchPermission) -> NotchPermissionStatus
    func request(_ permission: NotchPermission) async -> NotchPermissionStatus
}
```

Presentation requests are **display-targeted** (`PresentationTarget`: `.active`,
`.all`, or `.display(DisplayID)`) and geometry-independent. Extensions never
receive windows, screens, geometry, or singleton managers.

## Cancellation

`ExtensionCancellationBag` registers tasks, timers, notification observers, or
custom teardown blocks; `cancelAll()` runs each exactly once, in reverse order,
and registering after cancellation runs immediately. The host cancels the bag
when an extension deactivates or fails.

## Lifecycle host

```swift
@MainActor
public final class ExtensionHost {
    public init(registry:manager:contributions:makeContext:)
    public func start()
    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity)
    public func reconcileNow()
    public func phase(for id: ExtensionIdentity) -> ExtensionRuntimePhase
    public func remove(_ id: ExtensionIdentity)
    public func shutdown()
}
```

Phases: `inactive → activating → active → deactivating → inactive`, with
`failed` on activation error. Repeated and rapid enable/disable is coalesced by
a per-extension generation counter; at most one instance exists and stale
callbacks are ignored. Activation failure deactivates and tears down the
instance before recording `failed`.

## Registry, manager, and contributions

```swift
public final class ExtensionRegistry {
    public init(hostVersion: ExtensionVersion, sdkVersion: ExtensionAPIVersion = .current)
    public func register(_ definition: ExtensionDefinition) throws
    public var definitions: [ExtensionDefinition] { get }
    public var metadata: [ExtensionMetadata] { get }
}

public final class ExtensionManager {
    public init(registry: ExtensionRegistry, store: ExtensionStateStore)
    public func reconcile()
    public func isEnabled(_ id: ExtensionIdentity) -> Bool
    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity)
    public var onEnabledChanged: ((ExtensionIdentity, Bool) -> Void)?
}

@MainActor
public final class ContributionStore {
    public func set(open:closed:settings:for:) throws
    public func removeContributions(for id: ExtensionIdentity)
    public var openDestinations: [NotchOpenDestination] { get }
}
```

Only active extensions contribute content; disabling removes contributions
before deactivation.

## Per-display routing

```swift
@MainActor
public final class PresentationCoordinator: ObservableObject {
    public func router(for display: DisplayID) -> NotchRouter
    public func refreshAll()
    public var displayIDs: [DisplayID] { get }
}

@MainActor
public final class NotchRouter: ObservableObject {
    public init(displayID:homeID:contributions:manager:onChanged:)
    @Published public private(set) var activeDestinationID: DestinationID
    public func select(_ id: DestinationID)
    public var availableDestinations: [NotchOpenDestination] { get }
}
```

Each display has its own router, so selecting a destination on one display does
not change another. Selection falls back to Home when a destination is missing,
unavailable, or belongs to a disabled extension.

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

Unchanged: pure and deterministic, per region, by priority, recency,
tie-breaker, then id. Core supplies available contributions.

## What the API intentionally omits

- No generic event bus or "run arbitrary code on every event" hook.
- No direct window, geometry, monitor, or permission APIs (only the narrow host
  service protocols above).
- No remote manifest, installer, or network surface.
- No `ExtensionFoundation`/`ExtensionKit` types.