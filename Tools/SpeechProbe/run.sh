#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d)
xcrun swiftc -O -target arm64-apple-macos27.0 -parse-as-library -o "$OUT/probe" main.swift \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist 2>&1 | head -5
codesign -s - "$OUT/probe" 2>/dev/null
[ -x "$OUT/probe" ] || { echo "did not build"; exit 1; }
"$OUT/probe"
