#!/bin/bash
# Link the test against the chosen checkout's built Swift objects. Arguments:
#   product checkout, matching Swift --show-bin-path, new evidence directory
set -euo pipefail
[[ $# -eq 3 ]] || { echo "expected product checkout, Swift bin directory, new evidence directory" >&2; exit 2; }
list_only=false
if [[ $1 == --check-window-list ]]; then
    list_only=true
    src=$2
    bin=$3
else
    src=$1
    bin=$2
    evidence=$3
    mkdir -m 700 "$evidence"
fi
here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
ln -s "$bin/Riftlet_RiftletAdapters.bundle" "$scratch/Riftlet_RiftletAdapters.bundle"
includes=(-I "$bin" -I "$src/Sources/CSQLite")
[[ ! -d "$bin/Modules" ]] || includes+=(-I "$bin/Modules")
if [[ -f "$bin/RiftletAdapters.o" ]]; then
    objects=("$bin/RiftletAdapters.o" "$bin/RiftletCore.o")
else
    objects=("$bin/RiftletAdapters.build/"*.o "$bin/RiftletCore.build/"*.o)
fi
swiftc -module-cache-path "${RIFTLET_QA_SWIFT_MODULE_CACHE:-$scratch/module-cache}" -parse-as-library "${includes[@]}" "$here/check.swift" "${objects[@]}" -o "$scratch/check"
if [[ $list_only == true ]]; then
    "$scratch/check" --check-window-list
    exit
fi
for family in Chrome Edge; do
    if [[ "$family" == Chrome ]]; then app='/Applications/Google Chrome.app'; else app='/Applications/Microsoft Edge.app'; fi
    "$scratch/check" "$app" "$scratch/$family" > "$evidence/$family.json"
    if [[ -f "$scratch/$family/closed-window/acceptance-recent.jsonl" ]]; then
        cp "$scratch/$family/closed-window/acceptance-recent.jsonl" "$evidence/$family-closed-window.jsonl"
    fi
    for file in acceptance-recent.jsonl queue.sqlite qa.png; do
        cp "$scratch/$family/$file" "$evidence/$family-$file"
    done
done
