#!/bin/zsh

set -euo pipefail

INSTALL_PATH="$HOME/Applications/NotchKit Extensions/provider.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$INSTALL_PATH" ]]; then
    print "NOT_INSTALLED $INSTALL_PATH"
    exit 0
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_PATH/Contents/Info.plist")
if [[ "$bundle_id" != "com.notchkit.prototype.pomodoro.provider" ]]; then
    print -u2 "Refusing to remove unexpected bundle: $bundle_id"
    exit 1
fi

"$LSREGISTER" -u "$INSTALL_PATH" || true
/usr/bin/pkill -f "$INSTALL_PATH/Contents/Extensions/extension.appex/Contents/MacOS/extension" || true
/usr/bin/pkill -f "$INSTALL_PATH/Contents/MacOS/provider" || true
/bin/rm -rf "$INSTALL_PATH"
print "UNINSTALLED $INSTALL_PATH"
