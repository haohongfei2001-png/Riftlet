# Browser-owned click-time witness comparison

This is a bounded **offline architecture experiment**, not a replacement Chrome
bridge, extension, native click forwarder, or production upload feature. None of
its modules are imported by the App. It compares the authority available at two
different entry surfaces when the host has **no complete target ACK**:

- **A — original native entry:** a pre-existing page witness alone cannot prove
  which page/draft owned a separate native click. The comparison model refuses.
  This branch does not execute AppKit or measure a host event.
- **B — alternate page-owned entry:** Chromium actually routes a trusted
  `pointerdown` to a thumbnail button inside the same document as a previously
  completed witness. The handler freezes that witness, verifies the matching
  release, and validates only the frozen target after an asynchronous asset
  response. It can perform one synthetic fixture input without a host target ACK.
- **C — no page witness either:** the event is refused. Publishing a witness later
  does not replay the event. Startup and not-yet-installed monitoring still have
  this gap.

**B changes the input surface. It does not solve the original NSPanel cold-click
gap or preserve the approved native-only interaction unchanged.** An extension
toolbar popup, browser side panel, or forwarded AppKit event is a different
document/context; the B result does not cover any of them. No extension was
installed and no Native Messaging transport was used in this experiment.

## Run

Use the existing exact Playwright lock; no new dependency set is introduced:

```sh
cd Tests/ColdClickBrowser
npm ci --ignore-scripts --no-audit --no-fund
npx --no-install playwright install chromium --only-shell
cd ../..
node engineering/experiments/click-time-witness-20261029/browser-lab.mjs
```

Node 22 or later is required by the existing package. The runner rejects a
Playwright version other than **1.62.1**. A developer can explicitly supply an
existing testing binary via `RIFTLET_TEST_CHROMIUM`; the result always reports the
actual versions. It never attaches to or discovers a user's Chrome instance.

The launcher uses headless mode with a fresh temporary browser profile and a new
nonpersistent context. The context is offline, service workers are blocked, and
only the single inline synthetic fixture document is fulfilled by routing; every
other request is aborted and fails the test. A ChatGPT-shaped URL is used solely
to exercise the unchanged production page surface check. No ChatGPT server,
account, user browser profile, system screenshot, database, native queue, or
upload endpoint is involved. Execution has a 60-second bound and closes the
browser in `finally`.

## Authority and identity constraints

`witness.js` is a standalone lab protocol. `publishWitness()` is called before an
event by the fixture observer. It invokes the **unchanged current production page
program** to capture and validate a target, then stores an immutable copy and a
completion timestamp. The original document nonce, target/business identity,
monitor generation, original form/editor/input/entry references, asset hash,
attempt and visibility revision are bound to it. Host permission and connection
epochs are explicitly **simulated fixture values**, not real Chrome metadata or
host authorization evidence.

Neither pointer handler calls `captureTarget`. The original target is validated
through the production program, which drains its existing monitor. Event checks
require a primary left mouse pointer, exact original button and composed path,
the same document, visible/focused page, and:

```text
witness.completedAt < pointerdown.timeStamp <= handler.performance.now()
```

These are all timestamps from one renderer/time origin. Equal timestamps are
rejected. There is no renderer/host subtraction, clock conversion, backdating, or
late ACK publication. `isTrusted` in this run means a browser-dispatched **CDP
software pointer**, not an artificial `dispatchEvent`, and not a physical human
mouse.

Only a matching pointer release can request the synthetic asset. A bounded
response must echo the original request, document, witness, operation, target,
asset, attempt, hash and host epochs. The returned bytes are hashed independently.
Permission loss/recovery and connection changes invalidate the old epochs. The
final synchronous guard validates the exact original target object and current
eligibility; it never selects the current chat as a substitute. A consumed asset
ID remains consumed if the sink throws or becomes unknown; changing its attempt,
hash or visibility revision does not grant another input. A boundary after sink
invocation is `UNKNOWN`, never a pre-input refusal, and a late sink reply cannot
promote it to success. There is no automatic replay, safe retry, or waiting for a
future target. This ledger exists only in the current lab instance's memory;
reload/restart and durable UNKNOWN recovery are untested, so it is not production
deduplication or recovery evidence.

The synthetic sink alone uses the existing `begin/chunk/commit` program, producing
one actual Chromium `File`/`change`. An additional deliberately deferred sink
simulates an uncertain invocation without calling any input protocol or File
change. Sink invocation counts are distinct from actual fixture inputs. Input is
explicitly reported separately from
`productionInputAuthority: false`, `liveInputAuthority: false`, and
`productionAdmission: false`. That fixture operation reaches only `inputTriggered`;
the lab does not manufacture `uploadStarted`, attachment completion or a profile.

## Recorded result and scope

`browser-result.sanitized.json` records the bounded reviewed run on Chromium
151.0.7922.34 with Playwright 1.62.1. The production page source hash is included.

- B performed exactly one synthetic input. Its witness completed 31.5 ms before
  the actual browser event; the handler ran 0.3 ms after it. Nonempty text,
  noncollapsed selection, unfocused editor and original attachment DOM objects
  were retained. Repeated/double clicks did not input the same asset again.
  Changing attempt and visibility revision, then independently publishing a new
  witness, still did not reauthorize that consumed asset.
- An earlier capture listener deliberately held the renderer and published a
  witness **16.9 ms after the original event**. The later entry handler rejected
  it. Another delayed-handler case performed business A→B→A, and the original
  production root monitor rejected the witness.
- Truly absent witness, untrusted dispatch, release outside the original control,
  business ABA while awaiting bytes, host/permission epoch changes, asset revision
  change, editor replacement, active modal and a real frame-focus round trip all
  caused zero input. Wrong request/attempt/hash and changed bytes also caused zero
  input. None reacquired a target after the original event.
- An observation-only deferred sink had already been invoked when a real focus
  boundary occurred. Its result remained `UNKNOWN` after a late resolution; no
  success receipt or second sink invocation appeared. This extra case made no
  File input.
- The Window focus test uses actual Chromium focus between an inline child frame
  and the top-level page. It is **not** macOS application/tab activation evidence.

The React business ancestry is a controlled fixture. Real ChatGPT DOM changes,
system screenshot ingestion, original native NSPanel interaction, permissions,
physical mouse, extension/native host security, and upload start/completion are
**NOT_RUN** here. Pointer cancel/capture loss paths are fail-closed in the lab but
are not claimed as separately measured physical scenarios. A page that silently
changes business identity outside the existing monitor's observable contract is
not proven safe by this experiment.

The result supports a narrow architecture distinction: browser ownership of the
original event can remove one cross-context attribution step **when a complete
page witness already existed**. Metadata push alone does not supply that event
ownership. Product adoption would require a separate interaction decision,
trusted browser/host asset channel, installation/security work and live evidence;
this lab grants none of those admissions.
