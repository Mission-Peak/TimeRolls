#!/bin/bash
#
# check_packs_public.sh — can a phone read the photo packs?
#
# No credentials: this asks exactly what the app asks, as an anonymous stranger. Run it
# after changing the bucket's access settings.
#
set -uo pipefail

BASE="${ONEBUCKET_PUBLIC_BASE:-https://s3.us-ashburn-1.onebucket.io/irecollect}"

echo "Reading $BASE as an anonymous visitor…"
echo

catalog_code=$(curl -s -o /tmp/irecollect-catalog.json -m 20 -w "%{http_code}" "$BASE/packs/catalog.json")
echo "  catalog.json          HTTP $catalog_code"

if [ "$catalog_code" != "200" ]; then
    echo
    echo "Not public yet. The packs are uploaded, but the bucket still refuses"
    echo "anonymous reads, so the app cannot download them."
    exit 1
fi

# Follow the same chain the app does: catalogue → a manifest → a photograph.
manifest=$(python3 -c "
import json
print(json.load(open('/tmp/irecollect-catalog.json'))['packs'][0]['manifest'])
" 2>/dev/null) || { echo "  catalog.json is not readable as JSON"; exit 1; }

manifest_code=$(curl -s -o /tmp/irecollect-manifest.json -m 20 -w "%{http_code}" "$BASE/$manifest")
echo "  $(basename "$manifest")   HTTP $manifest_code"

first_image=$(python3 -c "
import json
print(json.load(open('/tmp/irecollect-manifest.json'))['items'][0]['file'])
" 2>/dev/null) || { echo "  manifest is not readable as JSON"; exit 1; }

image_code=$(curl -s -o /dev/null -m 30 -w "%{http_code}" \
    "$BASE/$(dirname "$manifest")/$first_image")
echo "  $first_image        HTTP $image_code"

echo
if [ "$manifest_code" = "200" ] && [ "$image_code" = "200" ]; then
    echo "All readable — the app can download packs. Tell Claude and the packs can come"
    echo "back out of the app binary."
else
    echo "The catalogue is readable but something under it is not."
fi
