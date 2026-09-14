#!/bin/bash
# Attempt to build a hand-authored ExtensionKit app extension (.appex) embedded
# in a host .app, ad-hoc sign it, and discover it headlessly.
# Expectation: discovery/enablement needs a real signing identity and/or GUI.
set -u

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET=arm64-apple-macos14.0
DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP="$BUILD/NotchKitPrototypeDiscoveryHost.app"
APPEX="$APP/Contents/PlugIns/com.notchkit.prototype.extension.appex"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
cp "$DIR/HostInfo.plist" "$APP/Contents/Info.plist"
cp "$DIR/ExtensionInfo.plist" "$APPEX/Contents/Info.plist"

echo "== Build extension executable (macOS 14 target) =="
xcrun swiftc -target "$TARGET" -sdk "$SDK" \
    -parse-as-library "$DIR/ExtensionMain.swift" \
    -o "$APPEX/Contents/MacOS/NotchKitProtoExtension"
echo "extension build exit=$?"

echo "== Build discovery host executable =="
xcrun swiftc -target "$TARGET" -sdk "$SDK" \
    -parse-as-library "$DIR/DiscoveryHost.swift" \
    -o "$APP/Contents/MacOS/DiscoveryHost"
echo "host build exit=$?"

echo "== Hand-authored extension point file (Contents/ExtensionPoints/) =="
mkdir -p "$APP/Contents/ExtensionPoints"
cp "$DIR/HostPoint.appexpt" "$APP/Contents/ExtensionPoints/com.notchkit.prototype.point.appexpt"
find "$APP/Contents/ExtensionPoints" -type f

echo "== Ad-hoc sign (deep) =="
codesign --force --deep --sign - "$APP" 2>&1
echo "codesign exit=$?"

echo "== Attempt headless discovery via direct exec =="
"$APP/Contents/MacOS/DiscoveryHost"
echo "direct exec exit=$?"

echo
echo "== Attempt headless discovery via LaunchServices (open -W) =="
OPEN_OUT="$DIR/open.out"; OPEN_ERR="$DIR/open.err"
rm -f "$OPEN_OUT" "$OPEN_ERR"
open -W -n "$APP" --stdout "$OPEN_OUT" --stderr "$OPEN_ERR" 2>&1
echo "open exit=$?"
echo "--- app stdout ---"; cat "$OPEN_OUT" 2>/dev/null
echo "--- app stderr ---"; cat "$OPEN_ERR" 2>/dev/null