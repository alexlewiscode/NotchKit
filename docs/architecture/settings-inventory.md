# Settings inventory (Agent C handoff)

Status: audit record. Documentation only; no production code, tests, project
settings, or workflows are changed by this document.

Base: `development` at `00a57505696225d42bbd66a051d4a93e0c6d9f56`.
Applies to: macOS 14 deployment target. The base was verified unchanged when
this worktree was created.

This document is the durable, control-level inventory of every existing NotchKit
setting, its persisted key and default, its side effects, its owner, and its
approved destination under the consolidation policy. It also records what is
*unsurfaced* or *dead* so that a reorganization does not expose settings that
were intentionally not exposed, and does not lose controls that currently work.

Related documents: [`extensions.md`](extensions.md),
[`extension-api.md`](extension-api.md),
[`first-party-battery-extraction.md`](first-party-battery-extraction.md),
[`calendar-migration-plan.md`](calendar-migration-plan.md),
[`identity-migration.md`](identity-migration.md).

## How to read this document

- **Visible control** — a control a user can currently see and interact with.
- **Unsurfaced key** — a persisted key that exists but has no reachable control.
  Do **not** expose it merely because the key exists; exposing requires a
  product decision.
- **Dead UI** — a view or control that is commented out or never instantiated.
- **Owner** — the feature or core subsystem that is accountable for the setting.
- **Approved destination** — the bucket from the consolidation policy. It is not
  a claim that the move is implemented.
- **CoreOnly** — the battery-free `NotchKitCoreOnly` target. Only Battery is
  excluded from it today; every other feature is compiled in.

Destination policy in effect:

| Destination | Scope |
| --- | --- |
| General | startup, menu bar, display selection |
| Appearance | notch size/shape, global colors, shadows, animation styling |
| Interaction | hover, gestures, haptics, open/close behaviour |
| Extensions | Battery, Calendar & Reminders, Shelf, Media, HUD, Camera Mirror |
| Shortcuts | central list grouped by owner |
| About | version, attribution, update status |

Feature-specific styling belongs with its feature, including music visualizers.

## Settings surfaces and navigation

- Settings window: `SettingsWindowController.swift:13-106`. Window title is
  currently `"Boring Notch Settings"` (`:43`) and the identifier is
  `BoringNotchSettingsWindow` (`:58`).
- Sidebar and detail: `SettingsView.swift:28-68` (links) and `:75-110` (switch).
  `selectedTab` is a private `@State` defaulting to `"General"` (`:18`) with no
  external setter, so no caller can deep-link to a specific page.
- Open entry points (all land on General): MenuBarExtra
  `NotchKitApp.swift:34-39`; notch context menu `ContentView.swift:184-190`;
  header gear `BoringHeader.swift:67-85`; onboarding finish
  `NotchKitApp.swift:601-604`.
- Extensions hub: `ExtensionsSettingsView.swift:17-82`; settings destinations are
  presented in a **sheet** (`:50-63`); enablement binding `:72-81`; Home is
  "Required" and cannot be disabled (`:128-131`).
- Pages and their definitions: `GeneralSettings` `SettingsView.swift:134-353`;
  `Charge` `:356-388` (Battery, `#if !NOTCHKIT_CORE_ONLY`); `HUD` `:471-598`;
  `Media` `:600-714`; `CalendarSettings` `:716-822`; `About` `:841-916`;
  `Shelf` `:918-1025`; commented `Downloads` `:391-469`; commented legacy
  `Extensions` `:1027-1164`; `Appearance` `:1166-1416`; `Advanced` `:1418-1692`;
  `Shortcuts` `:1731-1753`.
- Reusable bits: `AccentCircleButton` `:1695`, `proFeatureBadge` `:1755`,
  `comingSoonTag` `:1766`, `customBadge` `:1776`, `warningBadge` `:1786`.

## Persistence model

Two persistence mechanisms are in use:

1. `Defaults.Keys` in `models/Constants.swift:71-202`. These are the settings
   keys the app has always used. They must not be renamed merely to reorganize
   settings.
2. `@AppStorage` in `BoringViewCoordinator.swift:60-90` (and `UserDefaults`
   directly for extension state). These are not in `Constants.swift`.

Extension enabled state is stored separately by `UserDefaultsExtensionStateStore`
under `com.notchkit.extensions.state` (`ExtensionStateStore.swift:38-59`,
`NotchKitIdentity.swift:24`). It is not a `Defaults.Keys` key.

Keyboard shortcuts are stored by the `KeyboardShortcuts` package under its own
store; `ShortcutConstants.swift:12-17` declares the names.

---

