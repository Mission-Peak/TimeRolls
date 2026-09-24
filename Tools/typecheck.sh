#!/bin/bash
# Type-check every Swift file in the app, without building or signing anything.
#
# This exists because the curation harness compiles only a handful of files and so cannot
# tell you the app is broken. Removing an enum case leaves `switch` statements in the
# engine and the views that no longer compile, and nothing noticed until xcodebuild ran.
#
# Type-checking is a fraction of the cost of a build: no optimiser, no linking, no code
# signing, no device. It catches exactly the class of error a harness cannot.
set -uo pipefail
cd "$(dirname "$0")/.."
SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null) || {
    echo "  no iOS SDK found — skipping the typecheck"; exit 0; }
# Every file, plus a stand-in for the class Xcode generates from the .mlpackage — that
# class does not exist for a bare compiler invocation, and leaving its file out only moves
# the errors to whatever refers to it.
FILES="$(find TimeRolls -name '*.swift' -not -path '*/Packs/*') Tools/TypecheckShims/PhotoThemes.swift"
OUT=$(xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios26.0 \
      -swift-version 5 -default-isolation MainActor $FILES 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo "$OUT" | grep -E "error:" | sed 's/^/  /' | head -20
    exit 1
fi
echo "  $(echo "$FILES" | wc -l | tr -d ' ') files, no errors"
