#!/bin/bash
# Compare one immutable baseline to this checkout using real, isolated SQLite metadata.
set -euo pipefail
if [[ $# -ne 1 || -e "$1" || "$1" != /* ]]; then
  echo "Usage: scripts/measure-history-query.sh NEW_ABSOLUTE_OUTPUT_DIRECTORY" >&2
  exit 64
fi
out="$1"
mkdir -m 700 "$out"
cd "$(dirname "$0")/.."
baseline=3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b
mkdir "$out/baseline" "$out/compiler-cache"
git archive "$baseline" Sources/RiftletCore Sources/CSQLite | tar -xf - -C "$out/baseline"
for variant in baseline candidate; do
  src=.
  flags=(-D LIBRARY_BASELINE)
  if [[ "$variant" == baseline ]]; then src="$out/baseline"; else flags=(-D LIBRARY_104); fi
  build="$out/$variant-module"
  mkdir "$build"
  swiftc -O -module-name RiftletCore -enable-testing -emit-module -emit-library \
    -module-cache-path "$out/compiler-cache" -I "$src/Sources/CSQLite" "$src"/Sources/RiftletCore/*.swift \
    -emit-module-path "$build/RiftletCore.swiftmodule" -o "$build/libRiftletCore.dylib"
  swiftc -parse-as-library -O "${flags[@]}" -module-cache-path "$out/compiler-cache" \
    -I "$build" -I "$src/Sources/CSQLite" -L "$build" -lRiftletCore -Xlinker -rpath -Xlinker "$build" \
    Tests/Readiness/LibraryHistoryProbe.swift -o "$build/probe"
  (cd "$src" && shasum -a 256 Sources/RiftletCore/*.swift Sources/CSQLite/*) > "$build/source.sha256"
  shasum -a 256 "$build/probe" "$build/libRiftletCore.dylib" > "$build/binary.sha256"
done
sw_vers > "$out/environment.txt"
uname -m >> "$out/environment.txt"
swiftc --version >> "$out/environment.txt"
git rev-parse HEAD >> "$out/environment.txt"
for count in 200 2000 10000; do
  "$out/baseline-module/probe" seed "$out/seed-$count.sqlite" "$count"
  for variant in baseline candidate; do
    db="$out/$variant-$count.sqlite"
    cp "$out/seed-$count.sqlite" "$db"
    "$out/$variant-module/probe" run "$db" "$count" > "$out/$variant-$count.tsv"
  done
done
