# Final App local synthetic acceptance

Base `c861440bfd6ca12c75474d8b16e661f321776c22` (PR #31 already merged).
The original main ARM64 artifact was downloaded and its digest, packaged resources
and signature checked. No existing CI was rerun for confirmation.

## Evidence boundary

Main intentionally accepts ChatGPT origins only. An unmodified final package
cannot perform this localhost test. The disposable full-App build changes only
its Web-acceptance data namespace and the page's exact loopback URL predicate;
Home is disabled. Actual AppKit panels, mouse routing, selection authority,
process/window/tab targeting, permission checks, relay, Coordinator, SQLite,
start gate and completion proof are used. This is **derived full-App synthetic
integration**, not unmodified-final-package acceptance, real ChatGPT upload or
physical mouse evidence. No request, navigation, interception or native access
was made to ChatGPT. Fixture progress is simulated and cannot admit production.

All cases use owned visible local documents. Clicks are CGEvent, with an 80 ms
press and immediate switch after release. Timing is based on panel visibility,
not armed=true. Page/native clock alignment is bracketed by the AE read, so input
latency is reported as an interval. The snapshot-free fast-page case deliberately
removes diagnostic sampling delay. No failed click was replayed.

## Reproduced product defect and minimal fix

With another application foreground and multiple Chrome processes present, the
App's five-second background observer used a *foreground* permission lookup with
no original session. It returned unavailable twice. A had already received its
one input, produced admitted synthetic start and completed its fixture preview,
but SQLite remained `inputTriggered`; the image had swallowed. The same-window
and different-window controls completed.

The fix checks permission for each immutable original operation target before
read-only pending/recovery/completed observation. Denial skips transport without
changing UNKNOWN/audit and retains completed watches. Round-robin progress is
preserved. After each await the original operation is reread, and cancellation
and exact snapshot equality are checked. No new capture, append, target lookup
or operation is introduced. Original-receiver permission does not overwrite the
future foreground's status. Startup read-only recovery is separated from
permission-gated foreground arming, including passive later activation.

The new full-App other-application case reached persisted `succeeded`, one start,
one input and no B/C changes while the other app stayed foreground. A second
case terminated/restarted this owned App while A was pending and another app was
foreground: original operation/attempt 1 reached succeeded with no second input.
The old failing case is preserved unchanged, not repaired retrospectively.

## Remaining P0

A first click shortly after navigation to a fresh local page was safely refused.
The old-document ACK was present; the new-document native receipt arrived about
84.5 ms after the original mouse event, and its App publication about 100.6 ms
later. There was no begin/chunk/commit or file change. A slower fresh-page sample
succeeded, but already had a current receipt. Thus **unobserved cold first click
remains FAIL**, not fixed by the observation-permission change. No future ACK was
backdated and no click retained or automatically replayed.

One first-install switch was triggered as the existing `relay_install` trace was
observed. C stayed frontmost, A was unfocused and all input counts remained zero.
The probe cannot order C's switch against the URL setter itself; the narrow
check-to-setter race is **NOT_EXERCISED**, not proven safe. No speculative bootstrap
rewrite or weaker page identity check is included.

## Validation and limitations

`results.json` records every attempt, including idle-resource preflight refusals,
one stale-driver run after a compile failure (excluded from cold-click results),
and the first same-tab run with unavailable page counters. Later scoped same-tab
regression fills that counter gap without replaying any old operation. Its
background fixture produced final success but no independently sampled start;
that row has zero upload_starts and is not a fast-swallow PASS.

Local production build PASS. Local XCTest execution is unavailable because this
Mac has Command Line Tools without XCTest; parsing is not a test pass. The new
Core tests cover denied/granted different originals, recovery, late watches and
state changes during permission awaits. Exact formal CI/review follows the G/H
protocol; no existing CI is relabelled as testing this fix.

Physical mouse and live ChatGPT remain NOT_RUN/BLOCKED respectively. The 23–33 ms
measured synchronous pin work is about one to two 60 Hz frames; no frame-drop
benchmark or claim of imperceptible latency is made. Synthetic progress timing
and tiny generated images cannot predict real upload speed. Production remains
NO-GO; ordinary upload, safe-retry and continuation are unchanged. Original user
media, historical databases/UNKNOWN and all prior evidence remain untouched.
