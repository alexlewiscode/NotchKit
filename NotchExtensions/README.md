# NotchExtensions

Status: proposed. This directory holds manifests, examples, and validation
tooling for the extension ecosystem. None of it is compiled into the macOS app.

## Layout

| Path | Purpose | Status |
| --- | --- | --- |
| `manifests/` | Draft manifest schema and examples describing an extension | Proposed, non-functional |
| `validation/` | Future tooling to validate manifests and API compatibility | Proposed, non-functional |
| `examples/` | Example extension sources once a runtime adapter exists | Not started |

## Boundary rules

- Phase 1 extensions are compile-time, first-party Swift registered through
  `NotchExtensionRuntime` (host app) and the `NotchExtensionSDK` contracts. They
  are statically linked; they are not downloaded, installed, or loaded at
  runtime.
- The manifest schema here is a draft. It is not read by the app and must not be
  described as a working installation format.
- Validation tooling must not require an Apple `ExtensionFoundation` /
  `ExtensionKit` dependency in the macOS 14 app.
- The top-level `NotchExtensions/` name is reserved for this tooling. The former
  Swift module of the same name was renamed to `NotchExtensionRuntime`.
- No marketplace data, no backend, and no network calls in Phase 1.

See `docs/architecture/extensions.md`, `docs/architecture/extension-api.md`, and
`docs/architecture/identity-migration.md`.
