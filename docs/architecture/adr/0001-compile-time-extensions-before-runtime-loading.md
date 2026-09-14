# ADR 0001: Compile-time extensions before runtime loading

- Status: Accepted
- Date: 2026-09-14
- Context: NotchKit is a fork of boring.notch targeting macOS 14.

## Context

The app currently hard-codes its notch rendering and routing:

- `BoringViewCoordinator.currentView` is a fixed `NotchViews { home, shelf }`
  enum and `ContentView` switches over it directly.
- Which closed-notch content is visible is a scattered `if`/`else if` chain
  (battery notification, inline HUD, music live activity, idle face) with a
  parallel width calculation in `computedChinWidth`.

This makes adding or disabling a feature a cross-cutting change, and there is no
stable boundary a future extension could target. We need a seam that is safe on
the current deployment target and small enough to review.

## Decision

Introduce a **compile-time, first-party extension architecture** before any
runtime loading mechanism:

1. New modules: `NotchExtensionSDK` (public contracts) and `NotchExtensionRuntime`
   (catalog/registration and runtime infrastructure).
2. Built-in features are registered as descriptors through the catalog.
3. Open-notch routing uses stable destination ids via `NotchRouter`.
4. Closed-notch content uses declared contributions and deterministic selection
   via `ClosedNotchSelection`.
5. No dynamic code loading, no marketplace, no backend, no
   `ExtensionFoundation`/`ExtensionKit` dependency in this phase.

## Rationale

- **Safety on macOS 14.** No dependency on newer Apple extension frameworks, and
  no arbitrary code execution surface.
- **Incremental migration.** The boundary exists before features move, so each
  later migration (Shelf, Calendar, HUD, Battery, Media, Camera Mirror) is
  independently reviewable.
- **Deterministic behaviour.** Priority, recency, and stable tie-breakers replace
  ordering that depends on source position.
- **Testability.** `NotchExtensionSDK`/`NotchExtensionRuntime` are a local Swift package with a
  unit-test target; selection, registry, manager, and router can be tested
  without launching the app.

## Consequences

- During migration, some behaviour (for example all Shelf drag triggers) is not
  yet fully routed through `ExtensionManager`. Disablement is therefore only
  claimed for declared content until the relevant feature migration lands.
- `NotchExtensionSDK` must stay free of app internals, which requires small adapter types
  in the app host.
- A future runtime adapter is additive: it would populate the same registry from
  an out-of-process source rather than replace the core runtime.

## Alternatives considered

- **Adopt `ExtensionFoundation`/`ExtensionKit` now.** Rejected: not acceptable
  for the macOS 14 target as a hard dependency, and it would introduce a
  packaging/signing story before the internal boundary exists.
- **Plugin bundles loaded dynamically.** Rejected for this phase: arbitrary
  binary loading and signature verification are out of scope and expand the
  security surface.
- **Keep hard-coded features and add a thin registry later.** Rejected: the
  scattered rendering/routing seams are the problem, and deferring the boundary
  makes each future migration larger.
