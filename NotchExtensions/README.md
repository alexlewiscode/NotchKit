# NotchExtensions

Status: Phase 1 first-party examples and validation tooling plus Phase 2 local
package/runtime implementation. The Phase 2 sandbox install, registration,
launch, inventory, and uninstall path has live coordinator-level verification;
remaining ExtensionKit and product UI gates are documented separately.

## Layout

| Path | Purpose | Status |
| --- | --- | --- |
| `manifests/manifest.schema.json` | **Canonical** manifest schema for a NotchKit extension | Canonical; mirrors `ExtensionMetadata` |
| `Schemas/extension-manifest-v2.schema.json` | Strict draft 2020-12 schema for local-developer `ExtensionPackageManifest` | Implemented; structural schema plus executable cross-field validation |
| `examples/HelloExtension/` | Reference compiled-in extension (source + manifest) | Example; compiled and tested in the package test target |
| `validation/` | Phase 1 metadata validator and fixtures | Implemented |
| `LocalRuntime/` | Package installation, records, ExtensionKit matching, XPC transport, and native lifecycle | Implemented with tests; signed sandbox install/register/uninstall verified |
| `FirstParty/Battery/` | Extracted first-party Battery extension package | Implemented Phase 1 package |

## Boundary rules

- Phase 1 extensions are compile-time, first-party Swift registered through
  `NotchExtensionRuntime` (host app) and the `NotchExtensionSDK` contracts. They
  are statically linked; they are not downloaded, installed, or loaded at
  runtime.
- Phase 2 accepts only user-selected local `.notchkitextension` ZIP packages
  whose v2 manifests declare `source: localDeveloper` and
  `artifactKind: app-extension`. This is not a marketplace or network download
  format.
- The v2 JSON Schema validates serialized structure. The SDK and installer also
  enforce relational rules, archive/layout constraints, embedded-manifest byte
  equality, and code-signature policy.
- Native execution is availability-gated to macOS 26+. The deployment target and
  compile-time Tier A path on macOS 14 are unchanged.
- Local packages require a non-ad-hoc Apple-anchored signer and matching Team IDs
  for provider/nested extension and updates. Local policy does not require
  notarization and is not a catalog trust decision.
- A managed installation record and ExtensionKit discovery are independent.
  System approval and NotchKit's enabled preference must both permit execution.
- The top-level `NotchExtensions/` name is reserved for this tooling. The former
  Swift module of the same name was renamed to `NotchExtensionRuntime`.
- No marketplace data, backend, or network calls are added by Phase 2.

See `docs/architecture/extensions.md`, `docs/architecture/extension-api.md`,
`docs/architecture/native-extension-runtime-phase-2.md`, and
`docs/architecture/adr/0003-local-developer-package-install-policy.md`.
