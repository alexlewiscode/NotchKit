# Settings migration plan: consolidate feature configuration under Extensions

Status: Approved design. Implementation owned by Agent C.
Base commit: `00a57505696225d42bbd66a051d4a93e0c6d9f56` (`development`).
Plan branch: `docs/settings-migration-plan`.
Applies to: macOS 14 deployment target.

This document is the implementation-ready brief for moving feature settings
under a single `Extensions` section of the NotchKit Settings window. It does
**not** claim that any feature other than Battery has been extracted to a
first-party extension. It changes **no persisted preference keys**.

## References and reconciliation status

- Agent A settings inventory: **available**. Committed at
  `46afd93910f20ec8e7a9e245ed301b87846f565f` on `docs/settings-inventory` as
  [`settings-inventory.md`](settings-inventory.md), based on development
  `00a57505696225d42bbd66a051d4a93e0c6d9f56` (the same base as this plan).
  Agent A's key-audit artifacts (`defined_keys.txt`, `used_keys.txt`) were also
  used for the preference-key reconciliation in
  [Appendix A](#appendix-a-key-audit-reconciliation). The earlier "not present
  in this checkout at drafting time" note is resolved: the inventory is now in
  this branch (Agent C incorporated both documentation commits).
  See [Reconciliation record](#reconciliation-record) for the resolved
  differences between the two documents.
- Integration report: external chat content. Its reported defects are used only
  as review leads (see [Review leads](#review-leads-from-the-integration-report)).
  This plan deliberately does not repair unrelated validator, migration, or CI
  issues.
- Current architecture: `docs/architecture/extensions.md`,
  `docs/architecture/extension-api.md`,
  `docs/architecture/first-party-battery-extraction.md`,
  `docs/architecture/calendar-migration-plan.md`.

## Scope

In scope:

- a six-section Settings sidebar: General, Appearance, Interaction, Extensions,
  Shortcuts, About;
- stable typed settings routes and feature detail routes;
- lifecycle-independent settings declaration and a host settings catalog;
- honest enable/disable controls;
- isolation of settings-page side effects from feature services and permission
  requests;
- shortcuts discoverability, accessibility, localization, window sizing;
- tests and documentation for the above.

Out of scope (do not broaden):

- extracting Calendar, Media, HUD, Shelf, or Camera Mirror into extensions;
- validator, identity-migration, or CI repairs;
- marketplace, download, install, uninstall, verification, or catalog services;
- changing preference keys, defaults, or stored values;
- persisted navigation migration (settings navigation is **not** persisted).

## 1. Design summary

1. `SettingsView`'s string `selectedTab` becomes a typed `SettingsSection`.
2. Each feature's configuration page is declared at definition/registration
   time, not at activation time, so it is available while the feature is
   disabled or failed.
3. A host-owned `SettingsCatalog` is the single authoritative source for the
   Extensions hub. It is rebuilt from the registry, so removed definitions
   leave no stale routes.
4. Only Battery exposes an enable/disable control. Home is a required host
   destination and is not user-toggleable. Shelf, Calendar & Reminders, Media,
   HUD, and Camera Mirror are configuration entries with no lifecycle toggle.
5. Settings pages never call `activate()` or create a `NotchExtension`
   instance. Permission **requests** are explicit user actions; permission
   **status reads** and configuration-data loads are allowed but must be
   scoped to the visible page and torn down when the page closes.
6. Retry re-runs failed activation via the existing `ExtensionHost.reconcileNow()`
   path; no runtime addition is required.

## 2. Final navigation and control mapping

The sidebar has exactly these sections: **General**, **Appearance**,
**Interaction**, **Extensions**, **Shortcuts**, **About**. `Advanced` is removed
after every control it owns is redistributed. The Extensions hub contains
exactly six feature configuration entries: Battery, Calendar & Reminders,
Shelf, Media, HUD, Camera Mirror.

| Control (visible label) | Preference key | Old location | Final location |
| --- | --- | --- | --- |
| Show menu bar icon | `menubarIcon` | General / System features | General |
| Launch at login | `LaunchAtLogin` (no key) | General / System features | General |
| Show on all displays | `showOnAllDisplays` | General / System features | General |
| Preferred display | coordinator `preferred_screen_uuid` | General / System features | General |
| Automatically switch displays | `automaticallySwitchDisplay` | General / System features | General |
| Quit app (toolbar) | none | General toolbar | General |
| Notch height on notch displays | `notchHeightMode` | General / Notch sizing | Appearance |
| Custom notch size (notch) | `notchHeight` | General / Notch sizing | Appearance |
| Notch height on non-notch displays | `nonNotchHeightMode` | General / Notch sizing | Appearance |
| Custom notch size (non-notch) | `nonNotchHeight` | General / Notch sizing | Appearance |
| Always show tabs | coordinator `alwaysShowTabs` | Appearance / General | Appearance |
| Show settings icon in notch | `settingsIconInNotch` | Appearance / General | Appearance |
| Accent color (system/custom) | `useCustomAccentColor`, `customAccentColorData` | Advanced / Accent color | Appearance |
| Enable window shadow | `enableShadow` | Advanced / Window Appearance | Appearance |
| Corner radius scaling | `cornerRadiusScaling` | Advanced / Window Appearance | Appearance |
| Hide title bar | `hideTitleBar` | Advanced / Window Behavior | Appearance |
| Show notch on lock screen | `showOnLockScreen` | Advanced / Window Behavior | Appearance |
| Hide from screen recording | `hideFromScreenRecording` | Advanced / Window Behavior | Appearance |
| App icon (disabled / "Coming soon") | none | Advanced / App icon | Appearance |
| Show cool face animation while inactive | `showNotHumanFace` | Appearance / Additional features | Appearance |
| Open notch on hover | `openNotchOnHover` | General / Notch behavior | Interaction |
| Enable haptic feedback | `enableHaptics` | General / Notch behavior | Interaction |
| Remember last tab | coordinator `openLastTabByDefault` | General / Notch behavior | Interaction |
| Hover delay | `minimumHoverDuration` | General / Notch behavior | Interaction |
| Enable gestures | `enableGestures` | General / Gesture control | Interaction |
| Close gesture | `closeGestureEnabled` | General / Gesture control | Interaction |
| Gesture sensitivity | `gestureSensitivity` | General / Gesture control | Interaction |
| Change media with horizontal gestures (disabled placeholder) | none | General / Gesture control | Interaction |
| Extend hover area | `extendHoverArea` | Advanced / Window Behavior | Interaction |
| Show battery indicator | `showBatteryIndicator` | Battery | Extensions → Battery |
| Show power status notifications | `showPowerStatusNotifications` | Battery | Extensions → Battery |
| Show battery percentage | `showBatteryPercentage` | Battery | Extensions → Battery |
| Show power status icons | `showPowerStatusIcons` | Battery | Extensions → Battery |
| Show calendar | `showCalendar` | Calendar | Extensions → Calendar & Reminders |
| Hide completed reminders | `hideCompletedReminders` | Calendar | Extensions → Calendar & Reminders |
| Hide all-day events | `hideAllDayEvents` | Calendar | Extensions → Calendar & Reminders |
| Auto-scroll to next event | `autoScrollToNextEvent` | Calendar | Extensions → Calendar & Reminders |
| Always show full event titles | `showFullEventTitles` | Calendar | Extensions → Calendar & Reminders |
| Calendar / reminder list selection | `calendarSelectionState` + per-item toggles | Calendar | Extensions → Calendar & Reminders |
| Show Shelf | `boringShelf` | Shelf / General | Extensions → Shelf |
| Open shelf by default if items are present | `openShelfByDefault` | Shelf / General | Extensions → Shelf |
| Expanded drag detection area | `expandedDragDetection` | Shelf / General | Extensions → Shelf |
| Copy items on drag | `copyOnDrag` | Shelf / General | Extensions → Shelf |
| Remove from shelf after dragging | `autoRemoveShelfItems` | Shelf / General | Extensions → Shelf |
| Quick Share Service | `quickShareProvider` | Shelf / Quick Share | Extensions → Shelf |
| Music Source | `mediaController` | Media / Media Source | Extensions → Media |
| Show music live activity | coordinator `musicLiveActivityEnabled` | Media / live activity | Extensions → Media |
| Show sneak peek on playback changes | `enableSneakPeek` | Media / live activity | Extensions → Media |
| Sneak Peek Style | `sneakPeekStyles` | Media / live activity | Extensions → Media |
| Media inactivity timeout | `waitInterval` | Media / live activity | Extensions → Media |
| Full screen behavior | `hideNotchOption` | Media / live activity | Extensions → Media |
| Media control slots | `musicControlSlots`, `musicControlSlotLimit` | Media / Media controls | Extensions → Media |
| Show lyrics below artist name | `enableLyrics` | Media / Media controls | Extensions → Media |
| Colored spectrogram | `coloredSpectrogram` | Appearance / Media | Extensions → Media |
| Player tinting | `playerColorTinting` | Appearance / Media | Extensions → Media |
| Enable blur effect behind album art | `lightingEffect` | Appearance / Media | Extensions → Media |
| Slider color | `sliderColor` | Appearance / Media | Extensions → Media |
| Use music visualizer spectrogram | `useMusicVisualizer` | Appearance / animation | Extensions → Media |
| Selected animation | `selectedVisualizer` | Appearance / animation | Extensions → Media |
| Custom visualizers (Lottie) | `customVisualizers` | Appearance / animation | Extensions → Media |
| Replace system HUD | `hudReplacement` | HUD | Extensions → HUD |
| Request Accessibility (explicit button) | none | HUD | Extensions → HUD |
| Option key behaviour | `optionKeyAction` | HUD | Extensions → HUD |
| Progress bar style | `enableGradient` | HUD | Extensions → HUD |
| Enable glowing effect | `systemEventIndicatorShadow` | HUD | Extensions → HUD |
| Tint progress bar with accent color | `systemEventIndicatorUseAccent` | HUD | Extensions → HUD |
| Show HUD in open notch | `showOpenNotchHUD` | HUD | Extensions → HUD |
| Show percentage (open) | `showOpenNotchHUDPercentage` | HUD | Extensions → HUD |
| HUD style | `inlineHUD` | HUD | Extensions → HUD |
| Show percentage (closed) | `showClosedNotchHUDPercentage` | HUD | Extensions → HUD |
| Enable boring mirror | `showMirror` | Appearance / Additional features | Extensions → Camera Mirror |
| Mirror shape | `mirrorShape` | Appearance / Additional features | Extensions → Camera Mirror |
| Toggle Sneak Peek shortcut | `KeyboardShortcuts` `toggleSneakPeek` | Shortcuts | Shortcuts (owner: Media) |
| Toggle Notch Open shortcut | `KeyboardShortcuts` `toggleNotchOpen` | Shortcuts | Shortcuts (owner: Notch) |
| Release name / version / build | `releaseName` | About | About |
| Software update status (disabled) | none (Sparkle) | About | About |
| GitHub link + attribution | none | About | About |

Unsurfaced keys to preserve untouched (not rendered today, do not promote):
`showEmojis`, `shelfTapToOpen`, `tileShowLabels`, `showShuffleAndRepeat`,
`enableDownloadListener`, `enableSafariDownloads`,
`selectedDownloadIndicatorStyle`, `selectedDownloadIconStyle`,
`didClearLegacyURLCacheV1`.

**Window title:** change the visible title in
`NotchKit/NotchKit/components/Settings/SettingsWindowController.swift:43` from
`"Boring Notch Settings"` to `"NotchKit Settings"`. Keep the attribution in
`About` (`SettingsView.swift:898`) and the GitHub link (`:876-894`). The window
identifier `"BoringNotchSettingsWindow"` is not user-visible; leave it unless a
later cleanup is explicitly scoped.

## 3. Typed routes

In the host (new file `NotchKit/NotchKit/components/Settings/SettingsRoutes.swift`):

```swift
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, interaction, extensions, shortcuts, about
    var id: String { rawValue }
}

enum ShortcutsOwner: String, CaseIterable, Identifiable, Hashable {
    case notch, media
    var id: String { rawValue }
}

struct ExtensionSettingsRoute: Hashable {
    let featureID: FeatureSettingsID      // stable host feature id
    let destinationID: DestinationID      // stable settings destination id
}
```

- Sidebar: `List(selection: $selection)` with
  `NavigationLink(value: SettingsSection.general)` etc. The detail `switch`
  maps each case to its page; the `default` is `.general`.
- Existing link mapping is 1:1 from the old string values; there is no
  persisted navigation to migrate (`selectedTab` is `@State`, no
  `@SceneStorage`; window restoration is inert).
- Extensions detail owns `NavigationStack(path: $extensionsPath)` where
  `extensionsPath: [ExtensionSettingsRoute]`. Hub rows append a route; the
  destination view resolves the catalog entry by `destinationID`.
- **Feature detail → owner's shortcuts group:** feature detail pages expose an
  `onOpenShortcuts: (ShortcutsOwner) -> Void` closure. The parent Extensions
  page forwards it to the root, which sets `selection = .shortcuts` and
  `shortcutsOwnerFilter = owner`. This works without external deep-linking.
- **Stale-route fallback:** if a route's `destinationID` is not in the catalog
  (definition removed, or CoreOnly build), render an explicit
  "This feature is not available in this build." view with a Back action; do
  not crash or show an empty pane. On `SettingsCatalog` rebuild, prune
  `extensionsPath` entries whose `destinationID` is absent.
- **Back navigation / Escape:** do not rely on `NavigationStack` automatically
  mapping Escape. Provide an explicit toolbar Back button bound to
  `dismiss()` and `.keyboardShortcut(.cancelAction)`, and wire
  `.onExitCommand` to pop the current route (or close the settings window at
  the root). Cover this in the manual GUI checklist.

## 4. Lifecycle-independent settings

### 4.1 SDK change (additive, source-compatible)

`ExtensionDefinition` gains a lazy settings factory, defaulting to `[]`:

```swift
public struct ExtensionDefinition {
    public let metadata: ExtensionMetadata
    public let makeInstance: @MainActor (ExtensionContext) -> any NotchExtension
    /// Lifecycle-independent settings pages for the Extensions hub.
    /// Must not create or capture a live NotchExtension instance.
    public let settings: @MainActor () -> [ExtensionSettingsDestination]

    public init(
        metadata: ExtensionMetadata,
        settings: @escaping @MainActor () -> [ExtensionSettingsDestination] = { [] },
        makeInstance: @escaping @MainActor (ExtensionContext) -> any NotchExtension
    ) { ... }
}
```

Requirements:

- The manifest stays metadata-only. `ExtensionMetadata` is unchanged; nothing
  is added to the JSON schema, `manifest.json`, or validator fixtures.
- The factory must not capture a `NotchExtension` instance, an
  `ExtensionContext`, or a live service. It returns view factories/`AnyView`
  closures that read configuration only.
- The factory is called by the host at catalog-build time and by the hub when
  rendering a detail, never during activation.

### 4.2 API-version implications (against the actual policy)

`ExtensionAPIVersion.current` is `1.0.0`. Compatibility is enforced by
`ExtensionCompatibility.validate`, which checks (a) `artifactKind`, (b)
`metadata.supportedHostVersions`, (c) `metadata.supportedSDKVersions`, and the
capability/entry-point invariants. It does **not** compare
`metadata.apiVersion` to `current`; the docs' "compatibility is major-only"
statement is reflected by `isCompatibleWithCurrent` (major equality) and by the
sustained `1.x` range in `supportedSDKVersions`.

`ExtensionDefinition` is **not** part of the serialized manifest, so adding
`settings` does not change the API contract or compatibility. Therefore:

- **No `ExtensionAPIVersion` bump is required.**
- No manifest, schema, validator, or compatibility-test change is required for
  this field.
- If settings declaration is ever exposed to manifest authors (out of scope),
  that is a manifest-contract change and would bump the minor API version.

### 4.3 Transition away from instance `settingsDestinations()` (no duplicates)

Current path: `ExtensionHost.finishActivation` publishes
`instance.settingsDestinations()` into `ContributionStore` only while active
(`ExtensionHost.swift:230-236`), and removes them on deactivation
(`:283`, `:308`). The hub reads
`runtime.contributions.settingsDestinations` (`ExtensionsSettingsView.swift:66-70`).

Transition:

1. `NotchExtension.settingsDestinations()` becomes deprecated and returns `[]`.
   Battery's destination moves out of `BatteryExtension.settingsDestinations()`
   and into `BatteryExtensionFactory.definition`'s `settings`; Shelf's moves
   from `ShelfExtension.settingsDestinations()` into
   `BuiltInExtensions.shelfDefinition()`'s `settings`.
2. `ExtensionHost.finishActivation` stops publishing settings to
   `ContributionStore` (pass `settings: []`). The runtime library's public API
   is unchanged, so there is no breaking change and no API bump.
3. `ExtensionsSettingsView` reads **only** the `SettingsCatalog`. The catalog is
   built from `registry.definitions[].settings()`, so there is exactly one
   registration path and no duplicate pages. An automated test asserts the hub
   has exactly one page per feature id and that `ContributionStore` contributes
   no settings.

### 4.4 Catalog lifetime and staleness

New host type `SettingsCatalog` (`@MainActor ObservableObject`):

```swift
struct FeatureSettingsID: Hashable { let rawValue: String }
enum SettingsManagement { case runtimeManaged, configurationOnly }

struct SettingsCatalogEntry: Identifiable {
    let id: FeatureSettingsID
    let displayName: String
    let iconSystemName: String
    let owner: ExtensionIdentity?          // nil for core-owned adapters
    let management: SettingsManagement
    let destinations: [ExtensionSettingsDestination]
}

final class SettingsCatalog: ObservableObject {
    @Published private(set) var entries: [SettingsCatalogEntry]
    func rebuild(from definitions: [ExtensionDefinition], adapters: [SettingsCatalogEntry])
    func entry(for destinationID: DestinationID) -> SettingsCatalogEntry?
}
```

Lifetime decision: definitions are registered once in
`NotchKitRuntime.bootstrap()` and there is **no production removal path** (no
uninstall UI is permitted). To avoid silent staleness anyway:

- `rebuild(from:adapters:)` is idempotent and is called after `catalog.add` +
  `registry.registerAll` in `bootstrap()`.
- Any code path that calls `ExtensionHost.remove(_:)` or `shutdown()` must call
  `settingsCatalog.rebuild(...)` (or the host invokes a rebuild hook); the
  removal path is currently test-only, so this is documented and covered by a
  test that asserts a removed definition leaves no catalog entry or route.
- The hub's route resolver treats a missing destination as the stale-route
  fallback in §3.

## 5. Honest enablement

| Feature | Control in hub | Rationale |
| --- | --- | --- |
| Battery | Enable/disable toggle (lifecycle-managed) | `activate()`/`deactivate()` and the app-wide monitor are implemented and tested. |
| Home | No toggle; required host destination | Core requires Home; do not offer disabling it. |
| Shelf | Configuration only; **no extension-wide toggle** | Disable-safety is documented incomplete (`extensions.md:147-150`). Keep `boringShelf` with the accurate label **"Show Shelf"**; do not sync it to a lifecycle flag. |
| Calendar & Reminders | Configuration only | Not extracted; lifecycle not implemented. |
| Media | Configuration only | Not extracted. |
| HUD | Configuration only | Not extracted. |
| Camera Mirror | Configuration only | Not extracted. |

The `Shelf` settings page keeps `boringShelf` (relabeled "Show Shelf"),
`openShelfByDefault`, `expandedDragDetection`, `copyOnDrag`,
`autoRemoveShelfItems`, and `quickShareProvider` with unchanged behavior. The
hub must not present a "disable Shelf" affordance.

## 6. Settings side effects

Rule: settings listing/rendering must not construct a `NotchExtension`, call
`activate()`, start a long-lived feature service, or issue a permission
request automatically. Status reads, refreshes after access is granted, and
provider discovery are allowed but must be page-scoped and torn down on close.

Concrete changes (do not blanket-delete `.task`/`.onAppear`/`init`):

- **Calendar & Reminders.** Today `CalendarSettings.onAppear` calls
  `CalendarManager.checkCalendarAuthorization()`/`checkReminderAuthorization()`
  (`SettingsView.swift:815-820`), and the former **requests** access when status
  is `.notDetermined` (`CalendarManager.swift:67-75`). Replace with a
  page-scoped `CalendarSettingsDataProvider` that:
  - reads `EKEventStore.authorizationStatus(for: .event/.reminder)` only;
  - when `.fullAccess`, lists calendars/reminders through a short-lived
    `CalendarService`/`EKEventStore` and preserves `calendarSelectionState` and
    per-item selection semantics;
  - exposes explicit "Grant Calendar Access"/"Grant Reminder Access" buttons
    that perform `requestAccess` only when tapped;
  - refreshes after the user returns from System Settings;
  - cancels its task/observer on `.onDisappear`. It must **not** instantiate
    `CalendarManager.shared` (the long-lived observer/service).
- **Shelf.** Today `Shelf.init()` runs
  `QuickShareService.shared.discoverAvailableProviders()`
  (`SettingsView.swift:929-931`). Move discovery to a page-scoped provider load
  (or explicit "Refresh" action) that cancels on `.onDisappear`. It must not
  start Shelf's drag/observer services. `quickShareProvider` behavior is
  preserved.
- **HUD.** Today the page starts `XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()`
  on appear (`SettingsView.swift:586-588`) and stops it on disappear. Replace
  the automatic monitor with a one-shot `isAccessibilityAuthorized()` status
  read on appear; keep the explicit "Request Accessibility" button. If live
  updates are retained, they must remain a visible-page-only subscription and
  never auto-request.
- **Battery.** The host `Charge` page's `onAppear` accessibility read
  (`SettingsView.swift:380-384`) is deleted with the page; the package
  `BatterySettingsView` uses only `UserDefaults` and has no side effects.
- **Extensions hub.** The hub reads `SettingsCatalog` + `registry.metadata` +
  `host.phase`; it constructs no instances and calls no services.

## 7. States and Retry

- **Empty:** neutral "No built-in features are available." No marketplace copy.
- **Disabled:** configuration entry remains visible and its settings page opens;
  the page renders without services.
- **Failed:** row shows the `.failed(String)` message; add a **Retry** action.
  Retry calls `runtime.host.reconcileNow()` (which re-runs activation when the
  extension is enabled and the phase is `.failed` — `ExtensionHost.swift:104-110`)
  followed by `presentation.refreshAll()`. Retry must **not** call
  `setEnabled(true, ...)`, which is a no-op when already enabled
  (`ExtensionManager.swift:61-66`). No runtime addition is required.
- **Activating/deactivating:** show the current phase accurately; disable the
  toggle while a transition is in flight.
- **Battery-absent (CoreOnly):** Battery's definition is not registered, so
  there is no hub row, no catalog entry, and no dangling route. Stale routes
  fall back per §3. Validate with the `NotchKitCoreOnly` scheme.
- **Home:** shown (if at all) as a required host destination, never with a
  toggle.

## 8. Shortcuts

- Central `Shortcuts` page remains the single source of truth and is grouped by
  `ShortcutsOwner`: **Notch** (`toggleNotchOpen`) and **Media**
  (`toggleSneakPeek`).
- Feature detail pages expose a "Keyboard Shortcuts" link that activates the
  owner's group in the central page (§3).
- The unused names `clipboardHistoryPanel`, `toggleMicrophone`,
  `decreaseBacklight`, and `increaseBacklight` have no handlers; do **not**
  surface recorders for them. Report them as a defect/decision instead.
- Per-extension shortcut declarations are proposed, not implemented here.

## 9. Accessibility, localization, window sizing

- Icon-only / labels-hidden toggles (`SettingsView.swift:493`,
  `ExtensionsSettingsView.swift:133`) get `.accessibilityLabel`; phase and
  failure states get an accessible label/value ("Failed: <error>").
- Sidebar arrow-key selection is preserved; feature detail uses an explicit
  Back button plus `.keyboardShortcut(.cancelAction)` and `.onExitCommand`.
- New UI strings are plain literals so Xcode auto-extraction
  (`SWIFT_EMIT_LOC_STRINGS=YES`) picks them up ("First-party extensions",
  "Built-in feature settings", "Failed", "Retry", "Required", "Disabled",
  "Show Shelf", "No built-in features are available.", etc.); add them to
  `NotchKit/NotchKit/Localizable.xcstrings`. Known pre-existing gap: extension
  `displayName`/`summary`/destination `title` are `String` (not
  `LocalizedStringKey`) and do not localize; document, do not silently change.
- Window sizing: set `window.minSize` (≈760×560) in
  `SettingsWindowController`; keep the window resizable and macOS 14 APIs only.
- Keep `window.title = "NotchKit Settings"` (§2).

## 10. Ownership / shared files (prevent conflicting edits)

| File | Owner |
| --- | --- |
| `NotchKit/Packages/NotchExtensionSDK/Sources/NotchExtensionSDK/ExtensionDefinition.swift`, `NotchExtension.swift` | SDK owner (Agent 2) — additive only |
| `NotchKit/Packages/NotchExtensionSDK/Sources/NotchExtensionRuntime/ExtensionHost.swift`, `ContributionStore.swift` | Runtime owner (Agent 2) — no public API break |
| `NotchExtensions/FirstParty/Battery/**` | Battery owner |
| `NotchKit/NotchKit/components/Settings/SettingsView.swift`, new `SettingsRoutes.swift` | Agent C |
| `NotchKit/NotchKit/components/Settings/SettingsWindowController.swift` | Agent C |
| `NotchKit/NotchKit/ExtensionHost/ExtensionsSettingsView.swift`, `NotchKitRuntime.swift`, `BuiltInExtensions.swift`, new `SettingsCatalog.swift`, `LegacyFeatureSettings.swift` | Agent C |
| `NotchKit/NotchKit/Localizable.xcstrings` | Localization owner (single editor) |
| `docs/architecture/settings-migration-plan.md` and related architecture docs | Docs owner |

Agent C owns implementation; the planner does not edit production code.

## 11. Commit sequence

1. **Typed routes + lifecycle-independent settings definitions/catalog.**
   Add `SettingsSection`/routes, `ExtensionDefinition.settings` (default `[]`),
   `SettingsCatalog.rebuild`, and the deprecated no-op
   `settingsDestinations()`. No UI page moves yet. Focused checks: SDK/runtime
   tests; a catalog unit test for duplicate-free construction and removal
   staleness.
2. **Battery consolidation + disabled/failed configuration access.** Move the
   Battery destination to the factory definition; stop publishing settings in
   `finishActivation`; rewrite the hub to read the catalog; Battery remains the
   only toggle. Focused checks: Battery tests, hub catalog tests, build both
   schemes.
3. **Legacy configuration adapters with preserved data loading.** Add
   `LegacyFeatureSettings` (Shelf, Calendar & Reminders, Media, HUD, Camera
   Mirror) and the isolated data providers from §6. Focused checks: provider
   unit tests, no service construction on render.
4. **Remove redundant top-level feature pages and redistribute global
   settings.** Delete `Charge` and the top-level Media/Calendar/HUD/Shelf/
   Battery/Advanced pages after redistributing every Advanced control; fix the
   window title. Focused checks: full control-to-destination mapping review,
   build both schemes.
5. **Shortcuts links, accessibility/localization, tests, documentation.**
   Add the feature→shortcuts route, accessibility labels, catalog strings, the
   window minimum size, and update architecture docs (including that extraction
   is not complete). Full relevant verification at this handoff.

Each commit runs only the focused checks above; the full SDK/runtime, Battery,
validation, and both-scheme builds run at the completed handoff.

## 12. Acceptance checklist

- [ ] Every control in §2 appears exactly once at its final location; none
      dropped, duplicated, or left in a removed `Advanced` section.
- [ ] All preference keys, defaults, and raw strings are unchanged; stored
      values survive upgrade.
- [ ] Extensions lists exactly six feature configuration entries with accurate
      state; only Battery has an enable/disable control; Home has none; Shelf
      shows "Show Shelf" and no extension-wide toggle.
- [ ] Opening any settings page constructs no `NotchExtension`, calls no
      `activate()`, starts no long-lived feature service, and issues no
      automatic permission request.
- [ ] Calendar status/reads, Calendar/Shelf refresh-after-grant, and Quick
      Share discovery remain functional and are page-scoped; subscriptions stop
      on page close.
- [ ] Configuration pages are accessible while disabled and while failed.
- [ ] Retry restarts a failed, already-enabled extension via
      `host.reconcileNow()`; failure messaging is clear.
- [ ] Feature detail → owner shortcuts group works; back/Escape works
      explicitly; stale routes fall back and are pruned.
- [ ] `NotchKitCoreOnly` builds with no Battery row, catalog entry, or route.
- [ ] No marketplace/install/uninstall/verification surface is added or
      re-enabled; attribution and GitHub link are retained.
- [ ] Accessibility labels, keyboard navigation, localization strings, and
      window minimum sizing are in place; macOS 14 only.
- [ ] SDK/runtime tests (currently 100), Battery tests (16), and validation
      tests (5) pass; both `NotchKit` and `NotchKitCoreOnly` build.
- [ ] Shared schemes/CI claims match reality: no shared scheme files are
      committed; `cicd.yml:29-31` builds both schemes; `build_reusable.yml`
      archives only `NotchKit`. Do not call CI broken without checking these.

## 13. Post-implementation review (independent, read-only)

After Agent C finishes, review the actual diff and report defects with
`file:line` references:

- compare resulting controls against the reconciled inventory (Agent A + §2);
- verify disabled access, service-free rendering, routing, preference
  preservation, and Battery-free exclusion;
- distinguish automated evidence (builds/tests/inspection) from GUI checks
  actually performed;
- optionally spawn one bounded independent navigation/accessibility review
  subagent.

### Review leads from the integration report

Known reported defect categories to check, without broadening into repairs:

- **Lifecycle:** Shelf disable-safety incomplete; only Battery is fully
  managed. Settings must not depend on activation.
- **Migration:** identity migration end-to-end unverified; keys must not be
  renamed. Navigation is not persisted, so no nav migration is needed.
- **Validator:** manifests are valid; new hub strings are absent from the
  localization catalog and metadata titles are not localizable. Add host
  strings; do not alter the manifest schema.
- **CI:** schemes are not shared; `extensions.yml` is path-filtered to
  `NotchExtensions/**` and `NotchKit/Packages/**`, so host-only edits will not
  run SDK tests, while `cicd.yml` builds both app schemes. Verify the actual
  files rather than assuming.

## Reconciliation record

Agent C incorporated both documentation commits (Agent A's inventory
`46afd93` and this plan `d5c10d0`) into `codex/extensions-settings` on top of
development `00a5750`. The inventory is now in-tree. The resolved differences
between the two documents are:

1. **Agent A inventory status.** The plan's "pending" note is corrected above;
   the inventory is available and authoritative for control-level detail.
2. **`calendarSelectionState`.** The plan's Appendix A listed it among
   "not user-facing today" keys. Agent A sections 4 and 17 establish that it is
   surfaced through the per-calendar/per-reminder-list toggles and written by
   `CalendarManager.setCalendarSelected`. Corrected above; the consolidation
   surfaces it under Extensions → Calendar & Reminders.
3. **`autoScrollToNextEvent`.** Surfaced today but inert (read nowhere). It is
   kept visible at its approved destination and its inert status is recorded;
   it is not silently implemented or removed.
4. **`useMusicVisualizer`.** Surfaced today but permanently `.disabled(true)`.
   Moved to Extensions → Media and kept disabled; not silently enabled.
5. **`musicControlSlotLimit`.** Unsurfaced (the slot editor hardcodes 5); it is
   not exposed merely because the persisted key exists.
6. **Battery duplicate pages.** The host `Charge` page and the package
   `BatterySettingsView` write the same four keys. The package view is
   authoritative; `Charge` is removed only after lifecycle-independent access
   exists.
7. **Shelf duplicated enablement.** `boringShelf` (UI gate) and the
   extension-state enabled flag (contributions) are independent and are **not**
   synchronized. `boringShelf` is relabeled "Show Shelf"; the extension-wide
   lifecycle toggle is removed from the hub.
8. **Unused duplicate declarations.** The unused `mirrorShape` declaration in
   `GeneralSettings` and the unused `enableLyrics` declaration in `Media` are
   duplicated declarations of settings that are used elsewhere; only the unused
   declarations are deleted, and the functioning controls are retained.

## Appendix A: key-audit reconciliation

Comparing the independently-derived inventory with Agent A's key audit:

- Keys defined by `Defaults.Keys` and surfaced/referenced match; the full
  defined/used lists were cross-checked.
- `openLastTabByDefault` is a `BoringViewCoordinator` `@AppStorage` key, not a
  `Defaults.Keys` entry; it still belongs to Interaction.
- `preferred_screen_uuid` and `alwaysShowTabs`/`musicLiveActivityEnabled` are
  coordinator `@AppStorage` keys, not `Defaults.Keys`; they keep their current
  storage.
- `shelfTapToOpen` is referenced in code but not rendered in the settings UI;
  it stays untouched.
- `tileShowLabels`, `showShuffleAndRepeat`, `enableDownloadListener`,
  `enableSafariDownloads`, `selectedDownloadIndicatorStyle`,
  `selectedDownloadIconStyle`, and `didClearLegacyURLCacheV1` are not
  user-facing settings today; they stay untouched.
- `calendarSelectionState` is **surfaced and used** through the per-calendar and
  per-reminder-list toggles (it is read/written by `CalendarManager`), so it is
  *not* in the unsurfaced-key list above. The one disagreement with Agent A's
  earlier draft classification is resolved in
  [Reconciliation record](#reconciliation-record).
- Omissions/disagreements between this table and Agent A's
  `settings-inventory.md` are resolved in
  [Reconciliation record](#reconciliation-record); no key or control is removed
  as part of that reconciliation.
## Appendix B: implementation status (Agent C)

Branch: `codex/extensions-settings`, based on development
`00a57505696225d42bbd66a051d4a93e0c6d9f56`, with Agent A's inventory
(`46afd93`) and this plan (`d5c10d0`) incorporated once by cherry-pick.

Reviewable commits:

| Commit | Scope |
| --- | --- |
| `ace04d9` | SDK/runtime settings contract, `ExtensionAPIVersion` `1.1.0`, catalog core, tests, documentation reconciliation |
| `0035ec2` | Host consolidation: typed navigation, catalog wiring, legacy adapters/providers, sidebar redistribution, Battery consolidation, old-page removal |
| `45d7e06` | Localized settings strings |

### Deliberate deviations from the plan

- The pure catalog core (`FeatureSettingsID`, `SettingsManagement`,
  `SettingsCatalogEntry`, `SettingsCatalog`) lives in the linked
  `NotchExtensionRuntime` module rather than a host-only file. The runtime
  package has no app-internal dependencies, and this makes catalog
  construction, duplicate prevention, and removal staleness unit-testable under
  the existing `swift test` CI job. The **host remains the authority**: it
  supplies `runtimeManaged`, presentation order, and the legacy adapters, and
  `SettingsRoutes.swift` owns the SwiftUI navigation types.
- The six sidebar sections and the Extensions `NavigationStack` replace the
  previous string `selectedTab`. Sidebar selection was never persisted, so no
  navigation migration was added.

### SDK/API transition

- `ExtensionDefinition.settings` is additive and source-compatible; it defaults
  to `[]`, so existing initializers still compile.
- `NotchExtension.settingsDestinations()` is retained and deprecated; the host
  ignores it. `ContributionStore.set(open:closed:settings:for:)` is unchanged,
  so consumers of the settings API are not broken.
- `ExtensionAPIVersion.current` moves `1.0.0 -> 1.1.0` because the documented
  policy treats additive changes as minor bumps. The serialized manifest schema
  and its `manifest.json`/validator fixtures are unchanged.

### Verification actually performed

- `swift test --package-path NotchKit/Packages/NotchExtensionSDK`: **106** tests
  (baseline 100 + 5 catalog + 1 retry) pass.
- `swift test --package-path NotchExtensions/FirstParty/Battery`: **18** tests
  (baseline 16 + 2 lifecycle-independent settings) pass.
- `swift test --package-path NotchExtensions/validation`: **5** tests pass.
- `xcodebuild ... -scheme NotchKit -configuration Debug`: build succeeds.
- `xcodebuild ... -scheme NotchKitCoreOnly -configuration Debug`: build
  succeeds; Battery is still excluded by product linkage and definition
  registration, so it has no catalog entry, row, or route.
- Added tests: listing settings does not instantiate extensions; catalog
  construction is duplicate-free; rebuild after removal leaves no stale entry;
  `reconcileNow()` retries an already-enabled failed extension; Battery settings
  are declared on the definition and building the page starts no monitor.

### Not performed (require a GUI/hardware session)

- Interactive GUI checks of every sidebar section and feature detail, Battery
  enable/disable/re-enable, Calendar permission prompts and authorized list
  loading, Shelf provider discovery, Media/HUD/Camera configuration, Shortcuts
  owner focus, Back/Escape/keyboard behaviour, and window resizing under longer
  localized labels. These were **not** run in this session; no visual
  correctness is inferred from a successful build.
- The host target has no unit-test target, so the page-scoped providers
  (`CalendarSettingsDataProvider`, `ShelfShareProviderDataSource`) were verified
  by build and inspection only. Adding a host test target is future work.

### Pre-existing limitations preserved

- `autoScrollToNextEvent` is surfaced but inert; `useMusicVisualizer` is
  surfaced but permanently disabled; `musicControlSlotLimit` stays unsurfaced.
- Extension `displayName`/`summary`/destination `title` are `String`, not
  `LocalizedStringKey`, so they do not localize. Recorded, not redesigned.
- `MusicManager.shared` remains a pre-existing app-global that the Media page
  reads (deprecation status, slot preview); it is not started by settings.

### Scope

This consolidates settings configuration. Battery remains the only fully
lifecycle-managed feature. Extracting Calendar, Shelf, Media, HUD, or Camera
Mirror into independently installed extensions, and any marketplace/install
surface, remain future work.
