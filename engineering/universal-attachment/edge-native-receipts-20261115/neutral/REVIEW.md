# Native mouse delivery investigation

This is a source/evidence review and a compiled diagnostic fixture. This agent
has not launched a GUI, posted an event, changed a browser/profile/permission,
changed product source, or opened a product database for writing.

## Confirmed observations

- The preserved `restart-01-sent-1.json` reserves one pair for asset digest
  `90829a9e3527ab9ee8464ac72fcc20fa803efd98ef9dd96a2d8c1d29323c3b13`,
  input window 2823, point `(33,434)`, event number 28310 and tag
  114491094720443. This only establishes that the sender returned from
  `CGEventPost`, not application receipt.
- At the first independent read, the live trace still had 38 rows, ending at
  diagnostic sequence 38, and the read-only queue had two assets, zero
  operations and zero upload starts. The image hit map continued to update.
  A later second-pair reservation is a separate operation in the evidence;
  this review does not relabel either missing receipt as a refusal or retry.
- In the source of the running package, both the application event monitor
  and all panel/input dispatch diagnostics require a positive, less-than-48-bit
  `eventSourceUserData` tag before recording. The original passive observer
  likewise admits only the exact expected tag. Empty observations therefore
  cannot distinguish absent delivery from a rewritten/stripped correlation
  field. This is a limitation of the earlier instrumentation, not evidence that
  macOS did strip the field.
- The 2-by-2 hit-map rectangle is deliberately a verified interior sampling
  region. It is not the actual input NSWindow's size. The product publishes it
  only for a visible, ready, pending asset and a live input island whose four
  sampled corners satisfy the product selection geometry. The sender also
  checks the actual owning window and the first `NSWindow.windowNumber(at:)`
  receiver before reserving and again before posting.
- `RiftInputView.acceptsFirstMouse` already returns true. Its dispatch hook is
  before bounds/original-row validation; `onDown` tracing precedes its queue,
  duplicate, selection and state gates. Consequently those gates would not
  explain the absence of *all tagged* upstream events if the original tag had
  reached those hooks intact.
- The known old first click with a complete callback chain and `-1744` is
  independent of the current no-receipt outcome. Neither the current absence
  nor the old second-click absence is an Apple Events denial receipt.

## What remains unproved

An immediate sender exit, tooling focus restoration, a WindowServer/input
filter, an identity-field rewrite, and a geometry change after the final
preflight are still hypotheses. There is no source evidence here that licenses
declaring one of them the root cause or extending a product timeout as a fix.
The old exact-tag-only passive result cannot identify a failing event layer.

The public SDK's `CoreGraphics.framework/Headers/CGEvent.h` documents that
`CGEventPost` inserts an event before taps at the selected location, that taps
can be inserted before or after existing filters, and that active filters can
modify or discard an event. Its return type is `void`. The compiled fixture
uses these public interfaces only; it does not call private WindowServer APIs.

## Prepared bounded experiment

`MouseDeliveryProbe.swift` produces a single standalone executable with two
modes. The receiver makes one neutral AppKit window, activates and verifies
its own exact PID/kernel birth/window/first receiver, and creates passive HID
head, HID tail and annotated-session tail taps. Failure to create or enable a
tap stops without a click. Existing permission preflight results are recorded;
no permission prompt is requested.

The receiver launches two separate copies of its own binary, each associated
with a different neutral point, event number and tag. Each reserves a fresh
once-only record before exactly one mouse down/up pair:

1. Sender 1 exits immediately after the same `CGEventPost` pair used by the
   product test sender.
2. Sender 2 keeps its own run loop alive only until the fixture acknowledges
   one down/up pair from that sender, bounded at two seconds. A timeout is an
   observation failure, never a retry condition.

Only events from the exact sender PID or expected point/event-number pair are
correlated. The tag is recorded as data. Rewritten-identity candidates at the
owned neutral window/point are separately bounded and labeled uncorrelated;
they never acknowledge a click. Native events for the owned window are also
counted independently of identity correlation. No keyboard or unrelated
window events are retained. The per-trial observation is bounded at 2.5
seconds after a child exits; an unexpected live child stops the experiment.

Interpret the results narrowly:

- Both reach the fixture: immediate exit is not sufficient to reproduce loss
  in this bounded environment. It does not establish the product path.
- Only the receipt-wait sender reaches the fixture: sender lifetime is a
  candidate mechanism requiring repeatable controlled evidence before a fix;
  the difference must be localized in the recorded tap/native sequence.
- HID head sees a pair but a later stage does not: inspect that layer, including
  tap-enable/disabled facts and changed fields, before blaming App callbacks.
- Only uncorrelated events arrive: report the rewritten fields; do not claim
  a correlated successful click.
- No observations: the fixture did not localize delivery. Preserve the result
  and inspect supported event-system/permission state instead of reposting
  either product asset.

These neutral trials are solely an OS event-delivery experiment. They do not
prove ordinary Riftlet selection, draft binding, commercial upload start or
completion, and cannot authorize replay of a product UNKNOWN.

## Build and execution handoff

Compilation succeeded without warnings on the available command-line SDK.
The exact source, binary and empty compile-log hashes are in
`build-receipt.json`. No execution was performed by this agent.

Root may execute once after reviewing the source:

```sh
<USER_HOME>/Documents/GitHub/Riftlet/build/pr69-mouse-delivery-review/mouse-delivery-probe --run <USER_HOME>/Documents/GitHub/Riftlet/build/pr69-mouse-delivery-review/run-20261115-01 > <USER_HOME>/Documents/GitHub/Riftlet/build/pr69-mouse-delivery-review/run-20261115-01.stdout.json
```

The run directory must not exist; it is created as an owned mode-0700
directory. Original run files are never replaced. The receiver writes
`report.json`, per-trial configs/reservations, sender stdout/stderr and any
actual native acknowledgments. It hides only its own window at finish and
does not activate another application.
