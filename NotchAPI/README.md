# NotchAPI

Status: proposed. This directory is scaffolding only. There is no server, no
build target, and no network code here.

`NotchAPI` is the future server-side boundary for the extension ecosystem:

- extension catalog and metadata,
- distribution and download endpoints,
- extension submission and review workflow,
- validation status for submitted extensions.

## Boundary rules

- Nothing in this directory is compiled into or called by the macOS app. The app
  makes no network calls.
- The app-facing contracts live in the Swift `NotchExtensionSDK` module
  (`NotchKit/Packages/NotchExtensionSDK/Sources/NotchExtensionSDK`). A future
  server must translate to and from that contract rather than inventing a
  parallel one.
- The top-level `NotchAPI/` name is reserved for this server. The former Swift
  module of the same name was renamed to `NotchExtensionSDK`.
- Statically linked, compile-time extensions are **not** downloadable artifacts.
  Distribution only becomes meaningful once a runtime adapter exists (see
  `docs/architecture/extensions.md`, "Future adapter path").
- No server implementation is in scope until a later phase explicitly approves
  it.

See `docs/architecture/extensions.md` for the repository boundary map,
`docs/architecture/extension-api.md` for the current public contract, and
`docs/architecture/identity-migration.md` for the `com.notchkit.*` namespace.
