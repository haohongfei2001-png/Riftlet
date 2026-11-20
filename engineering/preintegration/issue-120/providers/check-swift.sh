#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
d=engineering/preintegration/issue-120/providers
swiftc -parse-as-library -emit-library -emit-module -module-name RiftletCore -I Sources/CSQLite Sources/RiftletCore/*.swift -o "$temp/libRiftletCore.dylib" -emit-module-path "$temp/RiftletCore.swiftmodule"
swiftc -parse-as-library -I Sources/CSQLite -I "$temp" -L "$temp" -lRiftletCore -Xlinker -rpath -Xlinker "$temp" \
  engineering/preintegration/issue-120/contract/AdapterContract.swift "$d/GeminiLandingProvider.swift" "$d/fixture/GeminiLandingCheck.swift" -o "$temp/check"
"$temp/check" "$d/gemini-surface.mjs"
