#!/bin/bash
# Build Time Rolls and put it on every device plugged into this Mac.
#
#   ./Tools/install.sh            build, install everywhere, launch on each
#   ./Tools/install.sh --no-check skip the curation harness (faster, less safe)
#
# There is nothing clever here. It exists so that installing is one command rather than
# three remembered ones, and so the two failures that actually happen — a device that
# needs restarting after an Xcode upgrade, and a device too old for the build — say so
# in words instead of a CoreDevice error number.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE="com.missionpeak.timerolls"
BUILD_DIR="${TMPDIR:-/tmp}/timerolls-build"

# Does the whole app still compile?
#
# Before the harness, deliberately. The harness only compiles the curation layer — not the
# engine, not the views — so it can pass while the app does not build at all, and it did
# exactly that twice in one afternoon: a theme was removed from an enum and the leftover
# `case .occasions:` in GameEngine and CategoryPicker went unnoticed until xcodebuild ran
# six minutes later. A whole-app typecheck takes seconds and fails on the same errors, so
# it belongs first, where it costs nothing and saves the wait.
if [ "${1:-}" != "--no-check" ]; then
    echo "▸ checking the app compiles"
    if ! ./Tools/typecheck.sh; then
        echo "✗ the app does not compile — not installing"
        exit 1
    fi

    echo "▸ checking curation invariants"
    ./Tools/CurationHarness/run.sh || { echo "✗ harness failed — not installing"; exit 1; }
fi

echo "▸ building"
xcodebuild -project TimeRolls.xcodeproj -scheme TimeRolls -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates build > "$BUILD_DIR.log" 2>&1
if [ $? -ne 0 ]; then
    echo "✗ build failed:"
    grep -E "error:" "$BUILD_DIR.log" | head -10
    exit 1
fi
APP="$BUILD_DIR/Build/Products/Debug-iphoneos/TimeRolls.app"

# Device names have spaces in them, so ask for JSON rather than guessing at columns.
xcrun devicectl list devices --json-output "$BUILD_DIR.devices.json" > /dev/null 2>&1
DEVICES=$(python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    # "simulators" are also listed and also paired; only real hardware gets a build.
    if d.get("visibilityClass") != "default":
        continue
    props = d.get("deviceProperties", {})
    hardware = d.get("hardwareProperties", {})
    print("\t".join([d["identifier"],
                     props.get("name") or hardware.get("marketingName") or d["identifier"],
                     props.get("osVersionNumber", "?")]))
' "$BUILD_DIR.devices.json")
[ -z "$DEVICES" ] && { echo "✗ no devices connected"; exit 1; }

echo "$DEVICES" | while IFS=$'\t' read -r ID NAME OS; do
    printf "▸ %s (iOS %s)\n" "$NAME" "$OS"

    OUT=$(xcrun devicectl device install app --device "$ID" "$APP" 2>&1)
    if [ $? -ne 0 ]; then
        case "$OUT" in
            *"still locked"*|*"Unlock the device"*)
                echo "  ✗ unlock this device and run again" ;;
            *"developer disk image"*)
                echo "  ✗ restart this device and run again — Xcode is mid-swap of its"
                echo "    developer disk image, which happens after an Xcode upgrade" ;;
            *"disconnected"*)
                echo "  ✗ device dropped off — unlock it, trust this Mac, try again" ;;
            *)
                echo "$OUT" | grep -i error | head -3 | sed 's/^/  ✗ /' ;;
        esac
        continue
    fi
    xcrun devicectl device process launch --device "$ID" "$BUNDLE" > /dev/null 2>&1 \
        && echo "  ✓ installed and launched" \
        || echo "  ✓ installed (open it yourself — launching failed)"
done
