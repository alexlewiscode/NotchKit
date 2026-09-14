# NotchKit Extensions Architecture

Status: Phase 1 (compile-time first-party extensions)
Applies to: macOS 14 deployment target

## Purpose

NotchKit replaces hard-coded rendering and routing seams with a compile-time,
first-party extension architecture. Extensions declare UI/content and settings
destinations. Core keeps ownership of everything privileged or structural.

This document describes the Phase 1 architecture. For the contract-by-contract
shape of the public API, see [`extension-api.md`](extension-api.md). For the
reasoning behind compile-time extensions, see
[`adr/0001-compile-time-extensions-before-runtime-loading.md`](adr/0001-compile-time-extensions-before-runtime-loading.md).

## Module boundaries

| Module | Kind | Responsibility |
| --- | --- | --- |
| `NotchKit` | Application host + core renderer/runtime | Owns geometry, windowing, animation, permissions, persistence, privileged system actions, and the SwiftUI rendering of the notch. Links `NotchExtensionSDK` and `NotchExtensionRuntime`. |
| `NotchExtensionSDK` | Public library (`NotchKit/Packages/NotchExtensionSDK`) | UI-facing contracts only. Defines descriptors, destinations, closed-notch contributions, regions, and the render snapshot. Must never import app internals such as `BoringViewModel`, singleton managers, or private window types. |
| `NotchExtensionRuntime` | Library (`NotchKit/Packages/NotchExtensionSDK`) | First-party catalog and registration boundary plus extension runtime infrastructure (`ExtensionRegistry`, `ExtensionManager`, `NotchRouter`, `ClosedNotchSelection`). Depends only on `NotchExtensionSDK`. |

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
`com.boringnotch.home`. Identities are validated at registration time:

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
- `ExtensionDescriptor`: identity, display metadata, API version, first-party
  source, capabilities, default enabled state, and the contributions above.

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

A later phase may back the same contracts with an Apple `ExtensionFoundation`
(or XPC) adapter. That adapter would:

- discover externally packaged extensions,
- marshal descriptors and view/content factories across a process boundary,
- keep `ExtensionRegistry`/`ExtensionManager`/`NotchRouter` as the core-facing
  surface.

The current macOS 14 app must not depend on `ExtensionFoundation` or
`ExtensionKit`. `NotchExtensionSDK` and `NotchExtensionRuntime` are designed so an adapter is
additive rather than a rewrite.

## Non-negotiable invariants

- No visual redesign in Phase 1.
- No network calls or backend.
- No placeholder marketplace data.
- No `ExtensionFoundation` / `ExtensionKit` dependency.
- Core keeps ownership of geometry, windows, privileges, persistence, and
  animation.
