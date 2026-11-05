#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# No installed App, defaults, TCC or user source folder is opened.
# A separate scratch directory prevents competing with the normal build.
riftlet_soak_scratch="$(mktemp -d "${TMPDIR:-/tmp}/riftlet-soak-build.XXXXXX")"
trap 'rm -rf "$riftlet_soak_scratch"' EXIT
swift build --build-system native --scratch-path "$riftlet_soak_scratch" --target RiftletCapture
riftlet_soak_bin="$(swift build --build-system native --scratch-path "$riftlet_soak_scratch" --show-bin-path)"
xcrun swiftc -parse-as-library -g -I "$riftlet_soak_bin/Modules" -I Sources/CSQLite \
  Tests/Readiness/NativeSoak.swift \
  "$riftlet_soak_bin"/RiftletCore.build/*.o "$riftlet_soak_bin"/RiftletCapture.build/*.o \
  -lsqlite3 -o "$riftlet_soak_scratch/readiness-soak"
"$riftlet_soak_scratch/readiness-soak"
