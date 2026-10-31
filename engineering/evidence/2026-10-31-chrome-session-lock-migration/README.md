# Chrome process identity integration: unresolved-operation lock correction

The initial process-identity source d82a70951feb0137bddb4b31b4b14248548acca9
and admission af68d8e80af2951a0ba8cbfdfcb9a2a09e3d9710 are superseded for
integration by this additional correction. Main base remains
60eaaef64848fc5535580e4fcb65e45f3f41e814. Earlier source-review PASS did not
cover the cross-format dispatch conflict; it was withdrawn before merge.
Historical reports and all prior evidence remain intact.

## Confirmed defect and correction

TargetLease.serializationKey includes the session spelling. A legacy unresolved
operation and a new kernel-session operation in the same live Chrome PID/tab
could therefore evade conflictsForDispatch. No user operation was dispatched
with that candidate. A synthetic regression fails on the prior source.

Mixed legacy/kernel spellings now conservatively conflict for the same valid
PID, adapter, Chrome Web Chat surface and nonempty tab. The existing recognized
business-draft comparison still permits distinct drafts of the same recognized
profile. Missing, unrecognized or cross-profile logical identity keeps the tab
locked. This is a conservative lock relation, not proof of process equality.
PID reuse across formats can conservatively overblock; it cannot grant input.
Same-format lifetime behavior remains unchanged. Session parsing is canonical
and strict. Receipt equality, serialization keys, persisted targets and original
operations are never rewritten; kernel time never reconstructs a legacy date.

## Limited validation

- Baseline FAIL: first mixed-format conflict assertion fails with old Models.swift.
- Local PASS: seven committed test bodies executed against actual Core/SQLite
  sources via a standalone assertion shim, 97 assertions. This is not XCTest.
- Cases cover symmetric mixed locks, immutable receipt identity, recognized
  different drafts, malformed sessions, real temporary SQLite second connection
  and reopen, A-to-B-to-A, missing legacy logical identity, and concurrent
  mixed-format dispatch where exactly one operation acquires the lock.
- Full ARM64/Intel XCTest, Feedback and exact-source CI must run on the successor
  reviewed merge. Earlier candidate CI cannot clear this new source.
- Real screenshot/cold-click/selection acceptance of the corrected unified App
  remains NOT_RUN at this source checkpoint. No real Chrome interaction or
  original UNKNOWN input was performed for this correction.

## Boundaries

One Core conflict predicate and its tests supplement the existing five-file
process resolver change. No SQLite schema/data migration, target rebinding,
retry, page algorithm, source policy, UI or Feedback behavior is changed.
Production input/start/completion, built-in upload, safe-retry and continuation
remain closed; the existing restricted candidate scope is unchanged.
All original images, UNKNOWN, media and audits remain preserved. Only synthetic
temporary SQLite files are used in these regressions. Public evidence contains
no real targets, private paths, chat content, image data or raw logs.
