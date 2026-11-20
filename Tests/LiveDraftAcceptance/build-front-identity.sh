#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 || "$1" != /* ]]; then
  echo 'Usage: build-front-identity.sh /absolute/output/file' >&2
  exit 2
fi
cd "$(dirname "$0")/../.."
options=(--configuration debug --disable-automatic-resolution)
swift build "${options[@]}" --target RiftletAdapters
bin="$(swift build "${options[@]}" --show-bin-path)"
includes=(-I "$bin" -I Sources/CSQLite)
if [[ -d "$bin/Modules" ]]; then includes+=(-I "$bin/Modules"); fi
if [[ -f "$bin/RiftletAdapters.o" ]]; then
  objects=("$bin/RiftletAdapters.o" "$bin/RiftletCore.o")
else
  objects=("$bin/RiftletAdapters.build/"*.o "$bin/RiftletCore.build/"*.o)
fi
swiftc -parse-as-library "${includes[@]}" Tests/LiveDraftAcceptance/front-identity.swift "${objects[@]}" -o "$1"
