# NotchKit Extensions Architecture

Status: Phase 1 (compile-time first-party extensions)
Applies to: macOS 14 deployment target

## Purpose

NotchKit replaces hard-coded rendering and routing seams with a compile-time,
first-party extension architecture. Extensions declare UI/content and settings
destinations. Core keeps ownership of everything privileged or structural.

This document describes the Phase 1 architecture, extended by the runtime
lifecycle. For the contract-by-contract shape of the public API, see
[`extension-api.md`](extension-api.md). For the reasoning behind compile-time
extensions, see
[`adr/0001-compile-time-extensions-before-runtime-loading.md`](adr/0001-compile-time-extensions-before-runtime-loading.md).
For the separation of compile-time, out-of-process, and catalog tiers, see
[`adr/0002-extension-distribution-tiers.md`](adr/0002-extension-distribution-tiers.md).

## Repository boundaries

The repository is organised into three top-level areas. Only the first is built
and shipped today; the other two are scaffolding for declared future work.

| Top-level path | Contains | Status |
| --- | --- | --- |
| `NotchKit/` | macOS host application, core runtime, XPC helper, local Swift package (SDK + runtime), Configuration, mediaremote-adapter, updater | Implemented (Phase 1) |
| `NotchAPI/` | Future server for the extension catalog, distribution, submissions, and validation status | Proposed; no code, no network calls |
| `NotchExtensions/` | Extension source, examples, manifests, and validation tooling | Proposed; docs and stubs only |

