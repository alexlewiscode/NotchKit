#!/bin/bash
# Attempt to build the smallest bundled app with an embedded XPC service,
# ad-hoc sign it, and connect to the service headlessly.
set -u

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET=arm64-apple-macos14.0
DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP="$BUILD/NotchKitPrototypeHost.app"
XPC="$APP/Contents/XPCServices/com.notchkit.prototype.xpcservice.xpc"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$XPC/Contents/MacOS"
cp "$DIR/HostInfo.plist" "$APP/Contents/Info.plist"
cp "$DIR/ServiceInfo.plist" "$XPC/Contents/Info.plist"

echo "== Build service executable =="
xcrun swiftc -target "$TARGET" -sdk "$SDK" \
    "$DIR/EchoServiceProtocol.swift" "$DIR/Service.swift" "$DIR/ServiceMain.swift" \
    -o "$XPC/Contents/MacOS/NotchKitPrototypeXPC"
echo "service build exit=$?"

echo "== Build host executable =="
xcrun swiftc -target "$TARGET" -sdk "$SDK" \
    "$DIR/EchoServiceProtocol.swift" "$DIR/HostMain.swift" \
    -o "$APP/Contents/MacOS/NotchKitPrototypeHost"
echo "host build exit=$?"

echo "== Build lifecycle host executable =="
xcrun swiftc -target "$TARGET" -sdk "$SDK" \
    "$DIR/EchoServiceProtocol.swift" "$DIR/LifecycleHost.swift" \
    -o "$APP/Contents/MacOS/NotchKitPrototypeLifecycleHost"
echo "lifecycle host build exit=$?"

echo "== Ad-hoc sign (deep) =="
codesign --force --deep --sign - "$APP" 2>&1
echo "codesign exit=$?"
codesign -dv --verbose=2 "$XPC" 2>&1 | head -8

echo "== Bundle layout =="
find "$APP" -type f

echo
echo "== Attempt headless connection (direct exec of host binary) =="
"$APP/Contents/MacOS/NotchKitPrototypeHost"
echo "host run exit=$?"

echo
echo "== Lifecycle observability (launch pid, crash -> interruption, invalidate) =="
"$APP/Contents/MacOS/NotchKitPrototypeLifecycleHost"
echo "lifecycle run exit=$?"

echo
echo "== Attempt headless connection via LaunchServices (open -W) =="
OPEN_OUT="$DIR/open.out"
OPEN_ERR="$DIR/open.err"
rm -f "$OPEN_OUT" "$OPEN_ERR"
open -W -n "$APP" --stdout "$OPEN_OUT" --stderr "$OPEN_ERR" 2>&1
echo "open exit=$?"
echo "--- app stdout ---"
cat "$OPEN_OUT" 2>/dev/null
echo "--- app stderr ---"
cat "$OPEN_ERR" 2>/dev/null