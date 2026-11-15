# Independent diagnostics review — 2026-11-15

Reviewer: `/root/final_diag_review`, not the implementation author.

Result: **NO BLOCKING FINDINGS in the five-file diagnostics-only working diff.** This is a source and controlled-command review; it does not admit Edge upload START/completion or establish commercial acceptance. Final immutable source checkpoint/admission review is pending the integration lead's complete G SHA.

Reviewed baseline: `c3278c0bea1c03dc8cfc445fd7678a3de3467ae1` in `build/universal-attachment-20261114`. Exact five-file hashes, frozen-source checks and timestamp are in `reviewed-source-hashes.json`.

## Scope and findings

- The Edge sidecar remains outside `AttachmentObservationEnvelope`, operation decisions and journals. Its Swift decoder accepts an exact numeric/boolean field set, bounds node counts and percentages, caps sidecar/summary bytes, and drops malformed optional diagnostics without rewriting a valid observation. Emitted trace fields have a separate `edge` prefix and contain no draft text, filenames, URLs or exception messages.
- Baselines retain the original editor/form/document, route/navigation and target in the document. Sampling checks those identities and the saved operation invocation before exporting facts. A later capture cannot replace the baseline retained by an existing operation. The baseline is taken by `captureTarget`; it is not independent proof of text/selection at an earlier physical mouse-down timestamp.
- The repaired scanner accepts only a declared form/composer, rejects body/html and historical ancestors, prunes recognized transcript/ancillary/nested editor and composer subtrees, and uses one bounded traversal for candidates/previews/indicators. Its original draft-text snapshot is limited to 65,536 characters and its per-pass traversal/candidate budgets are 2,048/512. No diagnostic descendant query escapes that traversal. This is a bound on the new scanner and exported facts, not a claim that unchanged application code performs no wider DOM queries.
- A failing or missing diagnostic snapshot neither prevents responsible input nor authorizes another setter. The optional sample can report failure/limits without promoting its partial facts to receipt evidence.
- Every pre-existing JavaScript line is retained (164 insertion lines only). The entire JavaScript `sample` function, including Edge's early return, is byte-identical to the reviewed baseline. `WebAttachmentAdapter.swift`, its Edge normalizer guard, `AttachmentObservation.swift`, the historical v17 observer, Chrome executor/router, transfer coordinator, App main and panel controller are byte-identical. Existing Chrome behavior and the PR #101 picker ownership rules therefore receive no rewrite in this increment.
- The added JavaScript tests are required by the existing CI entrypoint; the new XCTest file is under the existing adapter test target. This wiring is not itself a new CI pass.

## Independent execution

Ran `independent-probes.cjs` once against the reviewed working source; four probes passed. Raw structured results are `independent-probes.json`.

1. Read traps across 13 excluded subtree classes: zero diagnostic historical-content reads and zero diagnostic DOM mutations, while the intended original input completed exactly one setter/change.
2. Original browser process-session mismatch followed by five observations: no original-draft or progress claim; setter/change stayed at one.
3. A mismatched saved diagnostic invocation supplied no sidecar and did not change the underlying input receipt.
4. Ready/loaded/100%-progress appearance followed by five observations remained `inputTriggered`, with no START/completion evidence or retry admission; a second commit was refused and setter/change stayed at one.

`git diff --check` passed. Full prior CI was deliberately not repeated. This reviewer did not run Swift XCTest, native AppKit events, Apple Events, a browser, commercial uploads or signing/install tests. Their outcomes must remain separately recorded by the integration lead.

## Limits and handoff

No source/ref/remote/GUI mutation was made by this reviewer. Only this review directory was written. The reported PASS results apply to controlled diagnostics and preserved source boundaries, not the user's two-image commercial acceptance criteria. Keep PR #69 Draft and Edge START/completion admission closed until separately obtained real evidence supports them. Revalidate these exact hashes against the final source checkpoint before recording source admission.
