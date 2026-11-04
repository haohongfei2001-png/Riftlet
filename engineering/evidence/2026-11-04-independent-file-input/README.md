# Independent screenshot file input — 2026-11-04

This source replaces the PR #35–#40 upload-qualification path for the ordinary
product. It starts from main `cd9b69537fa9d0e405824fd55d98f6d15a87df3d`.

## Actual incident

The installed PR #40 relay had a separate action allowlist that omitted
`prepareInputResource` and `releaseInputResource`. Seven preparation commands
returned before the page function ran or a nonce receipt was written. The host
then exhausted its one-second receipt budget and reported `invalidReply`.
No new setter/change occurred for these seven attempts. Their measured receipt
execution durations were 964–1,032 ms. The preceding attachment's later UNKNOWN
was not the cause. The sanitized read-only findings and original-relay
reproduction are recorded in `incident-summary.json`.

## Replacement behavior

Each click pins the last observed Chrome window/tab and its original usable
composer before the press. The native route is checked again, and the page
checks the same document, path, editor and unique enabled PNG file input.
Official ChatGPT origins with usable composers are accepted regardless of path;
there is no pathname catalogue or React identity qualification.

The host verifies only the current private PNG, transfers its chunks and invokes
one commit. The page constructs one native File/DataTransfer, calls the native
files setter and dispatches one change. Only that synchronous execution owns
its input control. A retained FileList is neither cleared nor re-proved.

A new attachment in the original composer, correlated to this operation's
unique filename or current File preview URL, produces START when it has an image
source or upload indicator and no associated error. Image decoding, preview
size, progress completion and server confirmation are not required. Bare setter
return, filename placeholders and error nodes are not START. The thumbnail
swallows on START and this version stops observing that attachment.

If the commit reply is missing or malformed, only the original operation is
observed; commit is never resent. A new screenshot has its own independent
operation even if this one remains UNKNOWN. A target change or currently busy
synchronous setter yields an explicit no-input retirement, never a different
chat or an overlapping setter.

The ordinary loader does not run historical observer wrappers. Existing
SQLite schema v3, old receipts, checkpoints, UNKNOWN rows and media remain.
Current acceptance evidence uses an additive receipt field so the retained
PR #40 App can still decode the database after rollback.

## Verification boundaries

- New page-command VM regressions count actual setter/change/START, append
  outcomes, retained files, delayed START, missing replies, stale targets and
  preservation of text/selection/old cards. Legacy read-only fixtures remain.
- A separate native Chrome fixture uses a fresh temporary profile, a loopback
  page and actual File, DataTransfer, FileList, DOM events and Selection. It
  never connects to ChatGPT, the user's Chrome profile, CDP or Apple Events.
- Swift tests cover coordinator execution release, old UNKNOWN independence,
  once-only adapter dispatch, receipt recovery, all enum actions through the
  installed relay, and old-App receipt decoding. Full execution is recorded
  by the required ARM64, Intel and Feedback CI jobs.
- The original Mac has CommandLineTools without XCTest. Its product build
  succeeded; its full Swift test run was unavailable for that environment.
- Real ChatGPT and Project application semantics: **NOT_RUN**. User-operated
  normal use is the final acceptance; controlled application fixtures do not
  establish the inaccessible real application's current behavior.
