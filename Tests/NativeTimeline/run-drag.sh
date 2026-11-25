#!/bin/bash
# Run in a dedicated unlocked macOS test session. The host never activates an app.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${RIFTLET_NATIVE_DRAG_BUILD:-"$repo/.build"}
cd "$repo"
swift build --target RiftletUI --scratch-path "$scratch"
modules="$scratch/out/Products/Debug"
if [[ -f "$modules/RiftletUI.o" ]]; then
  objects=("$modules/RiftletCore.o" "$modules/RiftletCapture.o" "$modules/RiftletUI.o")
else
  bin=$(swift build --scratch-path "$scratch" --show-bin-path)
  modules="$bin/Modules"
  objects=("$bin"/Riftlet{Core,Capture,UI}.build/*.swift.o)
fi
driver="$scratch/riftlet-native-drag-acceptance"
swiftc -parse-as-library -I "$modules" -I Sources/CSQLite \
  Tests/NativeTimeline/DragAcceptance.swift "${objects[@]}" -lsqlite3 -o "$driver"
"$driver"
