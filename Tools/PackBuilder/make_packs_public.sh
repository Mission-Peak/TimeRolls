#!/bin/bash
#
# make_packs_public.sh — allow anonymous reads of the photo packs, and only those.
#
# The app downloads packs with no credentials, so packs/* has to be world-readable.
# Nothing else in the bucket is: engagement telemetry is device-keyed and belongs under
# events/, which this policy deliberately leaves private (spec §8, §9).
#
#   export AWS_ACCESS_KEY_ID=…  AWS_SECRET_ACCESS_KEY=…
#   "…/Tools/PackBuilder/make_packs_public.sh"
#
set -euo pipefail

ENDPOINT="${ONEBUCKET_ENDPOINT:-https://s3.us-ashburn-1.onebucket.io}"
BUCKET="${ONEBUCKET_BUCKET:-irecollect}"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY first (OneBucket console)." >&2
    exit 1
fi

POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadPhotoPacks",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/packs/*"
    }
  ]
}
JSON
)

echo "Granting anonymous read on s3://$BUCKET/packs/* …"
if aws s3api put-bucket-policy --bucket "$BUCKET" --endpoint-url "$ENDPOINT" \
       --policy "$POLICY" 2>/dev/null; then
    echo "Bucket policy applied."
else
    echo "Bucket policy was refused; falling back to per-object ACLs."
    aws s3 cp "s3://$BUCKET/packs/" "s3://$BUCKET/packs/" \
        --endpoint-url "$ENDPOINT" --recursive --acl public-read --metadata-directive REPLACE \
        --only-show-errors
    echo "Object ACLs updated."
fi

echo
echo "Checking…"
code=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/$BUCKET/packs/catalog.json")
if [ "$code" = "200" ]; then
    echo "catalog.json is readable. The app is good to go."
else
    echo "catalog.json still returns HTTP $code — the packs are not public yet."
fi
