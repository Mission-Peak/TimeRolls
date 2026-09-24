#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d)
xcrun swiftc -O -target arm64-apple-macos27.0 -o "$OUT/probe" main.swift || exit 1
"$OUT/probe" "$(cd ../.. && pwd)"
