#!/bin/bash
# Compile-verify symbol availability against specific macOS deployment targets.
# Headless: runs `swiftc -typecheck` only; no signing, no GUI, no execution.
#
# Usage: ./run-availability.sh
set -u

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$(xcrun --show-sdk-path --sdk macosx)"
DIR="$(cd "$(dirname "$0")" && pwd)"
SNIPPETS="$DIR/snippets"
LOGS="$DIR/logs"
OUT="$DIR/availability-results.tsv"

mkdir -p "$LOGS"
: > "$OUT"

printf 'snippet\tmacos14_exit\tmacos26_exit\tmacos14_first_error\n' >> "$OUT"

for f in "$SNIPPETS"/*.swift; do
    name="$(basename "$f")"
    stem="${name%.swift}"

    d14="$(xcrun swiftc -target arm64-apple-macos14.0 -typecheck "$f" -sdk "$SDK" 2>&1)"
    c14=$?
    d26="$(xcrun swiftc -target arm64-apple-macos26.0 -typecheck "$f" -sdk "$SDK" 2>&1)"
    c26=$?

    printf '%s\n' "$d14" > "$LOGS/$stem.macos14.log"
    printf '%s\n' "$d26" > "$LOGS/$stem.macos26.log"

    first="$(printf '%s\n' "$d14" | grep -E 'error:' | head -1 | sed 's/\t/ /g')"
    printf '%s\t%s\t%s\t%s\n' "$name" "$c14" "$c26" "$first" >> "$OUT"
done

column -t -s $'\t' "$OUT" 2>/dev/null || cat "$OUT"
echo
echo "Full diagnostics: $LOGS"
echo "TSV: $OUT"