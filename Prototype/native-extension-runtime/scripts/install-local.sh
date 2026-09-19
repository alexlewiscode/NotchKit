#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
PACKAGE_ROOT="${1:-${TMPDIR%/}/NotchKitNativeExtensionPackages/Pomodoro.notchkitextension}"
INSTALL_ROOT="$HOME/Applications/NotchKit Extensions"
INSTALL_PATH="$INSTALL_ROOT/provider.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    /usr/bin/xcrun swift run \
    --package-path "$ROOT" \
    notch-extension-package validate "$PACKAGE_ROOT"

/bin/mkdir -p "$INSTALL_ROOT"
/bin/rm -rf "$INSTALL_PATH"
/usr/bin/ditto "$PACKAGE_ROOT/payload/provider.app" "$INSTALL_PATH"
/usr/bin/codesign --verify --strict --deep "$INSTALL_PATH"
"$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
/usr/bin/open "$INSTALL_PATH"

print "INSTALLED $INSTALL_PATH"
