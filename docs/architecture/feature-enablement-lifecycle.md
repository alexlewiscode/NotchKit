# Feature Enablement & Lifecycle

This document is the ownership map and decision record for making the six
first-party feature master toggles truthful: Battery, Calendar & Reminders,
Shelf, Media, HUD, and Camera Mirror.

## Authoritative enablement

One master enabled state per feature lives in `ExtensionManager`, persisted in
`com.notchkit.extensions.state` (`ExtensionStateSnapshot`). The Extensions hub
reads it through `SettingsCatalog` entries whose `owner` is the feature's
`ExtensionIdentity`. The row toggle writes `ExtensionHost.setEnabled`, which
reconciles through the existing generation-guarded lifecycle:

| Phase | Meaning |
| --- | --- |
| `inactive` | Registered, not enabled. |
| `activating` | Activation in progress; toggle disabled. |
| `active` | Instance running; contributions live. |
| `deactivating` | Stopping; toggle disabled. |
| `failed(String)` | Activation threw; retryable. |
| `requiresPermission(String)` | Desired state on, permission gate unmet; not an error, not active, retried only by explicit user action. |

A feature's `activate()` can throw `ExtensionActivationError.permissionRequired`
to produce `requiresPermission` without being reported as active. `reconcileNow()`
never auto-retries that state; `ExtensionHost.retry(_:)` is the explicit path
(the row's Grant/Retry actions).

### Legacy preference mirroring

The master toggles supersede these legacy per-feature UI preferences:

| Feature | Legacy master | Migration seed (only if no authoritative value) |
| --- | --- | --- |
| Calendar & Reminders | `showCalendar` | `showCalendar` |
| Shelf | `boringShelf` | `boringShelf` |
| HUD | `hudReplacement` | `hudReplacement` |
| Camera Mirror | `showMirror` | `showMirror` |
| Media | (none) | default enabled |
| Battery | (extension state) | default value |

Migration is one-time and idempotent (`FeatureEnablementMigration`, marker
`didMigrateFeatureEnablement_v1`). It never deletes or resets legacy
subpreferences. For Calendar, HUD, and Camera it seeds only when no
authoritative value exists, so a saved choice is preserved. Shelf is the one
exception: it already had an authoritative value from the previous milestone
that came from its `defaultEnabled`, not from a user choice, while the
user-facing master was `boringShelf`; the legacy value therefore wins once.
The redundant master controls were removed from the detail pages, so
`showCalendar` / `showMirror` / `boringShelf` / `hudReplacement` remain in
storage only as migration inputs; core views gate on
`NotchKitRuntime.isFeatureEnabled`. Media's narrow `musicLiveActivityEnabled`
is a subpreference and is never treated as the Media master.

## Lifecycle ownership map

| Feature | Identity | Owned service | Start | Stop | Preserved on disable |
| --- | --- | --- | --- | --- | --- |
| Battery | `com.notchkit.battery` | `BatteryMonitor` (app-wide) | `BatteryExtension.activate` | `BatteryExtension.deactivate` | battery prefs |
| Calendar & Reminders | `com.notchkit.calendar` | `CalendarManager` | `CalendarFeature` → `start()` | `stop()` removes observers, cancels tasks, clears presented data | selection, filters |
| Shelf | `com.notchkit.shelf` | `QuickShareService` + host drag detectors | `ShelfExtension.activate` | `deactivate` stops discovery and disables detectors | `items.json`, bookmarks, sharing prefs |
| Media | `com.notchkit.media` | `MusicManager` | `MediaFeature` → `start()` | `stop()` releases controllers/observers | source, visualizer, playback prefs; external playback untouched |
| HUD | `com.notchkit.hud` | `MediaKeyInterceptor`, `VolumeManager`, `BrightnessManager`, `KeyboardBacklightManager` | `HUDFeature.activate` (requires accessibility) | `stop()` removes the event tap and CoreAudio listeners | volume/brightness display prefs |
| Camera Mirror | `com.notchkit.camera` | `WebcamManager` | `CameraFeature` → `start()` | `stop()` stops capture, removes device observers | device selection, mirror shape |

Home (`com.notchkit.home`) is required and has no toggle.

### Service construction is inert

Every feature service is now cheap to construct: `init` no longer registers
observers, starts timers, spawns controllers, or reads devices. The lifecycle
adapter is the only caller of `start()`/`stop()` in production. Core views may
still reference a singleton's published state, but that does not start it.
`TestHostPolicy` guards remain on every `start()`.

### Gating

Core renderers gate UI on the authoritative state via
`NotchKitRuntime.isFeatureEnabled`, not on legacy preferences:

- closed-notch music and inline HUD contributions use snapshot flags
  (`mediaEnabled`, `hudEnabled`);
- the open-notch music player, calendar, and camera preview gate on their
  feature;
- the camera header button and the Shelf tab strip gate on their feature;
- host drag detectors and the closed-notch drop surface gate on Shelf;
- non-music sneak peeks require HUD.

## Permissions

Opening any settings page is read-only and never prompts. HUD activation checks
accessibility without prompting; the row offers an explicit "Grant Access"
action. Camera activation starts only device monitoring; camera access is still
requested the first time the mirror opens. Shelf/Calendar requests remain
explicit buttons on their pages.

## Known limitations

- Battery's open-notch header indicator still reads the app-wide `BatteryMonitor`
  through `NotchKitRuntime`; disabling Battery correctly stops the monitor and
  hides the indicator because both gate on the same identity.
- `MenuBarExtra`, `NotchSpaceManager`, window geometry, and routing stay alive
  when every optional feature is off.
- A `.failed` extension is still re-attempted by `reconcileNow()` (pre-existing
  behavior); only `.requiresPermission` waits for explicit retry. No adapter
  currently throws `deviceUnavailable`, so this is latent.
- GUI interaction checks (clicking a row, toggling, VoiceOver) are covered by
  catalog-level tests and must still be confirmed interactively; see the handoff
  report. Row click and toggle separation are structurally guaranteed (a plain
  `Button` sibling to a `Toggle`, never nested).
