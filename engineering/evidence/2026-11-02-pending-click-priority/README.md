# Pending-click capture priority increment

Continues PR33 at `3d0f6c3f9b8e628aecbac19c5900aca6eb5a18e6`, based on
main `2fc362a8e5a12b5c833a14e09cf2946afbbd613d`. No main merge or admission
expansion. First-MAIN business continuity and focus-setter gaps from PR33 remain
open; the pending mechanism remains compiler-gated and fixed-loopback-only.

## Actual cause and minimal change

The preceding local AppKit/CGEvent fresh-page sample had no earlier native ACK.
A single native press installed MAIN and resolved original A. Switching to B
completed 102.27 ms after the original native event. A's sole file change occurred
while hidden/unfocused, B received none. Event-to-file-change was bounded by the
page/native clock read at 1010.04–1020.71 ms; synchronous press work was 74.31 ms.
The trace places 715.16 ms in `validate`'s queue wait behind an obsolete
`captureTarget` receipt poll. This is a one-sample historical baseline, not a
p50/p95 estimate, not a real ChatGPT upload, and not this increment's result.

The transport queue remains serial. Target discoveries acquire a generation
at enqueue. An original press or an enqueued pinned validate/begin/chunk/commit
supersedes older discovery generations. Superseded discovery checks fail before
native sends, after native returns, during receipt polling, before cache writes,
and at MainActor return. Tiny cache writes are atomic with supersession. No
receipt is re-submitted and no original target is substituted.

Only capture has a cancellation ticket. Begin/chunk/commit, discard and original
operation observation retain their existing serialization and receipt behavior.
A capture already submitted to MAIN can still execute its read-only page work;
its late result cannot publish a new ACK. The App records actual captureAttempted
separately from captureSuperseded, completes its scheduler once, and retains an
existing ACK only under the original epoch/session constraints. It never grants
an ACK from a cancelled result or cancels a bound upload transaction.

## Verification and limits

- Local `swift build --product Riftlet`: PASS.
- Six standalone deterministic Swift scenarios using the actual priority/receipt
  source: PASS (not XCTest or AppKit performance). Covered empty receipt
  supersession, queued old work, late valid reply, a timed-out in-flight read,
  unaffected input receipt and single serial input before fresh discovery.
- Added native XCTest regressions for those boundaries plus stale App
  epoch/session, late ACK rejection and exactly-once scheduler completion.
  Local CLT lacks XCTest; exact-source formal macOS CI must be reported separately.
- Local compiler-gated fixture App build/signature: PASS; its two established
  origin/data-root overlays stay isolated and are not production source changes.
- New real AppKit latency distribution: NOT_RUN at this checkpoint. Read-only
  inventory found another active browser task and recent HID input. No foreground
  was taken. p50/p95/max and main-thread distribution require new actual samples;
  simulated clock values cannot substitute for them.
- An already executing Apple Event is not forcibly interrupted. Receipt reads
  retain their existing maximum 250 ms send budget; other native events retain
  their existing up-to-five-second timeout. No universal latency bound is claimed.

Default upload/start/completion, safe-retry, Web continuation, legacy UNKNOWN,
media/history, Feedback and first-MAIN identity requirements are unchanged.
Production remains NO-GO. Real ChatGPT remains blocked by host restrictions and
was not accessed. No physical-input or complete consumer cold-first-click pass.

## First MAIN follow-up on this same branch

The old async URL setter path is removed ONLY from the compiler-gated local
candidate. A single absolute A execute-JavaScript call now installs the isolated
witness, inserts a classic inline MAIN script if needed, and requires an immediate
matching nonce receipt before it returns. It never adopts a later asynchronous
result as preparation. Ordinary builds retain their existing MAIN installer.
CSP or Trusted Types denial returns unavailable with no fallback, no borrowed
nonce, policy change, extension or background URL setter.

A concrete reentrancy defect was reproduced: a public validate/release listener
could commit business B (or B then A) before the first monitor existed. The new
order establishes MAIN business identity/monitor before those callbacks and
rechecks the exact saved state afterwards. All four callback/restore variants
now reject without input; the pre-fix test failed with a missing exception.

202 deterministic page/legacy cases pass. Actual Chromium isolated-world→MAIN
headless cases use the exact emitted relay and witness, with fresh registry,
one change on A, zero on B and synthetic final completion. Separate CSP-none
calibration refuses immediate MAIN execution. These are realm/channel tests,
not WindowServer/Apple Events foreground tests. Native XCTest covers immediate
nonce result, denied/deferred insertion, repeat nonce, foreign host and invalid
witness. Official Native/Feedback CI is reported on the exact new G/H separately.

The supported atomic claim starts at this one renderer task, NOT at the original
macOS mouseDown. A silent same-node business replacement before first observation
or one bypassing all observed root writes remains undecidable. The pre-MAIN
counterexample stays in the suite, with zero file input, and real-source gates
stay closed. This candidate is not eligible for consumer/production integration
on the strength of its local tests. Stop that enablement route rather than infer
continuity from a TTL or the usual order of notifications.

Standards context: classic inline script insertion is governed by the HTML script
execution model (https://html.spec.whatwg.org/multipage/scripting.html). MAIN code
is subject to page CSP (https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts).
The actual local tests, not those general documents, establish this limited result.
