# Original-click target transactions — integration candidate

Base: `0878e177b58e755e59e8b77adaec6be7ff657337`. The source checkpoint is
recorded by the admission-only successor; this evidence is part of that source.
Production remains NO-GO. No original database, media, UNKNOWN, system preference,
Chrome profile configuration, private chat, product input or historical receipt was changed in this work. Owned synthetic browser fixtures are described below.

## Implemented contract

A native press snapshots the last observed native route and page identity before
performing a bounded synchronous route check and original-page `pinTarget`.
The pin must match the exact PID birth/session, window, tab, document, composer,
logical draft and generation previously observed before the original event.
A page with no observer, a revoked pre-pin input lease, A-B-A transition, mismatched
route or late replacement receipt is refused. Pin creation does not input a file.
The returned target must equal the expected target plus the new pin UUID.

After that pin succeeds, future foreground capture invalidation does not revoke
it. Validation, begin, chunks, commit and original read-only observation address
only that absolute PID/window/tab. They never activate A or look for a replacement
in B. Original node/draft destruction, modal/disabled composer, receiver permission
loss, explicit removal/hide/exit and the original waiting deadline remain vetoes.
Pin creation has a 750 ms total native-event budget, not a fresh five-second wait
per event. This is a bounded UI-thread cost, not a measured latency improvement.

Only one operation can claim a pin. Input intent, unique commit, exact source
hash, uploadStarted admission, completion proof and same-draft UNKNOWN locks are
unchanged. Focus-only renewal preserves already issued pins; actual document or
business identity invalidation retires their original audit records. Old v13
closures remain available for their original read-only operations. Optional pin
identity decodes old targets unchanged and is checked by strict new receipts.
Foreground and click checks share per-receiver permission ordering; B's status
cannot stand in for A's permission.

## Exact limits

This is **not** a guarantee for a completely unobserved cold page. It removes the
requirement that the full capture ACK has already been published by the App,
while retaining a prior page receipt and native route. If A loses focus before
its pin is created, the press may still be safely refused. No click is retained
for future capture, no late ACK is backdated and no rejected input is replayed.
The pin boundary and original event time are logged separately.

## Executed verification

- Local ARM64 production `swift build --product Riftlet`: PASS (Command Line
  Tools; existing missing XCTest framework prevents local XCTest execution).
- Native test source parsing: PASS, not native test execution. Full XCTest and
  ARM64/Intel packaging are required from the exact admitted PR merge CI.
- `node --test Tests/WebPageProgram/*.test.cjs`: 191 PASS. Synthetic DOM covers
  pin-before-blur/hidden success, one input, distinct pins, late digest, original
  editor/navigation/business A-B-A invalidation, pre-pin focus/visibility A-B-A
  rejection and newly captured subsequent-click eligibility.
- `verify-completion-preview.cjs`: five isolated real Chromium/PNG decoder cases
  PASS. The added pinned target completes exact-content proof. **Headless
  bringToFront(B) left A visible and focused: background NOT_EXERCISED.** See the
  actual focus values in `headless-preview.json`; this is not live ChatGPT.
- New native regressions cover event-time route snapshots, full reply identity,
  original-receiver permission ordering, foreground-independent click authority,
  explicit cancellation, legacy Codable data, unchanged conflict locking and
  pinned input/start/completion observation normalization.

## Still required on the exact App

Real Chrome A-to-B same-window tab, other Chrome window and another application:
NOT_RUN for live ChatGPT. The initial read-only desktop probe encountered loginwindow; subsequent owned native transport checks are recorded below. No ChatGPT upload or user data access was attempted. MouseDown-to-file-input latency,
physical mouse, real selection/old attachment preservation and zero-proof cold
first click have no new MAC_PASS. Production input/start/completion, built-in
upload, Web continuation and safe-retry remain closed; the existing restricted
candidate admission is not expanded. Integrate only after independent source
review and the formal Native/Feedback/source checks; real acceptance is separate.

## Subsequent real transport finding and correction

The desktop later became available. Read-only task inventory showed no other
active desktop test. A bounded owned-localhost fixture then reproduced a concrete
problem: Chrome's native `javascript:` URL setter delivered the file to A, but
raised A's window or activated Chrome over another application. Same-window
inactive-tab delivery did not raise A. This is a transport defect, not a user
selection fault. The initial source checkpoint's independent code approval does
not erase this newly measured failure.

`MainWorldCommandRelay` now installs the reviewed program and native context as a
MAIN closure during foreground capture. Later pin/input/observe commands use
absolute-target execute-JavaScript plus a synchronous DOM event; they cannot
supply code or native context, reinstall a missing background endpoint, or fall
back to the URL setter. Source/context markers, lifetime nonce tombstones,
512 KiB request bounds, original operation guards and ten-second read-only
receipts remain separate checks. DOM correlation is not a security boundary
against malicious same-page code. Only the original installed, exact legacy
session alias can be used for read-only observation.

Actual production relay installer/dispatcher strings were exercised through
native PID-addressed Apple Events on owned localhost fixtures: A received one
additional file change in each of three switches (same-window tab, separate
Chrome window, another application), with A remaining unfocused and no foreground
change back to A/Chrome. The unaddressed B tab had zero changes. Controlled text
remained unchanged; the separate C window counter was not collected. These are
**MAC component results**, not actual ChatGPT uploads or full App clicks.
`native-background-transport.json` preserves both the original failure and the
corrected observations. Its timings include an intentional 100 ms check delay;
they must not be reported as mouseDown-to-input latency or upload speed.

A restarted native store can discover a unique already-installed exact-version
channel, then observe an old operation without installing or inputting. Truly
old pages without an endpoint, changed program markers, unavailable legacy alias
metadata or ambiguous duplicate channels remain safely unavailable until a normal
foreground capture of that original route. No background repair, data migration,
new operation registration or replay is performed. First installation still uses
the foreground-only URL path after an immediate native route recheck; a switch
racing that first installation is not newly proven safe. Subsequent commands do
not use it.

Seven actual JavaScriptCore relay checks passed via a local assertion harness
reusing the new XCTest bodies (not the XCTest runtime): reentrant/expired nonce
replay, missing/foreign/root-replaced channels, payload/context/code boundaries,
read-only legacy alias and restart discovery/adoption. The new XCTest cases are
included in formal CI. The initial G's Intel run failed in unchanged archived
round-two diagnostics (`x.sent` was still undefined after its fixed 15 ms wait),
before native compilation; no old evidence was edited and no gate was bypassed.
The successor source requires its own complete formal runs.
