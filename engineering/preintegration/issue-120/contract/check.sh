#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -parse-as-library -emit-library -emit-module -module-name RiftletCore -I Sources/CSQLite Sources/RiftletCore/*.swift -o "$out/libRiftletCore.dylib" -emit-module-path "$out/RiftletCore.swiftmodule"
swiftc -parse-as-library -I Sources/CSQLite -I "$out" -L "$out" -lRiftletCore -Xlinker -rpath -Xlinker "$out" engineering/preintegration/issue-120/contract/*.swift -o "$out/check"
"$out/check"
