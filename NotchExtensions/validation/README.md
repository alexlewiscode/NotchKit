# NotchExtensions validation (planned)

Status: schema and rules are canonical; tooling is **not implemented** in this
phase. Nothing here is compiled into or called by the macOS app.

## Canonical schema

`../manifests/manifest.schema.json` is the canonical manifest contract. It
mirrors the `Codable` shape of `NotchExtensionSDK.ExtensionMetadata`; the schema
and the Swift type are intended to change together.

## Checks a future validator must perform

1. **Schema**: JSON Schema validation against `manifest.schema.json`.
2. **Identity**: reverse-DNS format, matching the `ExtensionIdentity` rules.
3. **Artifact kind**: reject kinds the host cannot run. This host build supports
   only `compiled-in`. `app-extension` and `xpc-service` are reserved.
4. **Version ranges**:
   - the host version must satisfy `supportedHostVersions`;
   - the SDK version must satisfy `supportedSDKVersions`.
5. **Capability/entry-point consistency**: every entry point's kind must have a
   declared capability, and every declared capability must have at least one
   entry point of that kind.
6. **Entry-point uniqueness**: entry-point ids must be unique within a manifest.
7. **Reserved fields**: `sceneName` must be absent for `compiled-in`
   extensions.

These rules are implemented for the in-process contract by
`NotchExtensionSDK.ExtensionCompatibility` and covered by package tests. A
standalone validator is future work and must not introduce an
`ExtensionFoundation`/`ExtensionKit` dependency into the macOS 14 app.
