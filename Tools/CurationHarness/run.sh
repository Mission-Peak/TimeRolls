#!/bin/bash
# Compiles the curation logic on its own (no UIKit, no simulator) and checks its invariants.
set -euo pipefail
cd "$(dirname "$0")"
SRC="../../Photo Chronology"
OUT=$(mktemp -d)
# The app builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; match it, or this
# harness sees different isolation rules from the code it is checking.
swiftc -O -default-isolation MainActor -o "$OUT/harness" main.swift \
    "$SRC/Model/GameModel.swift" \
    "$SRC/Curation/Curators.swift" \
    "$SRC/Curation/LevelGenerator.swift" \
    "$SRC/Sourcing/PublicPacks.swift" \
    "$SRC/Sourcing/PackStore.swift" \
    "$SRC/Sourcing/ObjectCatalog.swift" \
    "$SRC/Model/CompanionPrompts.swift"
"$OUT/harness"
