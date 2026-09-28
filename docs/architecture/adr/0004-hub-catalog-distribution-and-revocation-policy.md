# ADR 0004: Hub catalog distribution and revocation policy

## Status

Accepted for Phase 3 implementation.

## Context

Phase 2 accepts a deliberately local, user-selected developer package. Its
Apple-anchored signer policy is not a catalog endorsement and cannot authorize
network distribution. The Hub introduces a distinct Tier C distribution path.

## Decision

- Hub packages declare `metadata.source: marketplace`; local packages declare
  `localDeveloper`. The manifest declaration is validated against the chosen
  installation context but never establishes trust by itself.
- A Hub release is eligible only when a pinned-key, signed catalog record binds
  its immutable release ID, extension identity/version, archive SHA-256, size,
  manifest SHA-256, publisher Team ID, and compatibility metadata.
- Hub publication requires valid Apple-anchored provider and nested extension
  signatures with matching Team IDs, automated package checks, and explicit
  reviewer approval of the immutable artifact hash. Apple Development signers
  may be published without notarization or stapling after review. Ad-hoc and
  unsigned code remains ineligible for installation.
- Signed catalog releases carry separate signer and review badges. `NotchKit
  Team` is derived from the configured first-party Team ID, `Apple Developer`
  from measured Developer ID certificate evidence, and `Reviewed Safe` from the
  review decision. Signer badges are provenance, not safety endorsements.
- Unreviewed submissions remain private to publishers and reviewers. Only
  reviewer-approved releases appear in the installable signed catalog.
- The host verifies catalog/download metadata, streams and hashes the archive,
  then runs the existing archive, layout, embedded-manifest, code-signature,
  installed-copy, and transaction checks.
- Installation records persist the verified Hub receipt. A local record never
  becomes marketplace-trusted merely because its identity appears in a catalog.
- Published artifact bytes are immutable and content-addressed. Catalog listings
  use stable Hub release paths; short-lived object-store URLs are requested only
  when a client begins a download.
- Revocation is independent of installation, user desired enablement, and macOS
  authority. A verified revocation blocks install, update, and rollback and
  tears down published runtime contributions without deleting evidence.
- Updates and manual rollback are explicit user actions. A rollback target must
  be retained or freshly downloaded, fully verified, compatible, and unrevoked.
- Hub networking, download, installation, and ExtensionKit execution are
  macOS-26-only. macOS 14 paths retain current Tier A behavior and issue no Hub
  network requests.

## Consequences

The Phase 2 local installer remains a reusable final validation layer but gains
an explicit Hub trust policy rather than accepting a URL as a local file. It
continues to enforce Apple-anchored signatures and same-team bundles; manual
review replaces notarization as the distribution approval gate. Hub and app
contracts must evolve together and be verified with shared fixtures.
