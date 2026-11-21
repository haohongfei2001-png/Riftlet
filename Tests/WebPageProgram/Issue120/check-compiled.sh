#!/bin/bash
# Run on a macOS development checkout with the project's Swift toolchain and
# ordinary Google Chrome installed. Only a fresh headless loopback window/profile
# is used by the Chrome test. No network permission or account is needed there.
set -euo pipefail
cd "$(dirname "$0")/../../.."
mode=full
case "$#" in
    0) ;;
    1) [[ "$1" == --backend-only ]] || exit 2; mode=backend ;;
    *) exit 2 ;;
esac
if [[ "$mode" == full && ! -x "${RIFTLET_HEADLESS_SHELL:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}" ]]; then
    echo "NOT_RUN: Google Chrome is unavailable" >&2
    exit 1
fi
options=(--configuration debug --disable-automatic-resolution)
if [[ -n "${RIFTLET_PROVIDER_SCRATCH:-}" ]]; then
    options+=(--scratch-path "$RIFTLET_PROVIDER_SCRATCH")
fi
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
swiftc -parse-as-library "${includes[@]}" Tests/WebPageProgram/Issue120/check-backend.swift "${objects[@]}" -o "$temp/backend"
"$temp/backend"
if [[ "$mode" == backend ]]; then exit 0; fi
swiftc "${includes[@]}" Tests/WebPageProgram/Issue120/export-program.swift "${objects[@]}" -o "$temp/export"
RIFTLET_TEST_PROVIDER_EXPORTER="$temp/export" node --test Tests/WebPageProgram/issue120-provider-runtime.test.cjs
