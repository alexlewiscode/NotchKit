#!/bin/zsh

set -euo pipefail

HOST_APP="${1:-${TMPDIR%/}/NotchKitNativeExtensionHostDerivedData/Build/Products/Debug/NativeExtensionHost.app}"
PROVIDER_APP="${2:-${TMPDIR%/}/NotchKitNativeExtensionDerivedData/Build/Products/Debug/provider.app}"
EXTENSION_APP="$PROVIDER_APP/Contents/Extensions/extension.appex"

for product in "$HOST_APP" "$PROVIDER_APP" "$EXTENSION_APP"; do
    /usr/bin/codesign --verify --strict "$product"
    /usr/bin/codesign -d --entitlements :- "$product" >/dev/null
done

test -f "$HOST_APP/Contents/Extensions/NativeExtensionHost.appexpt"
test -f "$EXTENSION_APP/Contents/Info.plist"

print "VERIFIED host-extension-point provider nested-extension signatures"
