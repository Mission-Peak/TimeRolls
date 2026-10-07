#!/bin/bash
# Put the staged photo packs into the OneBucket bucket the app reads from.
#
# Run this yourself: it needs the upload key for `timerolls-readonly`, and that belongs in
# your shell rather than in anything I can read. Set up a profile once —
#
#   aws configure --profile onebucket     # the upload key and secret, region us-east-1
#
# then run this. It is a sync, so running it twice only uploads what changed.
#
#   ./Tools/PackBuilder/upload_packs.sh onebucket
#
# The bucket is `timerolls-readonly`, the one named in Secrets.xcconfig and read by the
# app's read-only key. This used to upload to `timerolls`, the main bucket, from before the
# read path got a bucket of its own — run like that, every photograph went where the app
# never looks. Both the bucket and the endpoint can be overridden for a one-off:
#
#   ONEBUCKET_BUCKET=… ONEBUCKET_ENDPOINT=https://… ./Tools/PackBuilder/upload_packs.sh onebucket
set -euo pipefail
cd "$(dirname "$0")/../.."
PROFILE="${1:-default}"
BUCKET="${ONEBUCKET_BUCKET:-timerolls-readonly}"
# OneBucket, not Wasabi directly. Wasabi is where OneBucket keeps the bytes, but
# the credentials that exist are OneBucket ones and the app reads through OneBucket.
ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"

[ -d build/onebucket/packs ] || { echo "nothing staged — run Tools/PackBuilder/to_onebucket.py"; exit 1; }
echo "▸ uploading $(find build/onebucket/packs -name '*.jpg' | wc -l | tr -d ' ') photographs"
echo "  to s3://$BUCKET/packs via $ENDPOINT (profile $PROFILE)"
aws s3 sync build/onebucket/packs "s3://$BUCKET/packs" \
    --endpoint-url "$ENDPOINT" --profile "$PROFILE" \
    --content-type image/jpeg --exclude "*.json"
aws s3 sync build/onebucket/packs "s3://$BUCKET/packs" \
    --endpoint-url "$ENDPOINT" --profile "$PROFILE" \
    --content-type application/json --exclude "*" --include "*.json"
echo "✓ uploaded."
echo "  Next: python3 Tools/PackBuilder/to_onebucket.py --apply, so the app's packs carry"
echo "  each photograph's key. Commons stays the fallback either way."
