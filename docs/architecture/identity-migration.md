# NotchKit identity migration

Status: implemented for the boringNotch → NotchKit transition. Applies to the
macOS 14 deployment target.

Changing the bundle identifier changes the sandbox container and the
`UserDefaults` domain, so persisted settings do not move automatically. This
document records the namespace, the one-time migration, and what users may need
to re-authorize.

## Identifier namespace

| Concern | boringNotch (legacy, read-only) | NotchKit (current) |
| --- | --- | --- |
| App bundle id | `theboringteam.boringnotch` | `com.notchkit.app` |
| XPC helper bundle id / Mach service | `theboringteam.boringnotch.BoringNotchXPCHelper` | `com.notchkit.app.XPCHelper` |
| Extension identity prefix | `com.boringnotch.` | `com.notchkit.` |
| Extension-state defaults key | `com.boringnotch.extensions.state` | `com.notchkit.extensions.state` |
| Shelf storage directory | `Application Support/boringNotch/Shelf` | `Application Support/NotchKit/Shelf` |
| Log/notification namespace | `com.boringNotch` | `com.notchkit` |

The current values live in `NotchKitIdentity`
(`NotchKit/Packages/NotchExtensionSDK/Sources/NotchExtensionSDK/NotchKitIdentity.swift`);
the legacy values are read-only constants used only by the migration.

## One-time migration

Implemented in:

- `NotchKit/NotchKit/Migration/IdentityMigrationCoordinator.swift` — orchestration.
- `NotchKit/NotchKit/Migration/LegacyIdentityArchiveReader.swift` — synchronous
  read via the non-sandboxed helper.
- `NotchKit/NotchKit/Migration/ShelfBookmarkVerifier.swift` — bookmark check.
- `NotchKit/NotchKit/Migration/LegacyImportFlow.swift` — user-authorized fallback.
- `NotchKitXPCHelper` — reads only known legacy app-owned paths.
- `IdentityMigration` (`NotchExtensionRuntime`) — pure, unit-tested transforms.
- `main.swift` — runs the migration before SwiftUI resolves persisted settings.

Guarantees:

- **Non-destructive.** Originals are never modified or deleted; values are only
  copied.
- **Never overwrites NotchKit data.** Existing defaults, extension state, and
  Shelf data are left untouched.
- **Retryable.** The completion marker
  (`Application Support/NotchKit/Migration/identity-v1.done`) is written only
  after validation succeeds. A partial or failed run is retried next launch.
- **No content logging.** Settings values and Shelf contents are never logged.
- **Bookmarks are verified, not assumed invalid.** Only bookmarks that fail to
  resolve are counted; resolving bookmarks are left as-is.
- **Explicit fallback.** If the helper cannot read the legacy container, an
  import prompt is shown so the user can select the old Shelf items file rather
  than losing data silently.

## Permissions users may need to grant again

Because TCC grants are keyed by bundle identifier, users upgrading from
boringNotch may need to re-authorize:

- Accessibility (used by the helper for media keys),
- Automation / Apple Events (Spotify, Music),
- Camera (mirror),
- Calendars,
- Screen Recording (if used),
- Files/Shelf access via security-scoped bookmarks.

Launch-at-login registration is also keyed by bundle identifier and may need to
be re-enabled.

## Tests

`NotchKit/Packages/NotchExtensionSDK/Tests/NotchExtensionRuntimeTests/IdentityMigrationTests.swift`
covers identifier rewriting, extension-state rewriting, defaults merging,
idempotency, and partial-failure behaviour. End-to-end container reads cannot be
exercised without a machine that has a pre-existing boringNotch container; that
remains a manual/GUI check.
