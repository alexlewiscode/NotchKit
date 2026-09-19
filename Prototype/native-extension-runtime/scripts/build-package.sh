#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to an Apple development team identifier}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR%/}/NotchKitNativeExtensionDerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-${TMPDIR%/}/NotchKitNativeExtensionPackages}"
PACKAGE_ROOT="$OUTPUT_DIR/Pomodoro.notchkitextension"
PROVIDER_APP="$DERIVED_DATA/Build/Products/Debug/provider.app"

export DEVELOPER_DIR

/usr/bin/xcodebuild \
    -project "$ROOT/NativeExtensionPrototype.xcodeproj" \
    -scheme PomodoroProvider \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build

/usr/bin/codesign --verify --strict --deep "$PROVIDER_APP"

/bin/mkdir -p "$OUTPUT_DIR"
/bin/rm -rf "$PACKAGE_ROOT"
/bin/mkdir -p "$PACKAGE_ROOT/payload"
/usr/bin/ditto "$ROOT/Packaging/assets" "$PACKAGE_ROOT/assets"
/usr/bin/ditto "$ROOT/Packaging/localization" "$PACKAGE_ROOT/localization"
/usr/bin/ditto "$ROOT/Packaging/manifest.json" "$PACKAGE_ROOT/manifest.json"
/usr/bin/ditto "$PROVIDER_APP" "$PACKAGE_ROOT/payload/provider.app"

manifest_hash=$(/usr/bin/shasum -a 256 "$PACKAGE_ROOT/manifest.json" | /usr/bin/cut -d ' ' -f 1)
/usr/bin/printf '%s\n' \
    '{' \
    "  \"manifestSHA256\": \"$manifest_hash\"," \
    '  "providerBundleIdentifier": "com.notchkit.prototype.pomodoro.provider",' \
    '  "extensionBundleIdentifier": "com.notchkit.prototype.pomodoro.provider.extension",' \
    '  "verification": "apple-code-signature"' \
    '}' > "$PACKAGE_ROOT/signature.json"

DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun swift run \
    --package-path "$ROOT" \
    notch-extension-package validate "$PACKAGE_ROOT"

print "PACKAGE_READY $PACKAGE_ROOT"
