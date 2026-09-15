# NotchExtensionValidation

A self-contained Swift package that validates NotchKit extension **manifests**.
It is JSON-only: it never loads, links, or executes extension code, and it is
not built into or called by the macOS app.

| Item | Value |
| --- | --- |
| Package | `NotchExtensionValidation` (swift-tools-version 5.9) |
| Platform | macOS 14+ |
| Library | `ValidationCore` |
| Executable | `ext-validate` |
| SDK dependency | local package `../../NotchKit/Packages/NotchExtensionSDK` (product `NotchExtensionSDK`) |
| Canonical schema (read-only) | `../manifests/manifest.schema.json` |
| Reference example | `../examples/HelloExtension/manifest.json` |

Everything in this directory is tooling. The canonical contract remains the
JSON schema and the `NotchExtensionSDK.ExtensionMetadata`/`ExtensionCompatibility`
types; this package only enforces them.

## Commands

All commands run from `NotchExtensions/validation`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build
swift test
swift run ext-validate <path-to-manifest.json> [<path> ...] \
    [--host-version 1.0.0] [--sdk-version 1.0.0]
```

Examples:

```sh
# Validate the checked-in fixtures.
swift run ext-validate Fixtures/valid/hello-extension.json Fixtures/valid/battery.json
swift run ext-validate Fixtures/invalid/unsupported-host-version.json

# Validate against a non-default host/SDK.
swift run ext-validate manifest.json --host-version 2.1.0 --sdk-version 1.3.0

# Validate the canonical reference example.
swift run ext-validate ../examples/HelloExtension/manifest.json
```

## CLI output and exit codes

`ext-validate` prints **one line per issue**:

```
<ERR|WARN> <phase> <code>: <message> [<json-path>] (file: <manifest-path>)
<phase>  = structural | hostCompatibility
<code>   = a stable identifier from `ValidationCode`
```

Example lines:

```
ERR structural structural.unknown_key: Unknown top-level key 'bogusTopLevel'. [$.bogusTopLevel] (file: Fixtures/invalid/unknown-top-level-key.json)
ERR hostCompatibility compat.unsupported_host_version: Host version 1.0.0 is outside the required range >=2.0.0. (file: Fixtures/invalid/unsupported-host-version.json)
```

Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | No errors (warnings may have been printed) |
| `1` | At least one validation error |
| `2` | Usage error (unknown option, missing/invalid version argument, no paths) or I/O error (unreadable file) |

`ERR` issues drive exit code `1`. `WARN` issues never fail validation. If any
path cannot be read, `ext-validate` reports it, continues with the remaining
paths, and exits `2` (which takes precedence over `1`).

## Structural vs host compatibility

The validator runs two clearly separated phases and never mixes them.

### 1. Structural (strict decoding)

Mirrors the canonical schema: exact top-level key set, exact entry-point key
set, required fields, JSON types, and enum values. The `Codable` model silently
ignores unknown keys, so `ValidationCore` additionally does explicit
`JSONSerialization` key checks against the schema's allowed key sets.

Structural checks include:

- unknown top-level keys, unknown entry-point keys;
- missing required fields and wrong JSON types;
- invalid reverse-DNS identity, semantic version, or version-range strings;
- invalid `capability`, `artifactKind`, `entryPoint.kind`, and `source` values;
- duplicate `capabilities` array entries and duplicate entry-point ids;
- entry-point `metadata` not being a string-to-string object;
- `sceneName` present on a `compiled-in` extension.

If **any** structural issue is found, validation stops there. Host
compatibility is not evaluated, so a manifest that cannot be decoded never
produces misleading compatibility errors.

### 2. Host compatibility

Only runs when structure is sound. The decoded `ExtensionMetadata` is validated
with `NotchExtensionSDK.ExtensionCompatibility.validate(_:hostVersion:sdkVersion:)`
and each thrown `ExtensionCompatibilityError` is mapped to a stable code:

| SDK error | Code |
| --- | --- |
| `unsupportedArtifactKind` | `compat.unsupported_artifact_kind` |
| `unsupportedHostVersion` | `compat.unsupported_host_version` |
| `unsupportedSDKVersion` | `compat.unsupported_sdk_version` |
| `undeclaredCapability` | `compat.undeclared_capability` |
| `capabilityWithoutEntryPoint` | `compat.capability_without_entry_point` |
| `duplicateEntryPoint` | `compat.duplicate_entry_point` |

`ExtensionCompatibility.validate` throws on the first failure, so at most one
host-compatibility issue is reported per manifest.

### `$schema` allowance

`../examples/HelloExtension/manifest.json` carries a top-level
`"$schema"` annotation. The canonical schema's `additionalProperties: false`
does not list `$schema`, but it is the standard JSON-Schema self-description
key, so `ValidationCore` accepts it as an explicit, documented exception.
Every other unknown top-level key is rejected. This is the only intentional
widening of the schema's key set.

## API

```swift
public enum ValidationSeverity { case error, warning }
public enum ValidationPhase { case structural, hostCompatibility }

public struct ValidationIssue: Equatable, Sendable {
    public let severity: ValidationSeverity
    public let phase: ValidationPhase
    public let code: String
    public let message: String
    public let path: String?
}

public enum ManifestValidator {
    public static func validate(
        data: Data,
        hostVersion: ExtensionVersion,
        sdkVersion: ExtensionAPIVersion
    ) -> [ValidationIssue]
}
```

## Fixtures

- `Fixtures/valid/` — `hello-extension.json` (HelloExtension shape) and
  `battery.json` (closed-notch-contribution + settings-destination,
  `compiled-in`).
- `Fixtures/invalid/` — one fixture per failure mode, covering both phases.

`ValidationCoreTests` asserts phase, code, and severity for every invalid
fixture, asserts zero issues for the valid fixtures, and asserts that a
structural failure suppresses host-compatibility output. Tests locate fixtures
via `#filePath`, so they pass from any working directory.

## Security disclaimer

**Passing these checks is not a security review and is not approval of any
extension.** `ext-validate` only inspects manifest metadata as JSON. It does
not inspect, sandbox, sign, verify, or execute extension code, and it makes no
statement about an artifact's trustworthiness or behavior. A manifest that
passes is merely well-formed and compatible with the requested host/SDK
versions. Runtime, code, and distribution trust remain separate, out-of-scope
concerns.
