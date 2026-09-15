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

## Core-only build

A `CoreOnly` build configuration sets `NOTCHKIT_CORE_ONLY`, under which the host
does not import, register, or instantiate Battery, and does not create a monitor
or settings page.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKit \
  -configuration CoreOnly -destination 'platform=macOS' build
```

**Known limitation (not overclaimed):** Xcode/SwiftPM 5.9 cannot vary a package
product's linkage per build configuration, so the Battery package artifact is
still linked by the shared app target even though no code references it.
Removing the artifact from the core-only binary requires a separate app target
(or a SwiftPM feature flag). That is proposed future work; the current
configuration excludes Battery's registration, UI, and services at compile time,
which is stronger than hiding UI or toggling enablement, but it is not a
package-level exclusion.

## Verification

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift test --package-path NotchKit/Packages/NotchExtensionSDK   # 94 tests
xcrun swift test --package-path NotchExtensions/FirstParty/Battery    # 12 tests
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKit \
  -configuration Debug -destination 'platform=macOS' build             # succeeds
```

The 12 Battery tests cover activation, disablement, re-enable, idempotent
partial activation, stale events after deactivation, preference preservation,
display-aware presentation, and contribution gating.

## Not verified here

GUI checks still require a manual session: charging transitions, the battery
presentation, Battery settings, open/close behaviour, and multiple displays.
The package is compiled in; independent installation is not implemented.