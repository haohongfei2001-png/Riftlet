#!/bin/bash
set -euo pipefail
riftlet_package_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
riftlet_beta_app="$riftlet_package_dir/Riftlet.app"
if [[ ! -d "$riftlet_beta_app" || ! -x "$riftlet_beta_app/Contents/MacOS/Riftlet" ]]; then
  echo "未找到同一文件夹中的完整 Riftlet.app。请重新解压整个内部 Beta 包。" >&2
  exit 2
fi
# Explicit one-time mode selection. The original candidate owns onboarding,
# permissions and its existing durable data. No reset, migration or trace flag.
command open -n -a "$riftlet_beta_app" --args --system-screenshot-candidate
