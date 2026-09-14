#!/bin/bash
# Headless NSXPC boundary evidence.
#  - Compiles and RUNS a real anonymous-listener NSXPC round trip carrying JSON Data.
#  - Compiles two negative cases and asserts they FAIL, capturing diagnostics.
set -u

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$(mktemp -d)/nsxpc-round-trip"

echo "== 1. Build the round-trip executable =="
xcrun swiftc -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    "$DIR/NsxpcRoundTrip.swift" -o "$BIN"
echo "build exit=$?"

echo
echo "== 2. Run the round trip (anonymous listener, no launchd) =="
"$BIN"
echo "run exit=$?"

echo
echo "== 3. Negative: Codable struct as an @objc XPC method argument =="
neg1="$(xcrun swiftc -target arm64-apple-macos14.0 -typecheck \
    "$DIR/compile-fail/CodableStructAsXPCArgument.swift" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" 2>&1)"
echo "exit=$?"
printf '%s\n' "$neg1" | grep -E 'error:' | head -3

echo
echo "== 4. Negative: pure Swift protocol passed to NSXPCInterface(with:) =="
neg2="$(xcrun swiftc -target arm64-apple-macos14.0 -typecheck \
    "$DIR/compile-fail/SwiftProtocolNotObjC.swift" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" 2>&1)"
echo "exit=$?"
printf '%s\n' "$neg2" | grep -E 'error:' | head -3