## 1. General (`GeneralSettings`, `SettingsView.swift:134-353`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Show menu bar icon | `:159-164` | `menubarIcon` | `true` | Inserts/removes `MenuBarExtra` (`NotchKitApp.swift:19,33`) | Core shell | General |
| Launch at login | `:166` (`LaunchAtLogin.Toggle`) | none (LaunchAtLogin store) | package-defined | Registers login item | Core shell | General |
| Show on all displays | `:167-173` | `showOnAllDisplays` | `false` | Posts `showOnAllDisplaysChanged`; `NotchKitApp.swift:330-339` rebuilds windows | Core windowing | General |
| Preferred display | `:174-185` | `preferred_screen_uuid` (`@AppStorage`) | main display UUID | Writes coordinator; posts `selectedScreenChanged` (`BoringViewCoordinator.swift:90-97`); disabled when `showOnAllDisplays` | Core display | General |
| Automatically switch displays | `:187-194` | `automaticallySwitchDisplay` | `true` | Posts `automaticallySwitchDisplayChanged`; disabled when `showOnAllDisplays` | Core display | General |
| Notch height on notch displays | `:200-223` | `notchHeightMode` | `.matchRealNotchSize` | Resets `notchHeight` to 38/44/38; posts `notchHeightChanged` | Core geometry | Appearance |
| Custom notch height slider | `:224-232` | `notchHeight` | `32` | Posts `notchHeightChanged` | Core geometry | Appearance |
| Notch height on non-notch displays | `:233-252` | `nonNotchHeightMode` | `.matchMenuBar` | Resets `nonNotchHeight` to 24/32/32; posts `notchHeightChanged` | Core geometry | Appearance |
| Custom non-notch height slider | `:253-261` | `nonNotchHeight` | `32` | Posts `notchHeightChanged` | Core geometry | Appearance |
| Open notch on hover | `NotchBehaviour`, `:328-330` | `openNotchOnHover` | `true` | `.onChange` at `:278-282` forces `enableGestures = true` when turned off | Interaction | Interaction |
| Enable haptic feedback | `:331-333` | `enableHaptics` | `true` | Read by `ContentView.swift:382,435,467`; `BoringCalendar.swift:50,135` | Interaction | Interaction |
| Remember last tab | `:334` | `openLastTabByDefault` (`@AppStorage`) | `false` | `didSet` forces `alwaysShowTabs = true` (`BoringViewCoordinator.swift:76-82`) | Core tabs | Interaction |
| Hover delay | `:336-348` | `minimumHoverDuration` | `0.3` | Posts `notchHeightChanged` (a side effect that only repositions windows) | Interaction | Interaction |
| Enable gestures | `gestureControls`, `:288-290` | `enableGestures` | `true` | Gates `ContentView.swift:136-147` pan gestures; disabled when `!openNotchOnHover` | Interaction | Interaction |
| Change media with horizontal gestures | `:293-294` | none | n/a | **Placeholder**: constant `false`, `.disabled(true)` | Interaction | Interaction (leave disabled) |
| Close gesture | `:295-297` | `closeGestureEnabled` | `true` | Gates up-swipe close (`ContentView.swift:142`) | Interaction | Interaction |
| Gesture sensitivity | `:298-308` | `gestureSensitivity` | `200.0` | Read `ContentView.swift:431,434,449,458` | Interaction | Interaction |
| (unsurfaced) | `@Default(.showEmojis)` declared `:143` | `showEmojis` | `false` | No control and no consumer | Core | Leave unsurfaced |
| (unused declaration) | `@Default(.mirrorShape)` declared `:142` | `mirrorShape` | `.rectangle` | Shadowed by the used declaration in Appearance `:1168` | Camera Mirror | Remove the unused declaration only |

## 2. Appearance (`Appearance`, `SettingsView.swift:1166-1416`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Always show tabs | `:1184` | `alwaysShowTabs` (`@AppStorage`) | `true` | `didSet` may select Home (`BoringViewCoordinator.swift:65-74`) | Core tabs | Appearance |
| Show settings icon in notch | `:1185-1187` | `settingsIconInNotch` | `true` | Read `BoringHeader.swift:67` | Core shell | Appearance |
| Colored spectrogram | `:1194-1196` | `coloredSpectrogram` | `true` | Read `MusicManager.swift:560`, `BuiltInClosedNotchViews.swift:69,84,110` | Media | Extensions / Media |
| Player tinting | `:1197-1198` | `playerColorTinting` | `true` | Read `NotchHomeView.swift:150,508`, `ContentView.swift:313` | Media | Extensions / Media |
| Enable blur effect behind album art | `:1199-1201` | `lightingEffect` | `true` | Read `NotchHomeView.swift:34` | Media | Extensions / Media |
| Slider color | `:1202-1206` | `sliderColor` | `.white` | Raw key is legacy `"sliderUseAlbumArtColor"` (`Constants.swift:111`); read `NotchHomeView.swift:492-494` | Media | Extensions / Media |
| Use music visualizer spectrogram | `:1212-1216` | `useMusicVisualizer` | `true` | Always `.disabled(true)`; read `BuiltInClosedNotchViews.swift:107` | Media | Extensions / Media (leave disabled) |
| Selected animation | `:1219-1230` | `selectedVisualizer` | `nil` | Shown only when `!useMusicVisualizer`; read `LottieAnimationView.swift:12` | Media | Extensions / Media |
| Custom visualizers list + add/remove sheet | `:1249-1374` | `customVisualizers` | `[]` | Writes on add/remove; previews instantiate `LottieView` with the stored URL (remote fetch) | Media | Extensions / Media |
| Enable boring mirror | `:1386-1389` | `showMirror` | `false` | `.disabled(!checkVideoInput())`; read `BoringHeader.swift:51`, `NotchHomeView.swift:443` | Camera Mirror | Extensions / Camera Mirror |
| Mirror shape | `:1390-1395` | `mirrorShape` | `.rectangle` | Read `WebcamView.swift:25,32` | Camera Mirror | Extensions / Camera Mirror |
| Show cool face animation while inactive | `:1396-1398` | `showNotHumanFace` | `false` | Closed-notch `idleFace` contribution flag (`BuiltInClosedNotch.swift:52,128`) | Home closed notch | Appearance (animation styling) — flag for Agent B: Home-owned |
| App icon selection | `:1577-1619` | none | n/a | **Placeholder**: `.disabled(true)`, "Coming soon" | Core shell | Appearance (leave disabled) |

