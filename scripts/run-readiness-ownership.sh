#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
riftlet_owner_scratch="$(mktemp -d "${TMPDIR:-/tmp}/riftlet-owner-build.XXXXXX")"
trap 'rm -rf "$riftlet_owner_scratch"' EXIT
# The owner uses the preparation identity from the production adapter module.
swift build --build-system native --disable-automatic-resolution --skip-update --target RiftletAdapters
riftlet_owner_bin="$(swift build --build-system native --show-bin-path)"
xcrun swiftc -parse-as-library -I "$riftlet_owner_bin/Modules" -I Sources/CSQLite \
  Sources/RiftletApp/ApplicationInstanceOwnership.swift Tests/Readiness/InstanceOwnershipProbe.swift \
  "$riftlet_owner_bin"/RiftletAdapters.build/*.o "$riftlet_owner_bin"/RiftletCore.build/*.o \
  -lsqlite3 -o "$riftlet_owner_scratch/ownership-probe"
"$riftlet_owner_scratch/ownership-probe"
