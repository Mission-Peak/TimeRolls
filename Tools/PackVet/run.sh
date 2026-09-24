#!/bin/bash
# Describes every photograph in a pack and flags the ones that don't match their own title.
set -uo pipefail
cd "$(dirname "$0")"
PACK="${1:-travel-landmarks}"
LIMIT="${2:-}"
OUT=$(mktemp -d)
xcrun swiftc -O -target arm64-apple-macos27.0 -o "$OUT/packvet" main.swift || exit 1
"$OUT/packvet" "$(cd ../.. && pwd)" "$PACK" $LIMIT
