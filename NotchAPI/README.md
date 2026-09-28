# NotchAPI

Status: implemented in the sibling `notchkit-hub` repository. This directory
documents the app-side Tier C boundary; it is not a server build target.

`NotchAPI` is the future server-side boundary for the extension ecosystem:

- extension catalog and metadata,
- distribution and download endpoints,
- extension submission and review workflow,
- validation status for submitted extensions.

## Expected catalog / download metadata

A future catalog entry is expected to carry at least:

- `id`, `displayName`, `summary`, `iconSystemName`;
- `extensionVersion`, `apiVersion`;
- `minimumHostVersion`, `maximumHostVersion` (or an equivalent range);
- `supportedSDKVersions`;
- `capabilities`, `artifactKind` (only `compiled-in` runs today);
- `entryPoints` (see the canonical schema in
  `NotchExtensions/manifests/manifest.schema.json`);
- artifact `url`, `sha256`, `size`, `signature`, `notarizationStatus`;
- `validationStatus` and `submissionState`.

The app consumes only a pinned-key, signed catalog envelope on macOS 26 or
later. It verifies the exact signed payload before interpreting catalog data,
then independently verifies downloaded artifact bytes and package code before
installation. Unsigned HTTP metadata and a manifest declaration alone are not
marketplace trust evidence.

See `docs/architecture/adr/0002-extension-distribution-tiers.md` for the tier
separation and macOS 14 platform constraints.

## Boundary rules

- Nothing in this directory is compiled into the macOS app. The app-side Hub
  adapter lives under `ExtensionHost/Marketplace` and is created without making
  a request; it fetches only after a macOS-26 user explicitly opens Discover.
- The app-facing contracts live in the Swift `NotchExtensionSDK` module
  (`NotchKit/Packages/NotchExtensionSDK/Sources/NotchExtensionSDK`). A future
  server must translate to and from that contract rather than inventing a
  parallel one.
- The top-level `NotchAPI/` name is reserved for this server. The former Swift
  module of the same name was renamed to `NotchExtensionSDK`.
- Statically linked, compile-time extensions are **not** downloadable artifacts.
  Distribution only becomes meaningful once a runtime adapter exists (see
  `docs/architecture/extensions.md`, "Future adapter path").
- The Hub server implementation lives at
  `/Users/alexanderlewis/Documents/Code/notchkit-hub`. Its contracts must remain
  aligned with the canonical SDK manifest and ADR 0004.

See `docs/architecture/extensions.md` for the repository boundary map,
`docs/architecture/extension-api.md` for the current public contract, and
`docs/architecture/identity-migration.md` for the `com.notchkit.*` namespace.
