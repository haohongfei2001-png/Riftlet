# Cold-click page regression in headless Chromium

This runs the actual bundled page program in a fresh, nonpersistent Chromium
context. All content is a local synthetic fixture. The context is offline,
service workers are blocked, and routing fulfills only the one fixture document
from an inline string; every other resource request is rejected and fails the
test. No ChatGPT server, login, user browser profile, native database, screenshot,
or upload endpoint is used. The ChatGPT-shaped URL exists only to exercise the
program's unchanged surface check.

```sh
cd Tests/ColdClickBrowser
npm ci --ignore-scripts --no-audit --no-fund
npx playwright install chromium --only-shell
npm test
```

Playwright is exactly pinned by `package-lock.json`. The default run uses its
matching downloaded headless shell. A local developer may explicitly set
`RIFTLET_TEST_CHROMIUM` to an already installed **testing** binary to avoid a
second download. The JSON result reports the actual driver and browser versions;
such a local run is not relabelled as the default pinned-browser CI run. The
launcher always requests headless mode, creates its own temporary browser profile,
and never attaches to a running Chrome process.

The five cases cover:

- Forty empty-lease focus cycles retain one state, return fresh target objects,
  reject old targets, and do not input a file. Original returned target objects
  remain unchanged.
- A real modal outside the composer rejects capture and old-target input.
- Actual browser clicks on body/sidebar controls leave the same composer usable.
  One `begin/chunk/commit` then produces exactly one `File`/`change` with the exact
  synthetic PNG bytes, while preserving nonempty text, noncollapsed selection,
  unfocused editor, and the original attachment DOM object. Repeated commit is
  rejected. The state must be `inputTriggered`, never a fabricated start/complete.
- Once an operation exists, focus rearming preserves its original state and
  identity. Read-only observation still resolves the old operation; new input
  cannot reuse it.
- A controlled business A→B→A root commit invalidates the old binding and proof
  while retaining the original operation and unique input count.

The browser supplies real DOM nodes, range selection, native modal behavior,
`MutationObserver`, `File`/`DataTransfer`, cryptography, and trusted Window focus
events. Only the React business ancestry is an explicit, bounded fixture; this
does not validate current ChatGPT React implementation.

Headless tab `bringToFront()` does not reproduce OS app activation in the observed
environment. The test therefore obtains actual `isTrusted=true` Window blur/focus
events by clicking between a local child iframe and a top-level body button. It
asserts both event identity and order, without manually dispatching focus events.
It **does not** claim macOS app/tab activation, Apple Events, pre-event ACK,
AppKit/physical mouse, real system screenshots, or actual upload start/completion.
The attachment's programmatic `change` is correctly recorded as untrusted, not
human input. No renderer timestamp is subtracted from a host timestamp.

Execution has a 60-second overall bound and emits a compact JSON result with
source SHA-256, actual versions, case outcomes, and explicit untested scope.
No private source content, paths, browser sessions, or credentials are output.
