# Native extension runtime Phase 2 architecture

- Status: Implementation present; sandbox registration verified, remaining live gates ongoing
- Date: 2026-09-19
- Platform: macOS 26+ adapter in an app that retains a macOS 14 deployment target
- Policy: [ADR 0003](adr/0003-local-developer-package-install-policy.md)

## Scope

Phase 2 integrates local-developer packages into the production host boundary.
It covers strict package manifests, hardened local ZIP ingestion, transactional
managed installation, installation records, ExtensionKit discovery matching,
declarative and remote-scene sessions, lifecycle handling, and contribution
publication.

It does not add a catalog, network download, publisher review, revocation,
notarization requirement, automatic updates, or a macOS 14 ExtensionKit path.
Tier A compile-time extensions and their macOS 14 behavior remain unchanged.

## Modules

| Module or host area | Responsibility |
| --- | --- |
| `NotchExtensionSDK` | Schema-v2 package model, package validation rules, permissions, host-action declarations, declarative UI model |
| `NotchExtensionWire` | Bounded Codable-over-`Data` requests/responses, correlation, handshake/render/action validation |
| `NotchExtensionInstallation` | ZIP hardening, strict manifest decoding, extracted layout validation, code-signature evidence, records, transactional install/update/uninstall |
| `NotchNativeExtensionRuntime` | ExtensionKit identity matching, lifecycle, XPC transport, handshake, declarative sessions, bounded reconnect |
| Host `LocalExtensions` adapter | User-selected preview/install, managed inventory, system browser/monitor integration, dual enablement reconciliation, contribution/view adapters |
| Existing `NotchExtensionRuntime` | Shared manager, contribution store, routing, closed-notch selection; remains the core-facing boundary |

`NotchExtensionInstallation` does not discover extensions. Discovery does not
write install facts. The host coordinator joins those independent inputs.

## Package And Install Flow

1. Before the first install, the user grants the sandbox access to the exact
   fixed `~/Library/Application Support/NotchKit/LocalExtensions` directory.
   NotchKit persists a security-scoped bookmark and rejects another directory.
2. A user explicitly selects a `.notchkitextension` archive.
3. Preview extracts to ephemeral staging after central-directory hardening.
4. The strict v2 manifest, exact package layout, embedded manifest byte equality,
   plists, identifiers, versions, and declared extension point are validated.
5. Security.framework validates the provider and nested extension signatures,
   Apple anchor, non-ad-hoc status, Team IDs, and designated requirements.
6. The confirmation UI presents package identity, version, declarations, and
   signer Team ID. No discovery or activation is implied.
7. Installation repeats validation, enforces same-Team updates, moves the package
   transactionally into the managed root, and revalidates the installed copy.
8. The provider is registered/launched through the workspace service and the
   installation record is atomically persisted. Failure attempts rollback.
9. Uninstall accepts only the identity-derived managed path, unregisters the
   exact provider copy, removes it transactionally, and then removes the record.

## Discovery And Enablement Flow

1. On macOS 26+, the extension-point monitor reports system-visible identities.
2. Candidates come only from valid managed installation records and manifests.
3. Matching requires the declared extension bundle identifier and extension
   point identifier and rejects ambiguity.
4. The host maintains two independent controls: system authority/discovery and
   NotchKit's `desiredEnabled` preference.
5. Contributions are published only for a valid, app-enabled, system-discovered
   candidate. Losing either gate removes contributions and tears down sessions.
6. The ExtensionKit browser owns system approval and enablement. NotchKit must
   not label a non-discovered record as denied without system evidence.

## Session And Interaction Flow

1. Selecting/rendering an entry point creates a generation-scoped session.
2. Transport activation is followed by a bounded handshake validating protocol,
   extension identity, entry-point identity, and extension version.
3. A remote-scene descriptor is hosted opaquely with `EXHostViewController`.
   A declarative descriptor exchanges bounded render/action data and is rendered
   by the host.
4. Declarative actions originate from a host-rendered user interaction. Only an
   allow-listed host action returned to that request may reach the host handler.
   Unsolicited host-action messages are rejected.
5. Interruption invalidates the old transport and generation. At most one
   bounded reconnect is attempted before entering failure; disable/uninstall
   requests teardown and suppress stale callbacks.

## States

Installation and execution are separate state dimensions.

