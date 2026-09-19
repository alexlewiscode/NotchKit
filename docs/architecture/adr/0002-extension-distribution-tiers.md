# ADR 0002: Extension distribution tiers and the path to independent installation

- Status: Accepted; Tier B feasibility proven on macOS 26, local integration in progress
- Date: 2026-09-15
- Supersedes in part: ADR 0001 (which claimed `ExtensionFoundation`/`ExtensionKit`
  were unavailable on macOS 14; see "Correction to ADR 0001")

## Context

Phase 1 established a compile-time, in-process extension architecture
(`NotchExtensionSDK` contracts plus `NotchExtensionRuntime`). It deliberately
did not choose a mechanism for independently distributed extensions. This ADR
separates the concerns and records what is actually possible on the macOS 14
deployment target, so later work does not conflate them.

Three different things have been described loosely as "extensions":

1. first-party Swift code compiled into the app;
2. independently distributed artifacts that run outside the app;
3. the catalog/installation service that would distribute (2).

They have different trust, packaging, and platform properties and must be
specified separately.

## Decision

### Tier A — compile-time first-party modules

- Statically linked Swift, running in-process with full trust.
- May use `makeView`-style SwiftUI factories and closures.
- Registered as `ExtensionDefinition` (metadata + `makeInstance`), activated and
  torn down by `ExtensionHost`.
- This is the **only** tier the production app runs today.

### Tier B — independently distributed extension artifacts

- Code that runs outside the host process.
- **No SwiftUI view objects, closures, or arbitrary Swift structs cross the
  process boundary.** UI is either (a) hosted as an opaque remote scene, or
  (b) rendered by the host from declarative data.
- Reserved in the manifest as `artifactKind: app-extension | xpc-service`.
- The Phase 2 local-developer path uses an availability-gated macOS 26 adapter.
  Its package/install policy is defined by ADR 0003 and remains subject to the
  Phase 2 verification gates.

### Tier C — catalog and distribution services

- The `NotchAPI` server: catalog metadata, distribution, submissions, and
  validation status.
- Not implemented. No network code in the app. Described in `NotchAPI/README.md`.
- A user-selected local package installer is a bounded Tier B development tool,
  not evidence that Tier C exists.

## macOS 14 platform evaluation

Availability verified against Apple's documentation (all URLs are
`developer.apple.com/documentation/...`; macOS versions quoted from each page's
availability block). The important finding is that the *declaration and
discovery* layer is newer than the framework's headline availability.

| Symbol | macOS | Note |
| --- | --- | --- |
| `ExtensionFoundation` framework | 13.0+ | available on macOS 14 |
| `ExtensionKit` framework | 13.0+ | available on macOS 14 |
| `AppExtension` / `AppExtensionConfiguration` | 13.0+ | extension entry point |
| `AppExtensionConfiguration.accept(connection:)` | 13.0+ | accepts `NSXPCConnection` |
| `AppExtensionIdentity` | 13.0+ | identity of a discovered extension |
| `AppExtensionProcess`, `invalidate()`, `makeXPCConnection()` | 13.0+ | launch + connect |
| `AppExtensionProcess.Configuration.onInterruption` | 13.0+ | crash/interruption handler |
| `EXHostViewController`, `Configuration`, `makeXPCConnection()`, delegate | 13.0+ | hosts remote UI |
| `EXAppExtensionBrowserViewController` | 13.0+ | enable/disable UI |
| `PrimitiveAppExtensionScene`, `AppExtensionScene`, `AppExtensionSceneConfiguration` | 13.0+ | extension-side scenes |
| `NSXPCConnection`, `NSXPCInterface` | 10.8+ | Foundation XPC transport |
| `XPCSession`, `XPCPeerHandler` | 14.0+ | XPC framework Swift API |
| `AppExtensionPoint` and all attributes (`Definition`, `Name`, `UserInterface`, `Scope`, `EnhancedSecurity`, `Bind`, `Monitor`) | **26.0+** | not on macOS 14 |
| `ConnectionHandler` | **26.0+** | not on macOS 14 |
| `AppExtensionProcess.makeXPCSession()` | **26.0+** | not on macOS 14 |
| Programmatic `.appexpt` generation (`EX_ENABLE_EXTENSION_POINT_GENERATION`) | **26.0+** | macOS 14 would need a hand-authored `.appexpt` |

Consequences for macOS 14:

- ExtensionKit's host/UI surface and ExtensionFoundation's process/connection
  surface are usable, but the modern Swift way to declare extension points and
  generate `.appexpt` is not. A macOS 14 host would need a hand-authored
  `.appexpt` and manual plists.
- `EXAppExtensionBrowserViewController` (enable/disable UI) and the
  default-disabled/approval behaviour apply, but there is **no documented API
  that reports whether an extension is bundled or separately installed**;
  `AppExtensionIdentity` exposes only bundle id, extension-point id, and
  localized name. Scope is an internal matching concern.

## XPC transport and encoding (what actually crosses)