## 3. Media (`Media`, `SettingsView.swift:600-714`; `MusicSlotConfigurationView.swift`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Music Source | `:613-623` | `mediaController` | dynamic: `.appleMusic` when Now Playing is deprecated, else `.nowPlaying` (`Constants.swift:184,193-199`) | `.onChange` posts `mediaControllerChanged`; `MusicManager.init` rebuilds the active controller (`MusicManager.swift:74-78`) | Media | Extensions / Media |
| Pear-desktop link / Now Playing note | `:627-646` | none | n/a | Reads `MusicManager.shared.isNowPlayingDeprecated` | Media | Extensions / Media |
| Show music live activity | `:649-652` | `musicLiveActivityEnabled` (`@AppStorage`) | `true` | Gates closed-notch music contribution flag (`BuiltInClosedNotch.swift:51,103`) | Media | Extensions / Media |
| Show sneak peek on playback changes | `:653` | `enableSneakPeek` | `false` | Read `MusicManager.swift:586` | Media | Extensions / Media |
| Sneak Peek Style | `:654-658` | `sneakPeekStyles` | `.standard` | Read `MusicManager.swift:587`, `ContentView.swift:309,323`, `NotchKitApp.swift:368` | Media | Extensions / Media |
| Media inactivity timeout | `:659-668` | `waitInterval` | `3` | Read `MusicManager.swift:546` | Media | Extensions / Media |
| Full screen behavior | `:669-681` | `hideNotchOption` | `.nowPlayingOnly` | Read `FullscreenMediaDetection.swift:44`, `BoringViewModel.swift:77` | Media | Extensions / Media |
| Music slot editor | `MusicSlotConfigurationView.swift:13,43-71,247-251` | `musicControlSlots` | `defaultLayout` | `onAppear` pads to 5; drag/drop writes array | Media | Extensions / Media |
| Reset slot defaults | `MusicSlotConfigurationView.swift:27-31` | `musicControlSlots` | `defaultLayout` | Writes default layout | Media | Extensions / Media |
| Show lyrics below artist name | `:688-693` | `enableLyrics` | `false` | Read `MusicManager.swift:345`, `NotchHomeView.swift:156` | Media | Extensions / Media |
| (unused duplicate) | `@Default(.enableLyrics)` `:608` | `enableLyrics` | `false` | Same key as the toggle above; declaration unused | Media | Remove duplicate declaration only |
| (unsurfaced) | `musicControlSlotLimit` | `musicControlSlotLimit` | `5` | Read and clamped in `NotchHomeView.swift:120,224-230`; **no control** | Media | Leave unsurfaced (slot editor hardcodes 5) |
| (unsurfaced) | `showShuffleAndRepeat` | `showShuffleAndRepeat` | `false` | No consumer; superseded by `musicControlSlots` | Media | Leave unsurfaced |

## 4. Calendar & Reminders (`CalendarSettings`, `SettingsView.swift:716-822`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Show calendar | `:725-727` | `showCalendar` | `false` | Embeds/removes `CalendarView` (`NotchHomeView.swift:450-458`); hides music edge slots when camera expanded (`:232-235`); disables list toggles (`:771,807`) | Calendar | Extensions / Calendar & Reminders |
| Hide completed reminders | `:728-730` | `hideCompletedReminders` | `true` | Read `BoringCalendar.swift:278` | Calendar | Extensions / Calendar & Reminders |
| Hide all-day events | `:731-733` | `hideAllDayEvents` | `false` | Read `BoringCalendar.swift:282` | Calendar | Extensions / Calendar & Reminders |
| Auto-scroll to next event | `:734-736` | `autoScrollToNextEvent` | `true` | **Surfaced but inert**: read nowhere; `scrollToRelevantEvent` always scrolls (`BoringCalendar.swift:293-309`) | Calendar | Extensions / Calendar & Reminders (keep visible; note inert) |
| Always show full event titles | `:737-739` | `showFullEventTitles` | `false` | Read `BoringCalendar.swift:271,372,410` | Calendar | Extensions / Calendar & Reminders |
| Per-calendar toggle | `:756-772` | `calendarSelectionState` | `.all` | `CalendarManager.getCalendarSelected`/`setCalendarSelected` (`CalendarManager.swift:146-175`), which rewrites the enum and refetches events | Calendar | Extensions / Calendar & Reminders |
| Per-reminder-list toggle | `:792-808` | `calendarSelectionState` | `.all` | Same key and code path as above | Calendar | Extensions / Calendar & Reminders |
| Open Calendar Settings (denied) | `:746-753` | none | n/a | Opens `x-apple.systempreferences:...Privacy_Calendars` | Calendar | Extensions / Calendar & Reminders |
| Open Reminder Settings (denied) | `:782-789` | none | n/a | Opens `x-apple.systempreferences:...Privacy_Reminders` | Calendar | Extensions / Calendar & Reminders |

