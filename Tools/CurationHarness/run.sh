#!/bin/bash
# Compiles the curation logic on its own (no UIKit, no simulator) and checks its invariants.
set -euo pipefail
cd "$(dirname "$0")"
SRC="../../Photo Chronology"
OUT=$(mktemp -d)
swiftc -O -o "$OUT/harness" main.swift \
    "$SRC/Model/GameModel.swift" \
    "$SRC/Curation/Curators.swift" \
    "$SRC/Curation/LevelGenerator.swift" \
    "$SRC/Sourcing/PublicPacks.swift"
"$OUT/harness"
