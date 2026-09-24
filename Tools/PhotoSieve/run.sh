#!/bin/bash
# Put candidate photographs through the app's own curation. Paths on stdin, JSON on stdout.
set -uo pipefail
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/timerolls-photosieve"
mkdir -p "$OUT"
# The app's TextDensity is compiled in, not copied, so this cannot drift from what ships.
if [ ! -x "$OUT/sieve" ] || [ main.swift -nt "$OUT/sieve" ] \
   || [ ../../TimeRolls/Curation/TextDensity.swift -nt "$OUT/sieve" ]; then
    xcrun swiftc -O -target arm64-apple-macos27.0 -parse-as-library -o "$OUT/sieve" \
        main.swift ../../TimeRolls/Curation/TextDensity.swift >&2 || exit 1
fi
exec "$OUT/sieve" "$@"
