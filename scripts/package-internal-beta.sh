#!/bin/bash
# Package the already built unified App with an explicit candidate entry point.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Internal Beta packaging requires the macOS build and codesign tools." >&2
  exit 2
fi
python3 scripts/verify-app-bundle.py build/Riftlet.app --repository .
codesign --verify --strict build/Riftlet.app
if [[ -L build ]]; then
  echo "Refusing a linked build directory." >&2
  exit 2
fi
riftlet_beta_stage="$(mktemp -d build/.riftlet-internal-beta.XXXXXX)"
trap 'rm -rf "$riftlet_beta_stage"' EXIT
riftlet_beta_package="$riftlet_beta_stage/Riftlet-Internal-Beta"
mkdir "$riftlet_beta_package"
ditto build/Riftlet.app "$riftlet_beta_package/Riftlet.app"
cp packaging/internal-beta/Start-Riftlet-Internal-Beta.command "$riftlet_beta_package/"
cp packaging/internal-beta/README-zh-CN.txt "$riftlet_beta_package/"
chmod 755 "$riftlet_beta_package/Start-Riftlet-Internal-Beta.command"
python3 scripts/verify-internal-beta-package.py "$riftlet_beta_package" --repository . \
  --write-manifest --source-head "${RIFTLET_BUILD_HEAD_SHA:-HEAD}"
codesign --verify --strict "$riftlet_beta_package/Riftlet.app"
ditto -c -k --sequesterRsrc --keepParent "$riftlet_beta_package" "$riftlet_beta_stage/Riftlet-Internal-Beta.zip"
if [[ -L build/Riftlet-Internal-Beta.zip || -d build/Riftlet-Internal-Beta.zip ]]; then
  echo "Refusing an unexpected existing Beta archive." >&2
  exit 2
fi
mv "$riftlet_beta_stage/Riftlet-Internal-Beta.zip" build/Riftlet-Internal-Beta.zip
echo "RIFTLET_INTERNAL_BETA_PACKAGE_PASS: complete App, explicit candidate launcher, Feedback capability recorded in exact build manifest; NOT_PUBLIC_RELEASE"
