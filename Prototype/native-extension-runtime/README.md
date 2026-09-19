# Native Extension Runtime Prototype

This standalone macOS 26 prototype proves a Tier B extension can be installed
outside NotchKit, enabled through the system ExtensionKit UI, and rendered as
opaque remote SwiftUI in a separate process. It does not modify or link into the
production macOS 14 runtime.

## Components

- `NativeExtensionHost`: declares the custom `native-ui` extension point,
  monitors enabled extensions, presents the system extension browser, and hosts
  remote scenes with `EXHostViewController`.
- `PomodoroProvider`: independently installed containing app.
- `PomodoroExtension`: ExtensionKit extension that owns the Pomodoro SwiftUI
  scene and exports the bounded XPC handshake service.
- `NativeExtensionShared`: package manifest, package validation, lifecycle, and
  XPC protocol contracts.
- `notch-extension-package`: command-line validator for extracted
  `.notchkitextension` packages.

## Requirements

- macOS 26 or newer
- Xcode 26 with the macOS 26 SDK
- An Apple development team configured through `DEVELOPMENT_TEAM` or Xcode

No team identifier or signing certificate is stored in this project.

## Build And Test

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPMENT_TEAM=<your-team-id>

swift test
scripts/build-package.sh

xcodebuild \
  -project NativeExtensionPrototype.xcodeproj \
  -scheme NativeExtensionHost \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build
```

`scripts/build-package.sh` prints the generated package path. By default it is
an extracted directory named `Pomodoro.notchkitextension` under the temporary
directory.

## Install And Exercise

```sh
scripts/install-local.sh /path/to/Pomodoro.notchkitextension
open /path/to/NativeExtensionHost.app
```

In the host:

1. Open **Manage System Extensions**.
2. Enable **Pomodoro Focus** and dismiss the system sheet.
3. Confirm the timer renders and the status becomes **Active**.
4. Use **Crash Extension** to verify the extension exits while the host stays
   alive.
5. Relaunch the host to establish a new scene and XPC connection.
6. Disable the extension to verify immediate remote-view teardown.

Clean up with:

```sh
scripts/uninstall-local.sh
```

## Package Contract

```text
Pomodoro.notchkitextension/
  manifest.json
  signature.json
  payload/
    provider.app/
      Contents/Extensions/extension.appex
  assets/
  localization/
```

Validation checks manifest structure, supported platform and protocol versions,
bundle containment and identifiers, the manifest SHA-256 recorded in
`signature.json`, and Apple code signatures for the provider and nested
extension. The SHA-256 field detects manifest substitution inside the extracted
package; publisher authenticity comes from Apple code signing.

## Current Limits

- The package is an extracted directory, not a compressed transport archive.
- Apple Development signing was exercised. Developer ID distribution,
  notarization, and Gatekeeper installation remain unverified.
- The prototype has no download, catalog, update, or production-host
  integration.
- Automatic same-window recovery after a crash is not implemented; a fresh host
  scene establishes a new connection.
