#!/bin/sh
# Run inside a disposable macOS VM, using its ordinary Safari with default settings.
# The executable is compiled from SafariColdProbe.swift on a compatible Mac.
set -eu
[ "${RIFTLET_DISPOSABLE_SAFARI_GUEST:-}" = yes ] || { echo 'A disposable VM is required' >&2; exit 2; }
[ "$(/usr/sbin/sysctl -n hw.model)" = 'VirtualMac2,1' ] || exit 2
[ -x "$1" ] || exit 2
if /usr/bin/pgrep -x Safari >/dev/null; then echo 'Safari already running; leaving it untouched' >&2; exit 2; fi
folder=$(mktemp -d /private/tmp/riftlet-120-XXXXXXXX)
fixture="$folder/RiftletHostFixture.html"
pid=''
cleanup() {
    if [ -n "$pid" ] && [ "$(/bin/ps -p "$pid" -o ucomm= | /usr/bin/xargs)" = Safari ]; then
        kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$fixture"
    rmdir "$folder"
}
trap cleanup EXIT
cat > "$fixture" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Loading fixture</title><textarea>synthetic draft</textarea>
<script>window.riftletFixtureSentinel = crypto.randomUUID(); document.title='RiftletHostFixture-'+window.riftletFixtureSentinel;</script>
HTML
/usr/bin/open -g -a /Applications/Safari.app "$fixture"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(/usr/bin/pgrep -x Safari || true)
    [ -n "$pid" ] && break
    sleep 1
done
[ -n "$pid" ] && [ "$(echo "$pid" | wc -l | xargs)" = 1 ] || exit 2
sleep 3
"$1" "file://$fixture"
