# ADR 0003: Local developer package and installation policy

- Status: Accepted for Phase 2 implementation; live runtime verification ongoing
- Date: 2026-09-19

## Context

ADR 0002 selected a macOS 26+ ExtensionKit adapter for Tier B and left package,
publisher, and update policy as gates. Phase 2 adds a deliberately local-only
installation path. It is not a catalog trust policy and does not imply that a
package is reviewed, notarized, or endorsed by NotchKit.

The package contains executable code. Installation therefore has to bind the
bytes reviewed by the user to signed code, constrain extraction and placement,
and keep NotchKit preference state separate from macOS ExtensionKit authority.

## Decision

### Package envelope

- The transport is a ZIP archive with the `.notchkitextension` suffix.
- Extraction is preflighted and bounded by entry count, path length/depth,
  compressed size, expanded size, and per-entry expansion ratio.
- Absolute paths, traversal components, backslashes, NULs, home-relative paths,
  drive-like paths, duplicate normalized paths, encryption, symlinks, special
  entries, and unsupported compression methods are rejected.
- The extracted root contains exactly `manifest.json` and `payload/`; `payload/`
  contains exactly one provider `.app`, with exactly the declared nested
  `.appex`.
- `manifest.json` is schema version 2 and conforms to
  `NotchExtensions/Schemas/extension-manifest-v2.schema.json` plus the SDK's
  cross-field validator.

### Signed manifest and identity

- The provider embeds a second manifest at
  `Contents/Resources/NotchKitExtension/manifest.json`.
- The outer and embedded manifests must be byte-for-byte equal. Semantic JSON
  equivalence is insufficient. Because the embedded copy is sealed by the
  provider signature, this binds the package declaration to the signed app.
- Provider and nested extension bundle identifiers, extension point, versions,
  package identity, and package layout must agree with the manifest.
- The package identity is independent of the nested extension bundle identifier.

### Local signer policy

- Every executable bundle is strictly signature-validated for all architectures.
- The provider and nested extension must be signed by an Apple-anchored signer
  that supplies a non-empty Team ID and designated requirement.
- Ad-hoc and unsigned code are rejected.
- Any Apple-anchored development or distribution signer is eligible for this
  local-developer tier; there is no publisher allow-list.
- An update for an installed package identity must retain the original Team ID.
  A Team ID change is a different trust decision and is rejected as an update.
- Local installation does not require notarization. This exception does not set
  catalog or general-distribution policy and does not bypass system Gatekeeper
  behavior outside NotchKit.

### Managed location and sandbox gate

- Accepted packages are transactionally copied to the NotchKit-managed
  Application Support root at
  `~/Library/Application Support/NotchKit/LocalExtensions`. Execution and
  uninstall use only the recorded identity-derived relative path beneath that
  root.
- Before the first install, the user explicitly selects that exact directory in
  an `NSOpenPanel`. NotchKit rejects any other selection, persists an app-scoped
  security-scoped bookmark, validates it against the fixed root on restoration,
  and holds scoped access for the coordinator lifetime.
- The sandboxed host uses the user-selected executable entitlement so executable
  providers copied under that consent are not marked as having been created
  without user consent. Selecting a package archive does not grant authority to
  change the managed destination.
- Staging is private and temporary. A moved install is revalidated before
  registration, and failed replacement attempts restore the prior package when
  possible.
- Records that point outside the managed root are never executed or removed.
- The signed coordinator integration test has proved copy, validation,
  registration/launch, and removal from this location in the sandboxed host.
  Discovery, approval, rendering, updates, and clean-account product UI remain
  separate live gates.

### Records and authority

- The installed-extension record is authoritative for what NotchKit installed:
  identity, version, managed path, manifest digest, declarations, signer Team ID,
  designated requirements, timestamps, and desired-enabled state.
- Records are independent of ExtensionKit discovery. A record remains present
  when the system identity is disabled, awaiting approval, absent, or discovery
  is temporarily unavailable. Discovery never creates an installation record.
- System enablement/approval and NotchKit app enablement are separate gates. An
  extension contributes content only when it has a valid managed record, passes
  revalidation, is enabled in NotchKit, and is currently discovered as enabled
  by the system.
- NotchKit cannot infer system denial or approval from files, registration, or
  app preference state. Unknown remains unknown until system authority supplies
  evidence; system browser UI owns user approval.

### Host actions

- Host actions are a manifest allow-list, not ambient authority.
- The extension may request an allow-listed host action only in the response to
  a host-initiated user interaction. Unsolicited extension-to-host action
  requests are rejected.
- Wire identity, request correlation, entry-point identity, and declared-action
  checks precede execution. Core remains the sole owner of host effects.

### Platform boundary

- The native adapter is availability-gated to macOS 26 and newer.
- The app's macOS 14 deployment target and Tier A compile-time runtime remain
  unchanged. Phase 2 must not introduce ExtensionKit execution into macOS 14
  paths.

## Consequences

- Local development can use Apple Development or other Apple-anchored signing
  without requiring a Developer ID/notarization release pipeline.
- The same-Team update rule prevents silent publisher replacement but does not
  provide revocation, reputation, or marketplace review.
- The package schema validates serialized shape; relational rules such as entry
  point correspondence, bundle containment, version ordering, and paired sneak
  peek actions remain executable validator checks.
- Installation success is not activation success. The UI and lifecycle must
  represent installed, app-disabled, awaiting-system-approval, active,
  interrupted, and failed states without conflation.

## Verification status

The archive, manifest, layout, signature-policy boundary, transaction, record,
matching, wire, lifecycle, and user-gesture rules have implementation and test
coverage in the current worktree. On 2026-09-19, an Apple Development-signed
Pomodoro package passed preview, exact-folder authorization, transactional
install, workspace registration/launch, inventory validation, and uninstall in
the sandboxed signed test host. This closes the hard-quarantine managed-location
gate for that path. It does not establish the complete Security.framework signer
matrix, update/rollback behavior with real signed artifacts, clean-account
approval/discovery, rendering, or the complete product UI flow. The earlier
Phase 1 prototype evidence remains useful but is not evidence for this installer.
