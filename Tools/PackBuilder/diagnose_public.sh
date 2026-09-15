#!/bin/bash
#
# diagnose_public.sh — find out why anonymous reads of packs/* are refused.
#
# Prints what the endpoint actually says rather than swallowing it, so the next step is
# based on the real error instead of a guess.
#
#   export AWS_ACCESS_KEY_ID=…  AWS_SECRET_ACCESS_KEY=…
#   "…/Tools/PackBuilder/diagnose_public.sh"
#
set -uo pipefail

ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"
BUCKET="${ONEBUCKET_BUCKET:-irecollect}"
KEY="packs/catalog.json"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY first." >&2
    exit 1
fi

line() { printf '\n=== %s\n' "$1"; }

line "1. anonymous GET (what the app does)"
curl -s -o /tmp/irecollect-probe.txt -w "HTTP %{http_code}\n" "$ENDPOINT/$BUCKET/$KEY"
echo "--- body:"; head -c 400 /tmp/irecollect-probe.txt; echo

line "2. authenticated HEAD (does the object exist?)"
aws s3api head-object --bucket "$BUCKET" --key "$KEY" --endpoint-url "$ENDPOINT" 2>&1 | head -12

line "3. current bucket policy"
aws s3api get-bucket-policy --bucket "$BUCKET" --endpoint-url "$ENDPOINT" 2>&1 | head -12

line "4. applying a public-read policy, showing any error"
POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicReadPhotoPacks\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$BUCKET/packs/*\"}]}"
aws s3api put-bucket-policy --bucket "$BUCKET" --endpoint-url "$ENDPOINT" --policy "$POLICY" 2>&1 | head -12
echo "(no output above means it was accepted)"

line "5. anonymous GET again"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$ENDPOINT/$BUCKET/$KEY"

line "6. trying a public-read ACL on one object instead"
aws s3api put-object-acl --bucket "$BUCKET" --key "$KEY" --acl public-read \
    --endpoint-url "$ENDPOINT" 2>&1 | head -12
echo "(no output above means it was accepted)"
curl -s -o /dev/null -w "after ACL: HTTP %{http_code}\n" "$ENDPOINT/$BUCKET/$KEY"