- `NSXPCConnection`/`NSXPCInterface` are built from **Objective-C protocols**.
  The wire vocabulary is property-list types, explicitly declared collection
  classes, and `NSSecureCoding`-conforming objects. SwiftUI `View`, generic
  closures, and arbitrary Swift structs have no Objective-C/property-list
  representation and do not cross.
- The XPC framework's `XPCSession`/`XPCPeerHandler` is a different transport
  whose messages are Swift `Encodable`/`Decodable`; the framework performs the
  encoding.
- **`Codable` alone is not an XPC wire contract.** A `Codable` value crosses
  only when a transport encodes it — XPC-framework messages, or `Data`/
  property-list payloads over `NSXPCConnection`.
- On macOS 14 the only ExtensionFoundation-supported contract is Foundation
  `NSXPCConnection` via `accept(connection:)` + `makeXPCConnection()`.
  ExtensionFoundation's XPC-framework integration (`makeXPCSession()`,
  `ConnectionHandler`) is macOS 26+.

## UI presentation model

- The host does **not** receive view objects. It presents an
  `EXHostViewController` (wrapped in `NSViewControllerRepresentable` for
  SwiftUI) configured with an extension identity and a scene id, and treats the
  content as opaque. The extension delivers scenes via
  `PrimitiveAppExtensionScene`; only display (`sceneName`) and data messages
  cross.
- Therefore ADR 0001's "marshal descriptors and view/content factories across a
  process boundary" was wrong. It is corrected here and in `extensions.md`:
  view factories are scoped to trusted, compiled-in extensions only; any
  process boundary carries declarative data messages and rendering ownership,
  never view objects.

## Lifecycle

Tier A lifecycle is implemented now:

- `ExtensionHost` reconciles desired enabled state (`ExtensionManager`) against
  live instances: `registered → activating → active → deactivating → inactive`,
  with `failed` on activation error.
- Activation failure deactivates the instance, cancels its teardown bag, and
  records `failed`.
- Cancellation is centralized in `ExtensionCancellationBag` (tasks, timers,
  observers, custom teardown).
- Rapid/repeated enable/disable is coalesced with per-extension generation
  counters, so no duplicate services and no stale callbacks.
- Metadata listing reads `ExtensionMetadata` only; it never instantiates a
  service.

A Tier B adapter would map the same phases onto `AppExtensionProcess`
(`invalidate`, `onInterruption`) and `EXHostViewControllerDelegate`
(`hostViewControllerDidActivate` / `hostViewControllerWillDeactivate`), keeping
`ExtensionHost` as the core-facing surface.

## Bundled helper vs independently installed

- An ExtensionKit app extension normally **ships inside a host app bundle**; a
  separately installed extension lives in another app and is **disabled by
  default** until the user enables it.
- A bundled XPC/helper demo does **not** prove independent installation. The
  prototype must demonstrate discovery and enablement of an artifact that is
  not embedded in the host bundle before any independent-installation claim.
- No API reports install location, so evidence must come from observed system
  behaviour (enable/disable defaults, `EXAppExtensionBrowserViewController`),
  not from a host query.

## Gating

- The bounded macOS 26 prototype supplied the required feasibility evidence for
  independent installation, system consent, remote SwiftUI, process isolation,
  crash containment, reconnection, disablement, and uninstall. See
  [`native-extension-runtime-phase-1.md`](../native-extension-runtime-phase-1.md).
- Phase 2 contains an availability-gated Tier B adapter, hardened local package
  ingestion, and a same-Team update rule. ADR 0003 allows any non-ad-hoc,
  Apple-anchored signer and does not require notarization for local-developer
  packages.
- Shipping remains gated on Phase 2 live verification, including real signer
  results, managed-location sandbox behavior, integrated system/app enablement,
  install/update/uninstall, runtime teardown/recovery, and macOS 14 regression.
- Catalog distribution still requires a separate publisher, notarization,
  revocation, and update policy; local policy must not be generalized to it.
- Tier B/C must not add network calls, downloads, or `ExtensionFoundation`/
  `ExtensionKit` execution to macOS 14 paths.

## Consequences

- Tier A continues to reject out-of-process artifact kinds at compile-time
  registration. The separate Phase 2 local adapter accepts schema-v2
  `app-extension` packages only; `xpc-service` remains unsupported.
- The adapter is additive: it repopulates the same registry from an
  out-of-process source rather than replacing the runtime.
- Hand-authoring `.appexpt` is required for any macOS 14 ExtensionKit path; this
  is a real cost that the prototype must weigh against an isolated XPC design.
- The selected Tier B direction is a macOS 26+ ExtensionKit remote-scene adapter;
  Phase 2 also supports host-rendered declarative data. No macOS 14 ExtensionKit
  path is required.
- See
  [`0003-local-developer-package-install-policy.md`](0003-local-developer-package-install-policy.md)
  and [`../native-extension-runtime-phase-2.md`](../native-extension-runtime-phase-2.md)
  for local policy, implementation boundaries, and unpassed live gates.
