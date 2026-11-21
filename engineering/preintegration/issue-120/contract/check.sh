#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
architecture=${1:-$(uname -m)}
case "$architecture" in
    arm64|x86_64) ;;
    *) echo "Usage: check.sh [arm64|x86_64]" >&2; exit 2 ;;
esac
target="$architecture-apple-macos13.0"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -target "$target" -parse-as-library -emit-library -emit-module -module-name RiftletCore -I Sources/CSQLite Sources/RiftletCore/*.swift -o "$out/libRiftletCore.dylib" -emit-module-path "$out/RiftletCore.swiftmodule"
swiftc -target "$target" -parse-as-library -I Sources/CSQLite -I "$out" -L "$out" -lRiftletCore -Xlinker -rpath -Xlinker "$out" Sources/RiftletAdapters/Issue120/AdapterContract.swift engineering/preintegration/issue-120/contract/*.swift -o "$out/check"
"$out/check"
