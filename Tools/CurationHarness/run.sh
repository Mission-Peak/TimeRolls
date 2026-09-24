#!/bin/bash
# Compiles the curation logic on its own (no UIKit, no simulator) and checks its invariants.
set -euo pipefail
cd "$(dirname "$0")"
SRC="../../TimeRolls"
OUT=$(mktemp -d)
# The app builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; match it, or this
# harness sees different isolation rules from the code it is checking.
swiftc -O -default-isolation MainActor -o "$OUT/harness" main.swift \
    packs.swift \
    "$SRC/Model/GameModel.swift" \
    "$SRC/Curation/Curators.swift" \
    "$SRC/Curation/LevelGenerator.swift" \
    "$SRC/Curation/RoundAuditRules.swift" \
    "$SRC/Curation/AlbumNames.swift" \
    "$SRC/Curation/SpokenNumbers.swift" \
    "$SRC/Curation/Encouragement.swift" \
    "$SRC/Curation/DescribedPhotos.swift" \
    "$SRC/Curation/TextDensity.swift" \
    "$SRC/Curation/AlreadyMissed.swift" \
    "$SRC/Sourcing/QuestionGuardrail.swift" \
    "$SRC/Sourcing/PublicPacks.swift" \
    "$SRC/Sourcing/PackStore.swift" \
    "$SRC/Sourcing/ObjectCatalog.swift" \
    "$SRC/Model/PhotoRotation.swift" \
    "$SRC/Model/Supporting.swift"
"$OUT/harness"

# Not an invariant — a capability notice. If the on-device model learns to look at
# photographs, most of the curation above becomes a question asked in English instead.
./check_sdk.sh
