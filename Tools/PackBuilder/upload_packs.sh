#!/bin/bash
#
# upload_packs.sh — publish the assembled pack tree to the OneBucket bucket.
#
# The pack tree is plain objects, so this is an ordinary S3 sync. Needs the bucket's
# access keys, which the MCP integration holds but does not hand out; get them from the
# OneBucket console and export them first:
#
#   export AWS_ACCESS_KEY_ID=…
#   export AWS_SECRET_ACCESS_KEY=…
#   ./Tools/PackBuilder/upload_packs.sh
#
set -euo pipefail

ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"
BUCKET="${ONEBUCKET_BUCKET:-irecollect}"
TREE="${1:-build/remote}"

if [ ! -d "$TREE/packs" ]; then
    echo "No pack tree at $TREE. Build one first:"
    echo "  python3 Tools/PackBuilder/make_catalog.py --packs PacksForDownload --out $TREE"
    exit 1
fi

echo "Publishing $TREE → s3://$BUCKET  ($ENDPOINT)"
aws s3 sync "$TREE/" "s3://$BUCKET/" \
    --endpoint-url "$ENDPOINT" \
    --exclude ".DS_Store" \
    --content-type-by-extension 2>/dev/null \
  || aws s3 sync "$TREE/" "s3://$BUCKET/" --endpoint-url "$ENDPOINT" --exclude ".DS_Store"

echo
echo "Done. The app reads $ENDPOINT/$BUCKET/packs/catalog.json"
