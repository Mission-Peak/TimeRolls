#!/bin/bash
# Can anything on the device look at a photograph and answer a question about it yet?
#
# Most of the curation machinery exists because nothing can. A model that could be handed
# a photograph and asked "is there snow in this?" — and could answer no — would replace
# the null prompts, the concept floor and the outdoors test with one question in English.
# So this notices the day it arrives rather than us finding out months later.
#
# Two routes are watched, because Apple could take either:
#   1. Foundation Models learning to accept an image in a prompt.
#   2. Vision growing a request that describes or answers rather than classifies.
set -uo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
NAME=$(basename "${SDK:-no SDK}")
HERE=$(cd "$(dirname "$0")" && pwd)

# --- 1. Foundation Models: can a prompt carry anything but words?
MODELS="$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface"
if [ -f "$MODELS" ]; then
    HITS=$(grep -icE 'CGImage|CVPixelBuffer|UIImage|case image\(|ImageSegment|\.image\(|imageAttachment' "$MODELS")
    SEGMENTS=$(grep -A 4 'public enum Segment' "$MODELS" | grep -cE '^\s+case ')
    if [ "$HITS" -gt 0 ]; then
        echo "🔔 foundation models — $NAME CAN TAKE IMAGES ($HITS references)."
        echo "   A vision-language model on device would replace the null prompts, the"
        echo "   concept floor and the outdoors test. Worth stopping to redesign around it."
    else
        echo "foundation models — $NAME: text only" \
             "(a prompt holds $SEGMENTS kinds of segment, neither an image)"
    fi
else
    echo "foundation models — not in $NAME, skipped"
fi

# --- 1b. The same question asked of this Mac, which can be a release ahead of the SDK.
#
# The SDK is what we compile against, so it is the gate. But the framework shipped with
# the running OS is where the API appears first: on 22 September 2026 this Mac's runtime
# had Attachment<ImageAttachmentContent> — CGImage, CIImage, CVBuffer, image URL — while
# the iPhoneOS26.5 SDK above still said text only. Watching only the SDK would have meant
# believing "not possible" for as long as it took to install a new Xcode.
HOST="/System/Library/Frameworks/FoundationModels.framework/Versions/A/FoundationModels"
# The framework has no file on disk — it lives in the dyld shared cache — so ask
# dyld_info for it and judge by whether anything came back, not by whether a path exists.
if command -v dyld_info >/dev/null 2>&1; then
    MAC=$(sw_vers -productVersion)
    EXPORTS=$(dyld_info -exports "$HOST" 2>/dev/null)
    IMAGES=$(printf '%s' "$EXPORTS" | grep -cE "ImageAttachmentContent|IdentifiedImage")
    if [ -z "$EXPORTS" ]; then
        echo "foundation models — this Mac (macOS $MAC): framework not readable, skipped"
    elif [ "$IMAGES" -gt 0 ]; then
        echo "🔔 foundation models — this Mac (macOS $MAC) ALREADY TAKES IMAGES" \
             "($IMAGES symbols: Attachment, IdentifiedImage, ImageReference)."
        echo "   Needs Xcode 27 to compile against and iOS 27 on the device to run."
    else
        echo "foundation models — this Mac (macOS $MAC): text only in the runtime too"
    fi
fi

# --- 2. Vision: has it grown a request that says what it sees?
VISION="$SDK/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-ios.swiftinterface"
BASELINE="$HERE/vision-baseline.txt"
if [ -f "$VISION" ] && [ -f "$BASELINE" ]; then
    CURRENT=$(mktemp)
    grep -oE "public struct [A-Za-z]+Request" "$VISION" | awk '{print $3}' | sort -u > "$CURRENT"
    NEW=$(comm -13 "$BASELINE" "$CURRENT")
    GONE=$(comm -23 "$BASELINE" "$CURRENT")
    COUNT=$(wc -l < "$CURRENT" | tr -d ' ')
    if [ -n "$NEW" ] || [ -n "$GONE" ]; then
        echo "🔔 vision — the request list changed in $NAME:"
        [ -n "$NEW" ] && echo "$NEW" | sed 's/^/   new: /'
        [ -n "$GONE" ] && echo "$GONE" | sed 's/^/   gone: /'
        # A request whose name is about *saying* rather than *finding* is the one that
        # would change the design: describing, captioning, or answering a question.
        TELLING=$(echo "$NEW" | grep -iE "describ|caption|understand|answer|question|summar" || true)
        [ -n "$TELLING" ] && echo "   ⚠️  one of these describes rather than detects — read Tools/CURATION.md §3"
        echo "   If these are wanted, update Tools/CurationHarness/vision-baseline.txt."
    else
        echo "vision — $NAME: $COUNT requests, none new (nothing that describes a photograph)"
    fi
    rm -f "$CURRENT"
else
    echo "vision — no interface or no baseline in $NAME, skipped"
fi