| Dimension | States |
| --- | --- |
| Local record | absent, installed, registration pending, registration failed |
| App preference | desired enabled, desired disabled |
| System authority | unknown, awaiting user approval, approved, denied |
| Discovery | unmatched, matched, ambiguous/error |
| Session | discovered, awaiting approval, disabled, connecting, handshaking, active, interrupted, failed, inactive |

An installed record may legitimately be app-disabled or not discovered. An
active session requires all prior gates but does not rewrite installation facts.

## Threat Model

| Threat | Control |
| --- | --- |
| ZIP traversal, bombs, links, device/special entries | Preflight limits, normalized-path rejection, encryption/link/type/method rejection |
| Manifest swapped outside signed code | Byte equality with manifest embedded in the signed provider |
| Undeclared or substituted bundle | Exact root/payload layout, one expected `.appex`, plist/manifest identity checks |
| Unsigned, ad-hoc, or unrelated nested code | Strict all-architecture validation, Apple anchor, Team ID, provider/nested same-team check |
| Publisher takeover during update | Installed package identity may update only with the recorded Team ID |
| Managed-path escape or destructive uninstall | Identity-derived relative paths, containment checks, exact provider-path handling |
| Sandbox hard-quarantines copied executable code | Exact-root user consent, app-scoped security-scoped bookmark, and user-selected executable entitlement |
| Discovery spoof or collision | Match record plus manifest to bundle and extension-point identifiers; reject ambiguity |
| Wire confusion or stale callback | Correlated requests, identity/version/entry-point checks, generations, timeout, bounded payload contracts |
| Ambient extension control of host | Declared host-action allow-list and host-initiated user-gesture requirement |
| Crash loop or orphaned UI | Interruption teardown, one bounded reconnect, failure state, contribution reconciliation |

Residual risks include any Apple-anchored local signer being accepted, no
publisher revocation/reputation service, possible framework/LaunchServices
behavior differences on clean systems, and defects below the ZIP or code-signing
APIs. Local packages remain executable third-party code despite process isolation.

## Gates

- JSON syntax and schema fixtures must validate against the draft 2020-12 schema
  and the executable cross-field validator.
- Installation unit tests must cover malformed archives, byte-mismatched embedded
  manifests, layout/identity/version disagreement, signer/team failures,
  same-Team replacement, rollback, records, and managed-path refusal.
- Runtime contract tests must cover matching, ambiguity, handshake/version
  rejection, timeout, interruption/reconnect suppression, declarative rendering,
  and host-action gesture/allow-list enforcement.
- A real signed-package matrix must exercise Apple Development, Developer ID (if
  available), ad-hoc rejection, broken signatures, mixed teams, and same/different
  Team ID updates through Security.framework rather than fakes.
- A clean macOS 26 GUI account must exercise preview, confirmation, install,
  system approval, discovery, both enablement gates, rendering, crash recovery,
  update, disable, and uninstall from the managed product location.
- The sandbox managed-location flow must pass with the product entitlements and
  without retaining broad access to the selected source archive.
- macOS 14 build and launch checks must show no changed Tier A behavior and no
  execution of ExtensionKit-only paths.

## Live Verification Status

On 2026-09-19, the sandboxed, Apple Development-signed test host used the
production coordinator to preview a signed Pomodoro package, obtain exact-root
consent through `NSOpenPanel`, install it transactionally, launch/register its
provider through `NSWorkspace`, validate the installed inventory, and uninstall
it. This verifies the security-scoped destination model and closes the prior hard
quarantine failure for the tested path.

The repository does not yet establish:

- successful update/rollback using real signed package artifacts or the complete
  install flow through the product settings UI;
- the full Apple-anchored signer matrix or same-Team update behavior with real
  Security.framework results;
- clean-account ExtensionKit approval, discovery, and enablement reconciliation
  after sandbox registration;
- byte-equality tamper rejection against a genuinely signed provider;
- live declarative rendering, user-gesture host actions, automatic reconnect,
  disable teardown, or uninstall teardown in the integrated host;
- regression verification on macOS 14.

The macOS 26 Phase 1 prototype did record independent install, system approval,
discovery, remote SwiftUI, process isolation, crash containment, relaunch,
disable/re-enable, and uninstall observations. Those results prove platform
feasibility only; they are not promoted to Phase 2 product evidence.
