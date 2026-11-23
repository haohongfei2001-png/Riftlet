#!/bin/sh
# Supply the Debug products directory for the frozen build's adapters and core.
set -eu
if [ "$#" -ne 2 ]; then
    echo 'Usage: build-original-observer.sh <Debug-products-dir> <private-output-dir>' >&2
    exit 2
fi
umask 077
products=$1
destination=$2
native=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$destination"
for target in observer navigate focus present; do
    case $target in
        navigate) set -- -D QA_NAVIGATE ;;
        focus) set -- -D QA_FOCUS ;;
        present) set -- -D QA_PRESENT ;;
        observer) set -- ;;
    esac
    xcrun swiftc -parse-as-library -D ORIGINAL_DRAFT_OBSERVER "$@" \
        -module-cache-path "$destination/swift-cache" \
        -I "$products" -I "$native/../../../Sources/CSQLite" \
        "$native/identity.swift" "$native/owned.swift" "$native/press.swift" \
        "$native/OriginalDraftObserver.swift" "$native/ReadOriginalDraft.swift" \
        "$products/RiftletAdapters.o" "$products/RiftletCore.o" -lsqlite3 \
        -o "$destination/$target"
done