`calendarSelectionState` is **not** unsurfaced. It is surfaced through the
per-calendar and per-reminder-list toggles above and is read/written by
`CalendarManager`. See "Corrections" for the classification fix.

## 5. HUD (`HUD`, `SettingsView.swift:471-598`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Replace system HUD | `:493-497` | `hudReplacement` | `false` | `BoringViewCoordinator.swift:140-163`: enabling requests accessibility and starts `MediaKeyInterceptor`; disabling stops it; may revert to `false` if denied (`:156`) | HUD | Extensions / HUD |
| Request Accessibility | `:507-510` | none | n/a | `HostPermissionService.requestHUDInputAccess()` | HUD | Extensions / HUD |
| Option key behaviour | `:518-522` | `optionKeyAction` | `.openSettings` | Read `MediaKeyInterceptor.swift:142` | HUD | Extensions / HUD |
| Progress bar style | `:524-529` | `enableGradient` | `false` | Read `SystemEventIndicatorModifier.swift:114` | HUD | Extensions / HUD |
| Enable glowing effect | `:530-532` | `systemEventIndicatorShadow` | `false` | Read `SystemEventIndicatorModifier.swift:125` | HUD | Extensions / HUD |
| Tint progress bar with accent color | `:533-535` | `systemEventIndicatorUseAccent` | `false` | Read `SystemEventIndicatorModifier.swift:116,122,126` | HUD | Extensions / HUD |
| Show HUD in open notch | `:542-544` | `showOpenNotchHUD` | `true` | Read `BoringHeader.swift:47` | HUD | Extensions / HUD |
| Show percentage (open notch) | `:545-547` | `showOpenNotchHUDPercentage` | `true` | Read `OpenNotchHUD.swift:16,54,63` | HUD | Extensions / HUD |
| HUD style | `:558-563` | `inlineHUD` | `false` | `.onChange` (`:564-571`) forces `systemEventIndicatorShadow=false` and `enableGradient=false` | HUD | Extensions / HUD |
| Show percentage (closed notch) | `:573-575` | `showClosedNotchHUDPercentage` | `false` | Read `InlineHUD.swift:96`, `SystemEventIndicatorModifier.swift:63` | HUD | Extensions / HUD |
| Accessibility status (read) | `.task` `:583-585` | none | n/a | Reads authorization | HUD | Extensions / HUD |
| Accessibility monitoring | `.onAppear` `.onDisappear` `:586-591` | none | n/a | Starts/stops `XPCHelperClient` polling every 3 s while visible | HUD | Extensions / HUD |

Master gating: sections are disabled when `!hudReplacement` (`:539,555,579`); the
master toggle itself is disabled when accessibility is not authorized (`:497`).

## 6. Battery

Two pages exist for one feature.

### 6a. Host page `Charge` (`SettingsView.swift:356-388`, `#if !NOTCHKIT_CORE_ONLY`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Show battery indicator | `:360-362` | `showBatteryIndicator` | `true` | Read `BoringHeader.swift:87` (also gated by extension enabledness) | Battery | Extensions / Battery |
| Show power status notifications | `:363-365` | `showPowerStatusNotifications` | `true` | Read `BatteryExtension.swift:67,91` | Battery | Extensions / Battery |
| Show battery percentage | `:371-373` | `showBatteryPercentage` | `true` | Read `BatteryViews.swift:231` | Battery | Extensions / Battery |
| Show power status icons | `:374-376` | `showPowerStatusIcons` | `true` | Read `BatteryViews.swift:76` | Battery | Extensions / Battery |
| Accessibility probe (read) | `.onAppear` `:380-384` | none | n/a | `XPCHelperClient.shared.isAccessibilityAuthorized()` | Battery | Remove with the page |

### 6b. Package page `BatterySettingsView` (`NotchExtensions/FirstParty/Battery/Sources/BatteryExtension/BatteryViews.swift:335-378`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Show battery indicator | `BatteryViews.swift:341-345` | `showBatteryIndicator` | `true` | Same key as host page | Battery | Extensions / Battery (authoritative) |
| Show power status notifications | `:346-350` | `showPowerStatusNotifications` | `true` | Same key | Battery | Extensions / Battery (authoritative) |
| Show battery percentage | `:355-359` | `showBatteryPercentage` | `true` | Same key | Battery | Extensions / Battery (authoritative) |
| Show power status icons | `:360-364` | `showPowerStatusIcons` | `true` | Same key | Battery | Extensions / Battery (authoritative) |

