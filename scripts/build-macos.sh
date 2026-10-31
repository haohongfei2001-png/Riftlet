#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Riftlet's native build requires macOS with the Swift toolchain." >&2
  exit 2
fi
if [[ -L build ]]; then
  echo "Refusing a linked build directory." >&2
  exit 2
fi
mkdir -p build
riftlet_channel=development
riftlet_scratch=""
riftlet_swift_args=(-c release)
case "${1:-}" in
  "") [[ $# == 0 ]] || exit 2 ;;
  --ordinary-acceptance)
    [[ $# == 1 ]] || exit 2
    riftlet_channel=ordinary-acceptance
    riftlet_scratch="$(mktemp -d build/.ordinary-acceptance-swift.XXXXXX)"
    riftlet_swift_args+=(--scratch-path "$riftlet_scratch" -Xswiftc -D -Xswiftc RIFTLET_ORDINARY_ACCEPTANCE)
    ;;
  *) echo "Unsupported build mode." >&2; exit 2 ;;
esac
riftlet_package_dir="$(mktemp -d build/.riftlet-package.XXXXXX)"
riftlet_keep_package_dir=false
trap 'if [[ "$riftlet_keep_package_dir" != true ]]; then rm -rf "$riftlet_package_dir"; fi; if [[ -n "$riftlet_scratch" ]]; then rm -rf "$riftlet_scratch"; fi' EXIT
swift build "${riftlet_swift_args[@]}"
riftlet_bin_dir="$(swift build "${riftlet_swift_args[@]}" --show-bin-path)"
riftlet_app="$riftlet_package_dir/Riftlet.app"
if [[ "$riftlet_channel" == ordinary-acceptance ]]; then
  riftlet_app="$riftlet_package_dir/Riftlet Ordinary Test.app"
fi
mkdir -p "$riftlet_app/Contents/MacOS" "$riftlet_app/Contents/Resources"
cp "$riftlet_bin_dir/Riftlet" "$riftlet_app/Contents/MacOS/Riftlet"
cp Resources/Info.plist "$riftlet_app/Contents/Info.plist"
if [[ "$riftlet_channel" == ordinary-acceptance ]]; then
  python3 -B - "$riftlet_app/Contents/Info.plist" <<'PYPLIST'
import importlib.util, pathlib, plistlib, sys
spec = importlib.util.spec_from_file_location("bundle_verifier", "scripts/verify-app-bundle.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
path = pathlib.Path(sys.argv[1])
path.write_bytes(plistlib.dumps(module.ordinary_acceptance_plist(plistlib.loads(path.read_bytes()))))
PYPLIST
fi
cp -R ThirdPartyNotices "$riftlet_app/Contents/Resources/"
# The page loader resolves this app resource before SwiftPM's build-tree fallback.
# Keep the reviewed page program in its generated bundle, never an external path.
cp -R "$riftlet_bin_dir/Riftlet_RiftletAdapters.bundle" "$riftlet_app/Contents/Resources/"
python3 -B scripts/verify-app-bundle.py "$riftlet_app" --repository . --channel "$riftlet_channel"
codesign --force --sign - "$riftlet_app"
codesign --verify --strict "$riftlet_app"
# Both channels prove executable policy/root, not only plist labels. This early
# exit has no application, browser or database side effects.
python3 -B - "$riftlet_app/Contents/MacOS/Riftlet" "$riftlet_channel" <<'PYIDENTITY'
import importlib.util, json, subprocess, sys
spec = importlib.util.spec_from_file_location("bundle_verifier", "scripts/verify-app-bundle.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = subprocess.run([sys.argv[1], "--ordinary-build-info"], capture_output=True, text=True, timeout=10, check=True)
module.verify_ordinary_build_info(json.loads(result.stdout), sys.argv[2])
print("RIFTLET_ORDINARY_BINARY_IDENTITY_PASS: " + sys.argv[2] + "; fixed capture policy/root; no retry or continuation")
PYIDENTITY
if [[ "$riftlet_channel" == ordinary-acceptance ]]; then
  # Preserve a unique verified output. Never replace the ordinary product or
  # another acceptance binary, including one that may currently be running.
  riftlet_keep_package_dir=true
  echo "Created $riftlet_app (isolated ordinary acceptance; ad-hoc; NOT_NOTARIZED; no public release)."
  exit 0
fi
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
