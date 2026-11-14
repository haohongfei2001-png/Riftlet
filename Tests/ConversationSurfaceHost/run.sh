#!/bin/bash
# Apple WebKit, nonpersistent website data, simulated document bytes, no external browser.
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
swiftc -module-cache-path "${RIFTLET_SURFACE_MODULE_CACHE:-$scratch/cache}" -o "$scratch/surface-host" \
  Sources/RiftletAdapters/ConversationSurfaceAdapter.swift \
  Tests/ConversationSurfaceHost/ConversationSurfaceHost.swift
"$scratch/surface-host" Sources/RiftletAdapters/Resources/ConversationSurfaceProbe.js \
  Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js