## 7. Shelf (`Shelf`, `SettingsView.swift:918-1025`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Enable shelf | `:936-938` | `boringShelf` | `true` | Gates open destination and settings destination availability (`BuiltInExtensions.swift:119,131`), header tab strip (`BoringHeader.swift:25`), and drop surface (`ContentView.swift:351`). **Does not** stop Shelf services or reconfigure drag detectors | Shelf | Extensions / Shelf (enablement source-of-truth to be unified) |
| Open shelf by default if items are present | `:939-941` | `openShelfByDefault` | `true` | Read `BoringViewModel.swift:216`, `BoringViewCoordinator.swift:69` | Shelf | Extensions / Shelf |
| Expanded drag detection area | `:942-944` | `expandedDragDetection` | `true` | `.onChange` posts `expandedDragDetectionChanged`; `NotchKitApp.swift:341-347` rebuilds detectors | Shelf | Extensions / Shelf |
| Copy items on drag | `:951-953` | `copyOnDrag` | `false` | Read `ShelfItemView.swift:329` | Shelf | Extensions / Shelf |
| Remove from shelf after dragging | `:954-956` | `autoRemoveShelfItems` | `false` | Read `ShelfItemView.swift:359` | Shelf | Extensions / Shelf |
| Quick Share Service | `:965-984` | `quickShareProvider` | dynamic default provider (`Constants.swift:169`) | Requires discovered providers; read `FileShareView.swift:16,23`; `Shelf.init` triggers discovery (`:929-931`) | Shelf | Extensions / Shelf |
| (unsurfaced) | `@Default(.shelfTapToOpen)` `:920` | `shelfTapToOpen` | `true` | No control and no consumer | Shelf | Leave unsurfaced |

The Extension hub also exposes a separate Shelf enable switch
(`ExtensionsSettingsView.swift:72-81,133`) that writes only the extension state
store, not `boringShelf`. See "Duplicated controls".

## 8. Camera Mirror

Camera Mirror has **no dedicated page**; its controls live in Appearance.

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Enable boring mirror | `SettingsView.swift:1386-1389` | `showMirror` | `false` | `.disabled(!checkVideoInput())`; read `BoringHeader.swift:51`, `NotchHomeView.swift:443` | Camera Mirror | Extensions / Camera Mirror |
| Mirror shape | `SettingsView.swift:1390-1395` | `mirrorShape` | `.rectangle` | Read `WebcamView.swift:25,32` | Camera Mirror | Extensions / Camera Mirror |
| In-notch camera button | `BoringHeader.swift:51-66` | none | n/a | Calls `vm.toggleCameraPreview()` (`BoringViewModel.swift:133-179`) | Camera Mirror | Extensions / Camera Mirror |
| Camera permission prompt | `WebcamView.swift:57-93` | none | n/a | Requests AV authorization on first tap; alerts on denial | Camera Mirror | Extensions / Camera Mirror |
| Onboarding camera step | `OnboardingView.swift:39-59,147-149` | none | n/a | `AVCaptureDevice.requestAccess(for: .video)` | Camera Mirror | Extensions / Camera Mirror |

`checkVideoInput()` (`SettingsView.swift:1409-1415`) only checks device presence
(`AVCaptureDevice.default(for: .video)`); it does **not** request permission.

## 9. Advanced (`Advanced`, `SettingsView.swift:1418-1692`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Accent color mode | `:1462-1466` | `useCustomAccentColor` | `false` | Drives `Color.effectiveAccent` (`Color+AccentColor.swift:13-45`) | Core appearance | Appearance |
| Accent color presets / custom picker | `:1497-1548` | `customAccentColorData` | `nil` | Archives `NSColor`; posts `AccentColorChanged`; `SettingsView` rebuilds via `.id` (`:127-130`) | Core appearance | Appearance |
| Enable window shadow | `:1567-1569` | `enableShadow` | `true` | Read `ContentView.swift:111` | Core windowing | Appearance |
| Corner radius scaling | `:1570-1572` | `cornerRadiusScaling` | `true` | Read widely (Content/NotchHome/Webcam) | Core windowing | Appearance |
| App icon selection | `:1577-1619` | none | n/a | **Placeholder**: `.disabled(true)`, "Coming soon"; tapping sets `NSApp.applicationIconImage` | Core shell | Appearance (leave disabled) |
| Extend hover area | `:1622-1624` | `extendHoverArea` | `false` | Read by window hit area | Interaction | Interaction |
| Hide title bar | `:1625-1627` | `hideTitleBar` | `true` | Read `BoringViewModel.swift:115` | Core windowing | Appearance |
| Show notch on lock screen | `:1628-1630` | `showOnLockScreen` | `false` | Read `NotchKitApp.swift:95,105` | Core windowing | Appearance |
| Hide from screen recording | `:1631-1633` | `hideFromScreenRecording` | `false` | `Defaults.publisher` in `BoringNotchSkyLightWindow.swift:81,89` | Core windowing | Appearance |

