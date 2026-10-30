#!/bin/bash
set -euo pipefail
if [[ $# != 0 ]]; then
  echo "This fixed internal build accepts no runtime/admission overrides." >&2
  exit 2
fi
exec bash "$(dirname "$0")/build-macos.sh" --ordinary-acceptance
