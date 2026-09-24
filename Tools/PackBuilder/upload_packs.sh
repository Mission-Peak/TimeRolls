#!/bin/bash
# Put the staged photo packs into the OneBucket bucket.
#
# Run this yourself: it needs the Wasabi keys, and those belong in your shell rather than
# in anything I can read. Set up a profile once —
#
#   aws configure --profile onebucket     # your OneBucket key and secret, region us-east-1
#
# then run this. It is a sync, so running it twice only uploads what changed.
set -euo pipefail
cd "$(dirname "$0")/../.."
PROFILE="${1:-default}"
# OneBucket, not Wasabi directly. Wasabi is where OneBucket keeps the bytes, but
# the credentials that exist are OneBucket ones and the app reads through OneBucket.
ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"

[ -d build/onebucket/packs ] || { echo "nothing staged — run Tools/PackBuilder/to_onebucket.py"; exit 1; }
echo "▸ uploading $(find build/onebucket/packs -name '*.jpg' | wc -l | tr -d ' ') photographs"
aws s3 sync build/onebucket/packs "s3://timerolls/packs" \
    --endpoint-url "$ENDPOINT" --profile "$PROFILE" \
    --content-type image/jpeg --exclude "*.json"
aws s3 sync build/onebucket/packs "s3://timerolls/packs" \
    --endpoint-url "$ENDPOINT" --profile "$PROFILE" \
    --content-type application/json --exclude "*" --include "*.json"
echo "✓ uploaded."
echo "  The bucket is private, so the app still cannot read these — see"
  echo "  Tools/PackBuilder/README-onebucket.md for the one policy that changes that."