## 10. Shortcuts (`Shortcuts`, `SettingsView.swift:1731-1753`)

| Control | Symbol / path | Shortcut name | Default binding | Handler | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Toggle Sneak Peek recorder | `:1735` | `toggleSneakPeek` (`ShortcutConstants.swift:16`) | `⌘⇧H` | `NotchKitApp.swift:366-378`; hardcodes `.music` and bypasses `enableSneakPeek` | Media | Shortcuts (grouped under Media) |
| Toggle Notch Open recorder | `:1747` | `toggleNotchOpen` (`ShortcutConstants.swift:17`) | `⌘⇧I` | `NotchKitApp.swift:380-423` | Interaction | Shortcuts (grouped under Interaction) |
| (unwired) | `ShortcutConstants.swift:12` | `clipboardHistoryPanel` | `⌘⇧C` | **No handler** | none | Shortcuts (leave unwired) |
| (unwired) | `ShortcutConstants.swift:13` | `toggleMicrophone` | `fn+F5` | **No handler** | none | Shortcuts (leave unwired) |
| (unwired) | `ShortcutConstants.swift:14` | `decreaseBacklight` | `⌘F1` | **No handler** | none | Shortcuts (leave unwired) |
| (unwired) | `ShortcutConstants.swift:15` | `increaseBacklight` | `⌘F2` | **No handler** | none | Shortcuts (leave unwired) |

The Shortcuts page currently exposes only the two wired recorders. The four
unwired names must not be presented as working shortcuts.

## 11. About (`About`, `SettingsView.swift:841-916`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Release name (read-only) | `:849-854` | `releaseName` | `"Flying Rabbit 🐇🪽"` | Display only | Core shell | About |
| Version / build (read-only) | `:855-869` | none | n/a | Reads bundle | Core shell | About |
| Check for Updates | toolbar `:912`, `SoftwareUpdater.swift:21-33` | none | n/a | **Placeholder**: `.disabled(true)`, no action | Updater | About |
| Automatic update toggles | `SoftwareUpdater.swift:47-62` | none (hardcoded false) | n/a | **Placeholder**: `.disabled(true)` | Updater | About |
| GitHub link | `:879-891` | none | n/a | Opens upstream repository URL | Attribution | About |
| Attribution footer | `:896-904` | none | n/a | Static text | Attribution | About |

## 12. Extensions hub (`ExtensionsSettingsView`, `ExtensionsSettingsView.swift:17-141`)

| Control | Symbol / path | Key | Default | Side effects | Owner | Approved destination |
| --- | --- | --- | --- | --- | --- | --- |
| Per-extension enable switch | `:72-81,133` | `com.notchkit.extensions.state` (`enabled` map) | metadata `defaultEnabled` | Calls `runtime.host.setEnabled`; activates/deactivates the extension; removes/installs contributions | Extension runtime | Extensions |
| Settings destination link | `:112-123` | none | n/a | Presents `destination.makeView()` in a sheet | Extension runtime | Extensions |
| Home "Required" label | `:128-131` | none | n/a | No toggle | Extension runtime | Extensions |

There is **no** install, delete, search, or marketplace action. The footer states
extensions are compiled in (`:41-45`).

---

## 13. Unsurfaced keys and dead UI

Unsurfaced keys (do not expose without a product decision):

| Key | Default | Location | Reason to leave unsurfaced |
| --- | --- | --- | --- |
| `tileShowLabels` | `false` | `Constants.swift:108` | No control and no consumer |
| `showEmojis` | `false` | `Constants.swift:98` | No control and no consumer |
| `showShuffleAndRepeat` | `false` | `Constants.swift:130` | Superseded by `musicControlSlots` |
| `shelfTapToOpen` | `true` | `Constants.swift:168` | No control and no consumer |
| `musicControlSlotLimit` | `5` | `Constants.swift:136-139` | Read only; slot editor hardcodes 5 |
| `enableDownloadListener` | `true` | `Constants.swift:148` | Downloads feature does not exist |
| `enableSafariDownloads` | `true` | `Constants.swift:149` | Downloads feature does not exist |
| `selectedDownloadIndicatorStyle` | `.progress` | `Constants.swift:150` | Downloads feature does not exist |
| `selectedDownloadIconStyle` | `.onlyAppIcon` | `Constants.swift:151` | Downloads feature does not exist |
| `showWhatsNew` | `true` | `BoringViewCoordinator.swift:61` | No read observed |
| `currentMicStatus` | `true` | `BoringViewCoordinator.swift:63` | Written at `:229`, never read |

Surfaced but inert:

| Key | Default | Surfaced at | Why inert |
| --- | --- | --- | --- |
| `autoScrollToNextEvent` | `true` | `SettingsView.swift:734` | Declared `BoringCalendar.swift:270`; never read |
| `useMusicVisualizer` | `true` | `SettingsView.swift:1212` | Control always `.disabled(true)` |

Commented / dead UI (do not resurrect):

