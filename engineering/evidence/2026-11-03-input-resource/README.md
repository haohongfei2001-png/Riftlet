# Legacy UNKNOWN and current input execution — 2026-11-03

Continues PR #37 from `490704292b83b66d975f0fdbdaf0193cc95e3dc1`,
base `4c3175dd3c537466279d27844466fbe65f79eb6e`.

## Reproduced defect and implementation

`validatedDispatchOperation` previously required every unresolved same-draft
operation to carry an admitted immutable continuation START from the same
coordinator. A legacy START/UNKNOWN with no request fields could never satisfy
that rule, even after its input call ended.

The native dispatch call now records its input-execution return separately from
its receipt. The adapter can prepare the **next** click against the actual
current input: native FileList empty, native value empty, no still-running
same-node stage/commit across retained known page registries, exact click and
operation identity. A one-use reservation is passed through durable B intent
to BEGIN and rechecked synchronously before the original single File setter.
No code clears the picker to make it qualify. Existing cards and text/selection
are checked at input; independent START/UNKNOWN/COMPLETE remain unchanged.
An unused lost preparation can be superseded without allowing its stale BEGIN.
Legacy records are not rewritten, replayed, promoted, deleted or resurrected.
Missing resource conditions immediately retain B and report a pre-input refusal.

Broad ownership checks retain legacy A's attachment ID across new click pins.
Document-local numeric request counters are not compared across a refresh;
unique ownership IDs and original attachment IDs remain exclusive.

## Validation scope

The incident shape comes from the user's supplied incident facts and PR #37's
read-only Mac summary. This Linux session did not read the user's Mac files or
production SQLite. New SQLite fixtures contain synthetic media/identities only.
They preserve the exact old operation/asset/START/checkpoint bytes while B/C/D
use their own selections, invocations and resources. Both absent-call and old
version1-call-without-new-fields variants are covered.

The new 2/3/5-input Web incident counterexamples fail against the old page source
with `ORIGINAL_OPERATION_REQUIRED`. Current controlled Web and native regressions
exercise empty/occupied input, pending hash/change, lost/stale/reentrant tokens,
refresh/restart, late receipts, ownership collisions and current text/selection.
FormData, copied Blob and pre-cached transport fixtures deliberately have no
request ownership evidence; the new path does not infer their requests absent.
Direct original File request observation remains the separately typed old path.
The hermetic Chrome fixture executes actual native FileList, File, Blob,
FormData, Request, Selection and WebCrypto with a synthetic local application.
It uses a new temporary profile and a dedicated loopback fixture only, with no
attachment network upload or real ChatGPT session. The parent process waits for
the actual final assertion report in bounded wall time; a DOM snapshot with
unfinished asynchronous work cannot pass. macOS CI requires Chrome; this Linux executor reports
CHROME_NOT_RUN because no native Chrome binary is installed.
Exact completed CI, native tests and package identities are recorded in PR #37.

## Real-platform boundary

Archived authorized Home observations show two same-input changes 44.7 ms apart
with both attachments uploading and three sequential inputs retaining cards,
text and selection. They do not record a native empty-picker reset, and are not
a fresh test of this source on today's persisted-thread route. The Browser
connection in this turn returned `originating browser context` unavailable; no
shell, CDP or Apple Events fallback was used to reach a real ChatGPT page.

The implemented recovery is conditional on a currently empty, verified native
picker and a settled original input execution. Nonempty input with no original
independence proof, pending/ambiguous legacy execution or lost target continuity
still refuses before input. A controlled handler's post-input mutation is
detected, not reversible proof that arbitrary platform code cannot remove an
attachment. Fresh AppKit-to-current-ChatGPT A-UNKNOWN then B/C acceptance remains
required before claiming the user's exact live incident is finally resolved.
