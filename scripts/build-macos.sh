#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Riftlet's native build requires macOS with the Swift toolchain." >&2
  exit 2
fi
swift build -c release
riftlet_bin_dir="$(swift build -c release --show-bin-path)"
if [[ -L build ]]; then
  echo "Refusing a linked build directory." >&2
  exit 2
fi
mkdir -p build
riftlet_package_dir="$(mktemp -d build/.riftlet-package.XXXXXX)"
riftlet_keep_package_dir=false
trap 'if [[ "$riftlet_keep_package_dir" != true ]]; then rm -rf "$riftlet_package_dir"; fi' EXIT
riftlet_app="$riftlet_package_dir/Riftlet.app"
mkdir -p "$riftlet_app/Contents/MacOS" "$riftlet_app/Contents/Resources"
cp "$riftlet_bin_dir/Riftlet" "$riftlet_app/Contents/MacOS/Riftlet"
cp Resources/Info.plist "$riftlet_app/Contents/Info.plist"
cp -R ThirdPartyNotices "$riftlet_app/Contents/Resources/"
# The page loader resolves this app resource before SwiftPM's build-tree fallback.
# Keep the reviewed page program in its generated bundle, never an external path.
cp -R "$riftlet_bin_dir/Riftlet_RiftletAdapters.bundle" "$riftlet_app/Contents/Resources/"
python3 scripts/verify-app-bundle.py "$riftlet_app" --repository .
codesign --force --sign - "$riftlet_app"
codesign --verify --strict "$riftlet_app"
# Only publish a complete, validated bundle. Reusing a previous app directory
# could retain stale resources or a no-longer-shipped dependency/notice.
# This touches generated build output only; never an installed app or user data.
if [[ -L build/Riftlet.app || ( -e build/Riftlet.app && ! -d build/Riftlet.app ) ]]; then
  echo "Refusing an unexpected existing build/Riftlet.app." >&2
  exit 2
fi
if [[ -d build/Riftlet.app ]]; then
  mv build/Riftlet.app "$riftlet_package_dir/previous-Riftlet.app"
fi
if ! mv "$riftlet_app" build/Riftlet.app; then
  if [[ -d "$riftlet_package_dir/previous-Riftlet.app" ]]; then
    if ! mv "$riftlet_package_dir/previous-Riftlet.app" build/Riftlet.app; then
      riftlet_keep_package_dir=true
      echo "Previous generated App retained at $riftlet_package_dir/previous-Riftlet.app; replacement failed." >&2
    fi
  fi
  exit 1
fi
echo "Created build/Riftlet.app (development ad-hoc signature; not notarized; no public release)."