The host application lives under `NotchKit/` and links the local Swift package
at `NotchKit/Packages/NotchExtensionSDK`. Nothing under `NotchAPI/` or
`NotchExtensions/` is compiled into the macOS app, and Phase 1 makes no network,
catalog, distribution, or installation calls. See [Non-goals](#non-goals).

### Implementation status

- Implemented and unit-tested: `NotchExtensionSDK` contracts (metadata, version
  ranges, entry points, definition/instance, host services, cancellation,
  compatibility), the `NotchExtensionRuntime` registry/manager/contribution
  store/lifecycle host/per-display router/closed-notch selection, and the pure
  identity-migration transforms. 100 package tests pass.
- Implemented and build-verified: the macOS host, project/product/scheme rename
  to NotchKit, the `com.notchkit.*` identity namespace, per-display routing, the
  disabled upstream updater UI, and a separate `NotchKitCoreOnly` app target
  that is genuinely Battery-free.
- Proposed: the `NotchAPI/` server, `NotchExtensions/` tooling, out-of-process
  extension loading, distribution, and signing. See ADR 0002 for the gating.

## Module boundaries

| Module | Kind | Responsibility |
| --- | --- | --- |
| `NotchKit` | Application host + core renderer/runtime | Owns geometry, windowing, animation, permissions, persistence, privileged system actions, and the SwiftUI rendering of the notch. Links `NotchExtensionSDK` and `NotchExtensionRuntime`. |
| `NotchExtensionSDK` | Public library (`NotchKit/Packages/NotchExtensionSDK`) | UI-facing contracts only. Defines descriptors, destinations, closed-notch contributions, regions, and the render snapshot. Must never import app internals such as `BoringViewModel`, singleton managers, or private window types. |
| `NotchExtensionRuntime` | Library (`NotchKit/Packages/NotchExtensionSDK`) | First-party catalog and registration boundary plus runtime infrastructure (`ExtensionRegistry`, `ExtensionManager`, `ExtensionHost`, `ContributionStore`, `PresentationCoordinator`, `NotchRouter`, `ClosedNotchSelection`, `IdentityMigration`). Depends only on `NotchExtensionSDK`. |

Phase 1 does **not** move all existing features into `NotchExtensionRuntime`. The
module establishes the boundary; migration is incremental.

## Public API policy

`NotchExtensionSDK` is semantic-versioned.

- The current API version is `1.0.0`.
- Compatibility is determined by **major** version. A descriptor whose major
  version differs from the running core is rejected by `ExtensionRegistry`.
- Additive changes bump the minor version. Breaking changes bump the major
  version and require a migration note here.
- Every public symbol must be documented. Phase 1 keeps the surface deliberately
  small and avoids unrestricted hooks.

## Extension identity

Extension identity is a stable reverse-DNS string, for example
`com.notchkit.home`. Identities are validated at registration time:

- at least three dot-separated components,
- each component non-empty and restricted to ASCII letters, digits, and hyphens,
- no leading/trailing hyphen.

Identities are stable across releases. Renaming an identity is a breaking change
because it is the key for enabled state and settings routing.

## Core ownership

Core exclusively owns:

- notch geometry and size computation,
- window creation, placement, ordering, and SkyLight handling,
- animation and interaction timing,
- permissions and privileged system actions (accessibility, XPC helper, media
  key interception),
- persistence and defaults,
- global event monitors.

Extensions must not manipulate the notch window or install global monitors
directly. Extensions declare; core acts.

## What extensions may contribute

- `NotchOpenDestination`: an open-notch tab, identified by a stable id, with
  title/icon metadata, ordering, availability, and a view factory.
- `ClosedNotchContribution`: declared region, priority, stable tie-breaker,
  availability, and a content factory.
- `ExtensionSettingsDestination`: a settings page reachable from the Extensions
  hub.
- `ExtensionDescriptor` was replaced by `ExtensionMetadata` (metadata-only) plus
  `ExtensionDefinition` (metadata + instance factory). Content is produced by an
  activated `NotchExtension` instance, so metadata listing never instantiates a
  feature service.

There is no unrestricted "run arbitrary code on every event" hook.

## Deterministic closed-notch selection

Closed-notch content is selected per region (`leading`, `exclusion`, `trailing`)
using a single deterministic ordering:

1. **Region** — contributions only compete inside their declared region.
2. **Priority** — higher priority wins.
3. **Recency** — the most recently activated contribution wins among equal
   priorities.
4. **Tie-breaker** — a stable string, ascending, guarantees determinism for
   equal priority and recency.
5. **Identity** — the contribution id, ascending, is the final guarantee.

Selection only considers contributions whose `isAvailable` predicate is true for
the current `ClosedNotchRenderSnapshot`. Libraries that are disabled by
`ExtensionManager` are removed before selection.

Phase 1 registers the existing closed-state content (battery notification,
inline HUD, music live activity, idle face) as contributions in the same region.
Their relative order reproduces the previous `if`/`else` chain exactly.

## Disablement contract

Disabling an extension must prevent all of its observable effects, not merely
hide a tab. For a disabled extension, core must suppress:

- contributed open destinations,
- contributed closed-notch content,
- contributed settings destinations,
- observers and event handlers owned by the extension,
- feature-triggered auto-opening (for example drag-to-open flows).

Phase 1 wires the registry, manager, router, and closed-notch selection to honor
this contract for declared content. Shelf drag/observer triggers are not yet all
routed through `ExtensionManager`; Shelf is therefore **not** claimed to be
independently disable-safe until the Phase 2 migration completes.

## Non-goals

Phase 1 explicitly excludes:

- a marketplace,
- any backend or network calls,
- remote manifests,
- package download or installation,
- arbitrary dynamic binary loading,
- code signing or notarization of extensions,
- Apple `ExtensionFoundation` / `ExtensionKit`.

## Future adapter path

A later phase may back the same contracts with an out-of-process adapter. ADR
0002 separates three tiers (compile-time modules, independently distributed
artifacts, and catalog/installation services) and records what macOS 14
actually supports. In particular:

- **SwiftUI view factories cannot cross a process boundary.** The previous
  wording here ("marshal descriptors and view/content factories across a
  process boundary") was incorrect. View factories are scoped to trusted,
  compiled-in extensions only.
- Any process boundary carries **declarative data messages** and explicit
  rendering ownership. An ExtensionKit adapter would present an opaque remote
  scene via `EXHostViewController`; an XPC adapter would use a defined
  `NSXPCConnection`/XPC message contract.
- `AppExtensionPoint` and programmatic `.appext` generation are macOS 26+, not
  macOS 14; a macOS 14 ExtensionKit path would need a hand-authored `.appext`.
- A **bundled helper is not an independently installed extension.** Separate
  installation is only claimed once a prototype demonstrates discovery and
  enablement of an artifact outside the host bundle.

The production app stays on the in-process first-party runtime until that
prototype provides evidence. `NotchExtensionSDK` and `NotchExtensionRuntime`
are designed so an adapter is additive rather than a rewrite.

## Non-negotiable invariants

- No visual redesign in Phase 1.
- No network calls or backend.
- No placeholder marketplace data.
- No `ExtensionFoundation` / `ExtensionKit` dependency.
- Core keeps ownership of geometry, windows, privileges, persistence, and
  animation.
