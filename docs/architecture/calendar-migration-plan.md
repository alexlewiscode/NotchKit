# Calendar migration plan

Status: proposed. Not implemented. This follows the Battery extraction and reuses
its lifecycle pattern.

## Current Calendar dependencies (audit)

| Concern | Location |
| --- | --- |
| Views | `NotchKit/NotchKit/components/Calendar/BoringCalendar.swift` (`CalendarView`, `EventListView`, `ReminderToggle`, `WheelPicker`) |
| Data/observer | `NotchKit/NotchKit/managers/CalendarManager.swift` (singleton, `EKEventStoreChanged` observer, side effects in `init`) |
| Model | `NotchKit/NotchKit/models/{EventModel,CalendarModel}.swift` |
| Provider | `NotchKit/NotchKit/Providers/CalendarServiceProviding.swift` (`EKEventStore`) |
| Open-notch embedding | `NotchHomeView.swift` — `if Defaults[.showCalendar] { CalendarView() }`; sets `vm.isHoveringCalendar` |
| Settings | `SettingsView.swift` `CalendarSettings` |
| Settings keys | `showCalendar` (default false), `hideCompletedReminders`, `hideAllDayEvents`, `showFullEventTitles`, `autoScrollToNextEvent` |
| Permissions | `Info.plist` `NSCalendarsUsageDescription`, `NSRemindersUsageDescription`; onboarding `CalendarService()` |

Calendar has no closed-notch contribution and no `SneakContentType`
integration, so it is simpler than Battery in presentation terms but needs a
data/permission capability that Battery did not.

## Proposed package

`NotchExtensions/FirstParty/Calendar`:

- `CalendarMonitor` (app-wide) owning `EKEventStore` + the
  `EKEventStoreChanged` observer, with explicit `start()`/`stop()`.
- `CalendarExtension: NotchExtension` — `activate()` starts the monitor and
  registers teardown; `deactivate()` stops it and leaves no observer.
- Metadata: id `com.notchkit.calendar`, capabilities
  `.openDestination`/`.settingsDestination`, `defaultEnabled: false`,
  `artifactKind: .compiledIn`.
- Settings destination rendering the migrated `CalendarSettings`.
- Reuse the existing UserDefaults keys so preferences are preserved.

## SDK gaps to resolve first

1. **Calendar permission.** `NotchPermission` currently exposes accessibility,
   mediaControl, camera, and screenRecording. EventKit needs calendar and
   reminders. Smallest change: add `.calendar`/`.reminders` cases and map them in
   `HostPermissionService`.
2. **Attachment point.** Calendar is embedded inside Home, not a tab. Decide
   between (a) a new `homeWidget` entry point kind rendered by Home, or
   (b) promoting Calendar to an open destination. This is a contract decision
   requiring Agent 2; do not invent it during implementation.
3. **Host hover state.** `BoringViewModel.isHoveringCalendar` is host-owned.
   Either expose it through a narrow service or replace it with a
   contribution-provided signal.

## Steps

1. Resolve the SDK gaps above and agree the attachment point.
2. Create the package and move views/model/provider, mirroring Battery.
3. Register the definition in `BuiltInExtensions`/`NotchKitRuntime` and gate on
   enablement.
4. Move `CalendarSettings` to a settings destination; keep the same keys.
5. Add a `CoreOnly` exclusion and tests (enable/disable/re-enable, observer
   teardown, stale events, preference preservation, permission handling).
6. Manual GUI checks: calendar rendering, reminders, permission prompts,
   multiple displays.

## Risks

- EventKit permission prompts and entitlements may need a GUI session to verify.
- `EKEventStoreChanged` can fire while deactivated; the generation/cancellation
  pattern must drop stale callbacks.
- Moving Home's inline calendar changes layout; preserve visuals exactly or
  scope as a deliberate redesign.