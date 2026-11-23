#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
  echo "usage: build-window-inspector.sh RIFTLET_CHECKOUT INSTRUMENTED_PRODUCTS OUTPUT" >&2
  exit 2
fi
repo=$1
products=$2
out=$3
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
modcache="$out.module-cache"
mkdir -p "$modcache"
modcache=$(CDPATH= cd -- "$modcache" && pwd -P)
exec xcrun swiftc -parse-as-library -module-cache-path "$modcache" -D ORIGINAL_DRAFT_OBSERVER \
  -import-objc-header "$here/WindowInspectorSession.h" \
  -I "$products" -I "$repo/Sources/CSQLite" \
  "$repo/Tests/PreClickLease/native/identity.swift" "$repo/Tests/PreClickLease/native/owned.swift" \
  "$repo/Tests/PreClickLease/native/press.swift" "$here/WindowInspector.swift" \
  "$products/RiftletAdapters.o" "$products/RiftletCore.o" -lsqlite3 -lbsm -Xlinker -dead_strip -o "$out"
