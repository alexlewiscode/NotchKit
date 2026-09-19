# NotchKit Extension API

Status: Phase 1 contracts plus Phase 2 package/wire contracts. API version `1.2.0`.

This document specifies the public contracts in the `NotchExtensionSDK` module
and the behaviour guaranteed by the `NotchExtensionRuntime` module. See
[`extensions.md`](extensions.md) for architectural context and
[`adr/0002-extension-distribution-tiers.md`](adr/0002-extension-distribution-tiers.md)
for the distribution tiers. Tier A modules are statically linked. Phase 2 adds a
user-selected local package installer and a macOS 26+ out-of-process adapter; it
does not add catalog or network download behavior.

## Compatibility rules

- `ExtensionAPIVersion.current` is `1.2.0`.
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

### Versioning surfaces

Three distinct version surfaces are in play and are not interchangeable:

- **Swift SDK/API version** (`ExtensionAPIVersion.current`): the source-level
  contract of the `NotchExtensionSDK` module. Additive, source-compatible
  changes bump the minor component; breaking changes bump the major. The
  `1.1.0` added `ExtensionDefinition.settings`; `1.2.0` adds package,
  declarative UI, and out-of-process wire contracts.
- **Manifest schema version**: the serialized JSON shape
  (`manifest.schema.json`). `ExtensionDefinition` is not serialized, so adding
  `settings` does not change the schema; existing `1.0.0` manifests remain
  structurally valid.
- **Runtime compatibility checks**: `ExtensionCompatibility.validate` compares
  the running host and SDK versions against each manifest's
  `supportedHostVersions`/`supportedSDKVersions`. A `1.2.0` running SDK is within
  existing `1.x` ranges, so no Tier A manifest change is required. It
  deliberately does not compare `metadata.apiVersion` to the running version;
  do not treat that omission as a reason to skip the minor bump above.

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

`ExtensionMetadata` is the runtime-free, `Codable` Tier A manifest. It never
contains closures, views, or services. It is the canonical shape of
`NotchExtensions/manifests/manifest.schema.json` and is embedded unchanged in a
v2 package manifest.

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
    /// Lifecycle-independent settings pages. Must not create or capture a live
    /// NotchExtension, an ExtensionContext, or a long-lived service.
    public let settings: @MainActor () -> [ExtensionSettingsDestination]
    public let makeInstance: @MainActor (ExtensionContext) -> any NotchExtension
}

@MainActor
public protocol NotchExtension: AnyObject {
    func activate() async throws
    func deactivate()
    func openDestinations() -> [NotchOpenDestination]
    func closedNotchContributions() -> [ClosedNotchContribution]
    @available(*, deprecated, message: "Declare settings on ExtensionDefinition.settings")
    func settingsDestinations() -> [ExtensionSettingsDestination]
}
```

- **Metadata listing never instantiates an extension.** `makeInstance` is called
  only on activation.
- **Settings declaration never instantiates an extension.** `settings` is
  evaluated when the host builds or renders its settings catalog, so a disabled
  or failed extension keeps a reachable configuration page.
- `makeView`-style factories are for **trusted, compiled-in** extensions only;
  they are never encoded or sent across a process boundary.
- `settingsDestinations()` is retained only as a source-compatibility surface and
  is ignored by the host.

### Migrating settings off the instance method

`settingsDestinations()` still compiles, but the host no longer calls it. This is
**source compatibility without behavioural compatibility**: an extension whose
metadata declares a `settings-destination` entry point but that keeps returning
its page from the instance method will build and run, but its settings page will
be unreachable. The host logs a nonfatal diagnostic (it never asserts) when that
mismatch is detected at catalog-build time; it does not activate the extension to
find the old page.

Move the declaration onto the definition. The destination `id` must match the
metadata entry point id.

```swift
// Before: only produced while the instance was active.
final class BatteryExtension: NotchExtension {
    func settingsDestinations() -> [ExtensionSettingsDestination] {
        [ExtensionSettingsDestination(
            id: BatteryIds.settingsDestination,
            title: "Battery",
            iconSystemName: "battery.100",
            isAvailable: { true },
            makeView: { AnyView(BatterySettingsView()) }
        )]
    }
}