| Item | Location | Status |
| --- | --- | --- |
| Downloads page | `SettingsView.swift:391-469`, sidebar `:50-52` | Commented out; toggles disabled |
| Legacy Extensions manager (restart/disable/uninstall/add) | `SettingsView.swift:1027-1164` | Commented out |
| `EditPanelView` | `components/Settings/EditPanelView.swift:10-31` | Never instantiated |
| `ListItemPopover` | `components/Settings/ListItemPopover.swift:10-27` | Only referenced from commented code |
| `BoringExtrasMenu` | `components/Notch/BoringExtrasMenu.swift:55-71` | Never instantiated |
| `BoringStatusMenu` | `menu/StatusBarMenu.swift:3-24` | Never instantiated |
| `LiveActivityModifier` | `components/Live activities/LiveActivityModifier.swift:10-43` | Never referenced |
| `DownloadView` / `DownloadWatcher` | `components/Live activities/DownloadView.swift:16-52` | Never referenced |
| `proFeatureBadge` / `comingSoonTag` / `warningBadge` | `SettingsView.swift:1755-1801` | Unused or only in commented code |
| "Change media with horizontal gestures" | `SettingsView.swift:293-294` | Disabled placeholder |
| App icon picker | `SettingsView.swift:1577-1619` | Disabled placeholder |
| Updater controls | `SoftwareUpdater.swift:21-62` | Disabled placeholders |

---

## 14. Duplicated controls and authoritative implementations

| Duplication | Locations | Authoritative implementation to keep |
| --- | --- | --- |
| Battery settings | Host `Charge` (`SettingsView.swift:356-388`) and package `BatterySettingsView` (`BatteryViews.swift:335-378`) write the same four keys | Package `BatterySettingsView`. Host `Charge` is removed only **after** settings access is decoupled from activation (see corrected first slice) |
| Shelf settings page | Sidebar case `SettingsView.swift:90-91` and extension settings destination `BuiltInExtensions.swift:125-135` render the same `Shelf()` view over the same keys | One route. Prefer the Extensions destination; remove the sidebar entry only after the activation-independent access exists |
| Shelf enablement | `Defaults[.boringShelf]` toggle (`SettingsView.swift:936`) and extension-state toggle (`ExtensionsSettingsView.swift:72-81,133`) are independent and never synchronize | A single source of truth. Agent B owns the decision; today `boringShelf` gates UI and the extension state gates contributions |
| `mirrorShape` | Unused `@Default` `GeneralSettings:142` and used `Appearance:1168` | Appearance declaration; delete the unused one |
| `enableLyrics` | Unused `@Default` `Media:608` and `Defaults.Toggle` `:688` | The `Defaults.Toggle`; delete the unused declaration |
| Music appearance controls | Media page (`SettingsView.swift:600-714`) vs Appearance "Media" section (`:1193-1209`) and visualizer section (`:1247-1383`) | All Media-owned; consolidate under Extensions / Media |

## 15. Settings that need permission status, configuration data, or providers

| Setting surface | Data read | Whether it requests permission or starts a service |
| --- | --- | --- |
| Calendar & Reminders (`CalendarSettings.onAppear` `:815-820`) | `calendarAuthorizationStatus`, `reminderAuthorizationStatus`, `eventCalendars`, `reminderLists` | **Requests permission**: `checkCalendarAuthorization`/`checkReminderAuthorization` call `requestAccess` when status is `.notDetermined` (`CalendarManager.swift:74-79,111-116`). Rendering the page can raise TCC prompts |
| HUD | Accessibility authorization | **Reads** via `.task` (`:583-585`); **starts polling** via `startMonitoringAccessibilityAuthorization` (`:587`); the button **requests** (`:508`) |
| Battery (host `Charge`) | Accessibility authorization | Reads only (`:380-384`) |
| Shelf | Discovered share providers | **Starts discovery**: `Shelf.init` (`:929-931`) and `QuickShareService.init` (`QuickShareService.swift:29-33`) enumerate `NSSharingService`s |
| Camera Mirror | Device presence | Reads only (`checkVideoInput` `:1409-1415`); permission is requested on first tap (`WebcamView.swift:83-89`) or onboarding |
| Media | `MusicManager.shared.isNowPlayingDeprecated` | Reads a property; the manager's own async deprecation task runs independently |

Reading permission status is not the same as requesting it or starting a feature
service. The Calendar page currently does all three.

## 16. Services or singletons instantiated merely by rendering a settings page

| Settings page | Instantiated by rendering | What the initializer does |
| --- | --- | --- |
| Calendar & Reminders | `CalendarManager.shared` (`SettingsView.swift:717`) | Loads EventKit calendars/reminders and installs the `.EKEventStoreChanged` observer (`CalendarManager.swift:31-37,45-55`) |
| Shelf | `QuickShareService.shared` (`SettingsView.swift:923`) | Enumerates share services in `init` and in `Shelf.init` (`QuickShareService.swift:29-33`; `SettingsView.swift:929-931`) |
| Media | `MusicManager.shared` (e.g. `:627,708`), `MusicSlotConfigurationView` observes it (`:14`) | Central media singleton; async deprecation check on first access (`MusicManager.swift:72-93`) |
| HUD / Battery | `XPCHelperClient.shared` | Starts accessibility polling in HUD `.onAppear`; XPC helper client |
| About | `SPUStandardUpdaterController` fallback when none was injected (`SettingsView.swift:99-107`, `startingUpdater: false`) | Constructs an updater controller |
| Appearance | `LottieView` previews for `customVisualizers` (`:1251-1255`) | Loads Lottie JSON from the stored URL (remote fetch) |
| General / Appearance / Advanced | `BoringViewCoordinator.shared` | Shared coordinator; performs display migration in `init` (`BoringViewCoordinator.swift:105-177`) |

