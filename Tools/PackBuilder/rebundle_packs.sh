#!/bin/bash
#
# rebundle_packs.sh — put the downloadable packs back inside the app.
#
# A fallback for while pack delivery is unavailable: it moves everything in
# PacksForDownload/ into the app target, so the packs ship in the binary again. The app
# gets bigger (about 38 MB with both), but the photos are there with no network at all.
#
# Reverse it with --undo once downloads work.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
IN_APP="$PROJECT_DIR/Photo Chronology/Packs"
FOR_DOWNLOAD="$PROJECT_DIR/PacksForDownload"

if [ "${1:-}" = "--undo" ]; then
    mkdir -p "$FOR_DOWNLOAD"
    for pack in "$IN_APP"/*; do
        name=$(basename "$pack")
        [ "$name" = "decades" ] && continue      # the starter pack stays in the app
        [ -d "$pack" ] || continue
        git mv "$pack" "$FOR_DOWNLOAD/$name" 2>/dev/null || mv "$pack" "$FOR_DOWNLOAD/$name"
        echo "moved out of the app: $name"
    done
else
    for pack in "$FOR_DOWNLOAD"/*; do
        [ -d "$pack" ] || continue
        name=$(basename "$pack")
        git mv "$pack" "$IN_APP/$name" 2>/dev/null || mv "$pack" "$IN_APP/$name"
        echo "bundled into the app: $name"
    done
fi

echo
echo "Rebuild and reinstall to pick this up."
