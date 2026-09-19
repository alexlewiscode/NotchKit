#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to an Apple development team identifier}"

DERIVED_DATA="${DERIVED_DATA:-${TMPDIR%/}/NotchKitPomodoroDerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
PROVIDER_APP="$DERIVED_DATA/Build/Products/Release/provider.app"
EMBEDDED_MANIFEST="$PROVIDER_APP/Contents/Resources/NotchKitExtension/manifest.json"
ARCHIVE="$OUTPUT_DIR/Pomodoro.notchkitextension"

export DEVELOPER_DIR

/usr/bin/xcodebuild \
    -project "$ROOT/Pomodoro.xcodeproj" \
    -scheme PomodoroProvider \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build

/usr/bin/codesign --verify --strict --deep --verbose=2 "$PROVIDER_APP"
/usr/bin/cmp "$ROOT/Resources/NotchKitExtension/manifest.json" "$EMBEDDED_MANIFEST"

/bin/mkdir -p "$OUTPUT_DIR"
/bin/rm -f "$ARCHIVE"

if [[ -n "${NOTCH_EXTENSION_PACKAGE_CLI:-}" && -x "$NOTCH_EXTENSION_PACKAGE_CLI" ]]; then
    "$NOTCH_EXTENSION_PACKAGE_CLI" package "$PROVIDER_APP" --output "$ARCHIVE"
else
    swift run \
        --package-path "$ROOT/../../LocalRuntime" \
        notchkit-extension \
        package "$PROVIDER_APP" \
        --output "$ARCHIVE"
fi

if [[ -n "${NOTCH_EXTENSION_PACKAGE_CLI:-}" && -x "$NOTCH_EXTENSION_PACKAGE_CLI" ]]; then
    "$NOTCH_EXTENSION_PACKAGE_CLI" validate "$ARCHIVE"
else
    swift run \
        --package-path "$ROOT/../../LocalRuntime" \
        notchkit-extension \
        validate "$ARCHIVE"
fi

print "PACKAGE_READY $ARCHIVE"
