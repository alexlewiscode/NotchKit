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

For a Hub submission, build with signing disabled, select the marketplace
manifest, then sign both bundles with your Apple Development identity. This
keeps the notarization/Developer ID requirement out of the local submission
path:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Pomodoro.xcodeproj \
  -scheme PomodoroProvider \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/build/HubDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  NOTCHKIT_MARKETPLACE_BUILD=YES \
  build

IDENTITY_SHA='REPLACE_WITH_THE_SHA_FROM_SECURITY_FIND_IDENTITY'
PROVIDER_APP="$PWD/build/HubDerivedData/Build/Products/Release/provider.app"
EXTENSION="$PROVIDER_APP/Contents/Extensions/extension.appex"
codesign --force --sign "$IDENTITY_SHA" --options runtime --timestamp=none \
  --entitlements Configuration/PomodoroExtension.entitlements "$EXTENSION"
codesign --force --sign "$IDENTITY_SHA" --options runtime --timestamp=none \
  --entitlements Configuration/PomodoroProvider.entitlements "$PROVIDER_APP"
codesign --verify --deep --strict "$PROVIDER_APP"

swift run --package-path ../../LocalRuntime notchkit-extension package \
  "$PROVIDER_APP" \
  --output "$PWD/build/Pomodoro-marketplace.notchkitextension" \
  --marketplace
```

`--marketplace` validates `metadata.source = marketplace` and keeps the
embedded and outer manifests byte-identical. Apple Development signatures can
be submitted for manual review; the Hub does not require notarization or a
stapled ticket. Before requesting the NotchKit Team badge, verify that the
signed bundle's `TeamIdentifier` exactly matches the Hub's configured
`NOTCHKIT_TEAM_ID`.

The fallback archive contains exactly:

```text
manifest.json
payload/provider.app
```

The provider and extension use App Sandbox and hardened runtime. The extension binds to host `com.notchkit.app`, extension-point name `native-ui`, and accepts both process XPC connections and remote-scene XPC connections.
