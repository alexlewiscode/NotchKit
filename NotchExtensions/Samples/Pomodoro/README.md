# Pomodoro Extension Sample

A standalone macOS 26 ExtensionKit provider for NotchKit. The sample includes:

- A polished SwiftUI remote scene named `main`.
- Host-rendered declarative open-notch (`compact`) and closed-notch (`closed`) entry points.
- A bounded `NotchExtensionServiceProtocol` service with handshake, render, and stateful start/pause/reset actions.
- A user-initiated `open-destination` host action from the closed-notch **Open** button.
- A schema-v2 manifest embedded in the signed provider at `Contents/Resources/NotchKitExtension/manifest.json`.

## Requirements

- macOS 26 and Xcode 26.
- An Apple development team capable of signing a sandboxed provider and ExtensionKit extension.
- The local SDK package at `../../../NotchKit/Packages/NotchExtensionSDK`.

## Build

The project intentionally contains no `DEVELOPMENT_TEAM`. Supply one as a command-line override:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
xcodebuild -project Pomodoro.xcodeproj \
  -scheme PomodoroProvider \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## Package

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./build-package.sh
```

The output defaults to `build/Pomodoro.notchkitextension`. Set `OUTPUT_DIR` and `DERIVED_DATA` to override their locations. If `NOTCH_EXTENSION_PACKAGE_CLI` points to an executable, or `notch-extension-package` is installed, the script invokes that production packager. Otherwise it uses macOS `ditto` to make a temporary ZIP-compatible archive while preserving executable modes and the signed bundle contents.

The fallback archive contains exactly:

```text
manifest.json
payload/provider.app
```

The provider and extension use App Sandbox and hardened runtime. The extension binds to host `com.notchkit.app`, extension-point name `native-ui`, and accepts both process XPC connections and remote-scene XPC connections.
