#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
options=(--configuration debug --disable-automatic-resolution)
if [[ -n "${RIFTLET_PROVIDER_SCRATCH:-}" ]]; then options+=(--scratch-path "$RIFTLET_PROVIDER_SCRATCH"); fi
swift build "${options[@]}" --target RiftletAdapters
bin="$(swift build "${options[@]}" --show-bin-path)"
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
ln -s "$bin/Riftlet_RiftletAdapters.bundle" "$temp/Riftlet_RiftletAdapters.bundle"
includes=(-I "$bin" -I Sources/CSQLite)
if [[ -d "$bin/Modules" ]]; then includes+=(-I "$bin/Modules"); fi
if [[ -f "$bin/RiftletAdapters.o" ]]; then
  objects=("$bin/RiftletAdapters.o" "$bin/RiftletCore.o")
else
  objects=("$bin/RiftletAdapters.build/"*.o "$bin/RiftletCore.build/"*.o)
fi
swiftc -parse-as-library "${includes[@]}" Tests/Issue120Integration/driver.swift "${objects[@]}" -o "$temp/driver"
RIFTLET_CHAIN_DRIVER="$temp/driver" node --test Tests/Issue120Integration/check.cjs
