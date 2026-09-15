# Battery extraction (first-party extension)

Status: implemented on `feature/first-party-battery`. Base:
`54cb5fae217b42a56e882d9353a4e2ada68c20c7`.

This document separates what is implemented, what is tested, and what is only
proposed. Battery is the first built-in feature migrated to a fully managed
first-party extension.

## What moved

| Concern | Before | After |
| --- | --- | --- |
| Power observation | `NotchKit/managers/BatteryActivityManager.swift` (singleton, starts in `init`, no stop path) | `NotchExtensions/FirstParty/Battery/Sources/BatteryExtension/PowerSourceObserving.swift` (`IOKitPowerSource`, explicit `start`/`stop`) |
| App-wide state | `NotchKit/models/BatteryStatusViewModel.swift` (singleton) | `BatteryMonitor` (app-wide, one active observer, idempotent `start`) |
| Visuals | `BoringBattery.swift` + host `BatteryNotificationContent` | `BatteryViews.swift` in the package |
| Closed-notch contribution | hardcoded in `BuiltInClosedNotch.battery()` | `BatteryExtension.closedNotchContributions()` published through `ContributionStore` |
| Settings | host-only `SettingsView.Charge` | package `BatterySettingsView` as a settings destination; same UserDefaults keys |
| Identity | `BuiltInExtensionIDs.batteryContribution` only | `com.notchkit.battery` metadata + `manifest.json` |

The host keeps the open-notch header indicator, but it now observes the same
app-wide `BatteryMonitor` and is hidden when the extension is disabled.

## Lifecycle and disablement

- `activate()` starts the monitor and registers a teardown block.
- `deactivate()` clears the change callback, stops the monitor, and cancels the
  teardown bag.
- Contributions and settings pages are produced only while active, so a
  disabled extension contributes nothing to `ContributionStore`.
- Presentation is requested through the SDK with `PresentationTarget.active`;
  core (`HostPresentationService`) decides how to present it. Adding a display
  never starts another observer because the monitor is app-wide.

## SDK change (additive)

`NotchExtensionSDK` gained `NotchGeometry` and `EnvironmentValues.notchGeometry`.
This is a generic, read-only geometry value that any closed-notch contribution
view needs; core sets it immediately before rendering. It is additive and does
not change existing initializers. It requires Agent 2's review before merge.

Battery does **not** require a new power host service: it owns IOKit directly.
If first-party policy later forbids extensions reading system power state, the
smallest follow-up is a `NotchPowerService` on `ExtensionContext` exposing a
`BatterySnapshot` and an observer token; that is **proposed, not implemented**.

## Core-only build (Battery-free)

`NotchKitCoreOnly` is a separate app target and scheme that shares the same
source files as `NotchKit` but does **not** declare the `BatteryExtension`
package product dependency. Under `NOTCHKIT_CORE_ONLY`, the host does not
import, register, or instantiate Battery: no monitor is created, the header
indicator is absent, and the Battery settings pane is not built.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKitCoreOnly \
  -configuration Debug -destination 'generic/platform=macOS' build
```

Verified on this branch (Debug and Release): the core-only link file list
contains no `BatteryExtension.o`, the app binary contains zero
`BatteryExtension` symbols and no `com.notchkit.battery` registration strings,
and the bundle packages no Battery resources. The default `NotchKit` target
still links and registers Battery (992 `BatteryExtension` symbols).

"Core-only" means **without Battery** in this milestone. Other features
(Calendar, Shelf, HUD, Media) have not yet been extracted and are still part of
core.

The earlier `CoreOnly` build configuration was removed: it only excluded code
paths while still linking the Battery package, which did not meet the absence
criterion.

## Verification

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift test --package-path NotchKit/Packages/NotchExtensionSDK   # 100 tests
xcrun swift test --package-path NotchExtensions/FirstParty/Battery    # 16 tests
xcrun swift test --package-path NotchExtensions/validation            # 5 tests
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKit \
  -configuration Debug -destination 'generic/platform=macOS' build             # succeeds
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKitCoreOnly \
  -configuration Debug -destination 'generic/platform=macOS' build             # succeeds
```

The Battery tests cover activation, disablement, re-enable, idempotent partial
activation, stale events after deactivation, preference preservation,
display-aware presentation, and contribution gating. The runtime tests add
deterministic shared-service ownership coverage (rapid toggles, superseded
deactivation, superseded activation whose replacement fails, disable during a
delayed activation, prompt contribution withdrawal, and removal mid-transition).

## Runtime race fixed in the integration branch

1. **Additive SDK change:** `NotchGeometry` / `notchGeometry` (see above).
2. **Runtime race (fixed).** `beginDeactivation` previously ran
   `instance.deactivate()` and `bag.cancelAll()` before its generation guard,
   and `beginActivation` replaced `tasks[id]` without cancelling a pending
   deactivation. On a rapid disable→enable, a stale deactivation could call the
   previous instance's `deactivate()` after the new activation started, stopping
   the shared `BatteryMonitor`.
   The integration branch fixes the ownership ordering in `ExtensionHost`:
   `beginActivation` cancels the pending transition and owns teardown of the
   previous instance exactly once, `beginDeactivation` checks the generation
   before any teardown side effect, and a superseded late `activate()` is torn
   down whenever no live instance owns the service (disabled, removed,
   replacement failed, or shutdown). Deterministic tests cover each case.

## Not verified here

GUI checks still require a manual session: charging transitions, the battery
presentation, Battery settings, open/close behaviour, and multiple displays.
The package is compiled in; independent installation is not implemented.