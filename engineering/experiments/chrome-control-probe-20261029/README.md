# Read-only Chrome control probe

This small macOS diagnostic separates native Apple Events/AX availability from
the desktop control tool. It never grants a target ACK or input authority. It
does not install, launch or activate Chrome, request permissions, change browser
settings, inspect chat text, manipulate a composer, capture a screenshot or send.

```sh
swiftc -parse-as-library engineering/experiments/chrome-control-probe-20261029/probe.swift -o /tmp/riftlet-chrome-probe
/tmp/riftlet-chrome-probe --self-check
```

The self-check constructs local descriptors and adversarial aggregate JSON only;
CI does not enumerate a user's applications or inspect permissions. A separately
authorized live read can be bounded by the caller:

```sh
python3 - <<'PY'
import subprocess
subprocess.run(['/tmp/riftlet-chrome-probe', '--live-read-only'], timeout=18, check=True)
PY
```

Live mode addresses each already running Chrome process by its original PID and
launch date. It uses passive Automation checks (`askUserIfNeeded=false`) and
`neverInteract`. AX timeout configuration must succeed; the original process
lifetime must survive each window read and Apple Event. The exact fixed tab
descriptor is required before aggregate DOM inspection. The reply has a strict
key/type/size allowlist and is projected into closed enums, booleans and bounded
counts. No private window/tab IDs, URLs, paths, page text or error description are
printed. Numeric error codes do not identify their root cause.

Each remote AE has a 0.5-second limit and AX a 0.3-second messaging timeout; the
outer 18-second process bound also covers permission service/library overhead.
No API result is reused to select an upload receiver. In particular, a successful
probe's Automation status belongs to that executable/caller, not every Riftlet
App, and a DOM element count does not prove a unique valid business target.

Actual bounded local results and the exact probe source hashes are in
[control-results.json](../../evidence/2026-10-29-cold-click-verdict/control-results.json).