// After: declared lifecycle-independently, reachable while disabled or failed.
let definition = ExtensionDefinition(
    metadata: try BatteryManifest.metadata(),
    settings: {
        [ExtensionSettingsDestination(
            id: BatteryIds.settingsDestination,
            title: "Battery",
            iconSystemName: "battery.100",
            isAvailable: { true },
            makeView: { AnyView(BatterySettingsView()) }
        )]
    }
) { context in
    BatteryExtension(context: context, monitor: monitor)
}
```

The `settings` closure may read configuration and build views on demand, but must
not create or capture a live `NotchExtension`, an `ExtensionContext`, or a
long-lived service.

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

## Package manifest v2

`ExtensionPackageManifest` is the local-developer package envelope. Its strict
serialized shape is
`NotchExtensions/Schemas/extension-manifest-v2.schema.json`; the SDK validator
adds cross-field rules that JSON Schema does not express.

```swift
public struct ExtensionPackageManifest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let metadata: ExtensionMetadata
    public let artifact: ExtensionPackageArtifact
    public let permissions: Set<ExtensionDeclaredPermission>
    public let hostActions: Set<ExtensionHostAction>
    public let entryPoints: [ExtensionPackageEntryPoint]
}
```

The current installer accepts only `metadata.source == .localDeveloper` and
matching `.appExtension` artifact kinds. `ExtensionPackageArtifact.appExtension`
declares provider, nested extension, extension point, minimum macOS version,
inclusive integer protocol range, and `arm64`/`x86_64` architectures. The SDK
requires macOS 26 or newer, positive ordered protocol versions, at least one
architecture and entry point, provider/extension identifier containment, and a
one-to-one id/kind match between metadata entry points and package descriptors.

Package entry points choose `remote-scene` or `declarative` presentation. A
remote scene requires a non-empty package `sceneName`; a declarative descriptor
must omit it. The duplicate `entryPoint` object is intentional: it binds the
package presentation descriptor back to the stable metadata contract. Metadata
entry-point `sceneName` remains part of the pre-existing Tier A encoding and is
not the package presentation scene.

Permissions are disclosures for `accessibility`, `media-control`, `camera`, or
`screen-recording`, including whether each is required, whether the host or
extension owns it, and a non-empty usage-description key. Host actions are an
allow-list of `open-destination`, `close-notch`, `show-sneak-peek`, and
`hide-sneak-peek`. Open/close require an open destination, and show/hide sneak
peek must be declared together.

The schema enforces closed object shapes recursively, enum values, canonical
semantic-version/range syntax, identifier syntax, and collection uniqueness
where representable. The executable validator remains authoritative for range
ordering, identifier relationships, entry-point correspondence/uniqueness,
permission-kind uniqueness, and host-action dependencies.

## Local package execution boundary

- Installation records and ExtensionKit discovery are independent inputs.
- System approval and NotchKit's desired-enabled state are independent gates.
- Native matching uses both nested bundle identifier and extension-point
  identifier and rejects ambiguity.
- Sessions handshake before becoming active and validate protocol, extension,
  entry-point, and extension version.
- Declarative render/action payloads cross as bounded Codable `Data`; SwiftUI
  views and closures never cross.
- Host actions are accepted only when allow-listed and returned from a
  host-initiated user gesture. Unsolicited host-action requests are rejected.
- Native execution is macOS 26+ only. Tier A and macOS 14 behavior are unchanged.

## What the API intentionally omits

- No generic event bus or "run arbitrary code on every event" hook.
- No direct window, geometry, monitor, or permission APIs (only the narrow host
  service protocols above).
- No remote manifest, network download, or catalog surface.
- No `ExtensionFoundation`/`ExtensionKit` types in the portable SDK contracts or
  macOS 14 execution path.
