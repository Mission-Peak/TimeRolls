#!/bin/bash
#
# upload_packs.sh — publish the assembled pack tree to the OneBucket bucket.
#
# Works from any directory: paths are resolved relative to this script, not to wherever
# it happens to be run from.
#
# Needs the bucket's access keys. The MCP integration holds them but does not hand them
# out, so take them from the OneBucket console:
#
#   export AWS_ACCESS_KEY_ID=…
#   export AWS_SECRET_ACCESS_KEY=…
#   "…/Tools/PackBuilder/upload_packs.sh"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"
BUCKET="${ONEBUCKET_BUCKET:-irecollect}"
TREE="${1:-$PROJECT_DIR/../build/remote}"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY first (OneBucket console)." >&2
    exit 1
fi

if [ ! -d "$TREE/packs" ]; then
    echo "No pack tree at $TREE" >&2
    echo "Build one first:" >&2
    echo "  python3 \"$SCRIPT_DIR/make_catalog.py\" --packs \"$PROJECT_DIR/PacksForDownload\" --out \"$TREE\"" >&2
    exit 1
fi

count=$(find "$TREE" -type f | wc -l | tr -d ' ')
echo "Publishing $count objects from $TREE"
echo "            → s3://$BUCKET  ($ENDPOINT)"
echo

aws s3 sync "$TREE/" "s3://$BUCKET/" \
    --endpoint-url "$ENDPOINT" \
    --exclude ".DS_Store" \
    --only-show-errors

echo
echo "Done. The app reads $ENDPOINT/$BUCKET/packs/catalog.json"