Rendering the Calendar and Shelf pages has the largest unintended
service-start side effects.

## 17. Corrections

- `calendarSelectionState` was previously classified inconsistently. It is
  **surfaced and used**: the per-calendar and per-reminder-list toggles
  (`SettingsView.swift:756-772,792-808`) read it through `CalendarManager`, and
  `CalendarManager.setCalendarSelected` rewrites it (`CalendarManager.swift:151-172`).
  It is not an unsurfaced key.
- `autoScrollToNextEvent` is **surfaced but inert**, not unsurfaced.
- `useMusicVisualizer` is surfaced but permanently disabled, not working.
- `musicControlSlotLimit` is unsurfaced even though the player reads it; the
  slot editor hardcodes 5 and never writes it.
- `showPowerStatusNotifications`/`showBatteryIndicator`/`showBatteryPercentage`/
  `showPowerStatusIcons` each have two controls; see section 14.
- The unused `@Default` declarations for `mirrorShape` (`GeneralSettings:142`)
  and `enableLyrics` (`Media:608`) are duplicates, not separate settings.

## 18. Branding

The Settings window title `"Boring Notch Settings"` (`SettingsWindowController.swift:43`)
and the identifier `BoringNotchSettingsWindow` (`:58`) are a branding omission to
fix. The About page's historical attribution and copyright must be preserved;
do not remove attribution while correcting the product name.

## 19. Integration-report findings: concrete relevance here

These were reported externally. Only their bearing on this inventory is recorded.

| Reported finding | Relevance to this inventory |
| --- | --- |
| A superseded activation can overwrite `BatteryMonitor.onChange` while a live owner exists (latent because Battery activation does not suspend) | The Battery enable/disable switch in the Extensions hub is the user-facing trigger surface. Battery settings must remain reachable independent of activation so a lifecycle race cannot strand the user without a settings route |
| `ExtensionManager` lacks main-actor isolation | The hub enable binding calls `manager.isEnabled`/`host.setEnabled` from SwiftUI (`ExtensionsSettingsView.swift:72-81`). Any consolidation that adds settings-side enable/disable calls inherits this |
| Migration recovery/testing gaps | New settings keys introduced by consolidation will not be migrated from the legacy namespace unless added to `IdentityMigration` (`IdentityMigrationCoordinator.swift:81-116`). Preserve existing raw keys |
| Migrated Sparkle defaults could affect a future updater | The About/update surface reads no Sparkle setting today; migration copies legacy defaults wholesale |
| Validator range grammar and `apiVersion` compatibility gaps | Any new extension settings-destination metadata must pass `NotchExtensions/validation`; do not rely on it as an install gate |
| CI runner/Xcode and invalid-fixture exit-code handling | Documentation-only change here. The verification baseline below is the reported one; no workflow is modified |

## 20. Corrected first implementation slice

The earlier suggestion to remove the host Battery page while its replacement
disappears on disablement is rejected. `ExtensionSettingsDestination.makeView` is
produced by the **active instance** and installed only after `activate()`
(`ExtensionHost.swift:230-236`), so disabling Battery removes `BatterySettingsView`
from the hub. Removing `Charge` then would strand the user with no Battery
settings page.

Corrected sequence:

1. Establish settings access independent of activation, so a destination can be
   listed and opened even when its extension is disabled.
2. Then consolidate Battery to the package-owned `BatterySettingsView` and remove
   the host `Charge` page.

Until step 1 exists, keep the host Battery page. Do not describe any of this as
completing extraction: Battery is the only extracted feature; Calendar, Shelf,
Media, HUD, and Camera Mirror remain core.

Open decisions for Agent B:

1. Whether settings destinations are metadata-declared (listable when disabled)
   or remain instance-produced.
2. The single source of truth for Shelf enablement (`boringShelf` vs extension
   state), without renaming persisted keys.
3. How not-yet-extracted features (Calendar, HUD, Media) surface under
   Extensions without deleting their sidebar entries before an equivalent
   destination exists.
4. A tab-routing API for `SettingsView` so the hub and onboarding can deep-link.
5. Whether `NotchPermission` gains calendar/reminders, or Calendar waits.

## 21. Verification baseline (reported)

At this development base: SDK/runtime 100 tests, Battery 16 tests, validation 5
tests; the default `NotchKit` target and the battery-free `NotchKitCoreOnly`
target build. GUI behaviour was not established by that report and remains a
manual check, especially for Battery presentation, Calendar permission prompts,
Shelf drag-disable behaviour, and HUD accessibility gating.
