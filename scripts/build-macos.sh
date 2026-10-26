#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Riftlet's native build requires macOS with the Swift toolchain." >&2
  exit 2
fi
swift build -c release
riftlet_bin_dir="$(swift build -c release --show-bin-path)"
riftlet_app="build/Riftlet.app"
mkdir -p "$riftlet_app/Contents/MacOS" "$riftlet_app/Contents/Resources"
cp "$riftlet_bin_dir/Riftlet" "$riftlet_app/Contents/MacOS/Riftlet"
cp Resources/Info.plist "$riftlet_app/Contents/Info.plist"
cp -R ThirdPartyNotices "$riftlet_app/Contents/Resources/"
codesign --force --sign - "$riftlet_app"
codesign --verify --strict "$riftlet_app"
echo "Created $riftlet_app (development ad-hoc signature; not notarized)."
