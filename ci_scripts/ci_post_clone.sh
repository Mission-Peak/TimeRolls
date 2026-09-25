#!/bin/bash
# Xcode Cloud runs this after checking out the code, before it builds.
#
# It writes TimeRolls/Secrets.xcconfig, which is git-ignored and so never arrives with the
# clone. Without it the build still succeeds — and the app quietly reads every pack
# photograph from its original Wikimedia address instead of from OneBucket. That fallback
# is what made the missing credentials invisible the first time, so this script refuses
# to let an archive through without them.
#
# The values come from secret environment variables set on the Xcode Cloud workflow in
# App Store Connect. Only the read-only `timerolls-readonly` pair belongs there — never
# the `timerolls` or `timerolls-upload` keys, which can write. Nothing here prints them.
set -euo pipefail

DEST="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}/TimeRolls/Secrets.xcconfig"
NAMES=(ONEBUCKET_HOST ONEBUCKET_NAME ONEBUCKET_REGION ONEBUCKET_ACCESS_KEY_ID ONEBUCKET_SECRET_ACCESS_KEY)

missing=()
for name in "${NAMES[@]}"; do
    [ -n "${!name:-}" ] || missing+=("$name")
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "OneBucket settings missing from this workflow's environment: ${missing[*]}"
    # A build or a test can go ahead without them. A build meant for people — an
    # archive, which is what reaches TestFlight — cannot, or it ships reading from
    # Wikimedia and nothing says so.
    if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
        echo "error: refusing to archive without OneBucket credentials."
        echo "Add them as secret environment variables on the Xcode Cloud workflow."
        exit 1
    fi
    echo "warning: pack photos in this build will come from their original source."
    exit 0
fi

# An xcconfig reads "//" as the start of a comment, and a secret key can contain one.
# "/$()/" is how an xcconfig spells two slashes without starting a comment.
escape() { printf '%s' "$1" | sed 's|//|/$()/|g'; }

{
    echo "// Written by ci_scripts/ci_post_clone.sh from the Xcode Cloud environment."
    for name in "${NAMES[@]}"; do
        echo "$name = $(escape "${!name}")"
    done
} > "$DEST"

echo "Wrote $(basename "$DEST") with ${#NAMES[@]} OneBucket settings."
