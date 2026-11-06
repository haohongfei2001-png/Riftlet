#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
riftlet_owner_scratch="$(mktemp -d "${TMPDIR:-/tmp}/riftlet-owner-build.XXXXXX")"
trap 'rm -rf "$riftlet_owner_scratch"' EXIT
# Compile the actual owner implementation; do not copy/reimplement the lock.
xcrun swiftc -parse-as-library Sources/RiftletApp/ApplicationInstanceOwnership.swift \
  Tests/Readiness/InstanceOwnershipProbe.swift -o "$riftlet_owner_scratch/ownership-probe"
"$riftlet_owner_scratch/ownership-probe"
