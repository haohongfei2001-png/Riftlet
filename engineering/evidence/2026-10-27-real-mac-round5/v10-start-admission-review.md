# v10 controlled synthetic start admission — independent review

Date: 2026-10-27. Source: `0659e1cc603b1963367a2ba3a032414eeb5ad2ed`.

**Decision: sufficient evidence to admit this start profile only for a controlled, temporary synthetic App acceptance run.** This is permission to test visual exit with generated images, not a completed visual-exit acceptance result. Production start/completion and retry admission remain closed. The integration lead performed the real Mac actions; the independent reviewer read source, regression results and private local evidence without operating the GUI.

## Observed evidence

- Original operation: `5B303B81-3FA6-46DF-A27F-B1091D0A3954`; asset: `F8EEA909-ECFA-4647-ADC7-C9F4C93ADF73`; attempt: `1`.
- Page `inputCount=1`. The native trace contains one selection boundary (`accessibility`), one `begin` and one `commit`; chunks are transport parts, not repeated inputs. The AX helper returned success with the same foreground PID before/after, `physical=false` and `attachmentResultVerified=false`.
- Original progress increased from `2.2689483164749897` to `6.35305528612997`. `startSequence=12 > inputSequence=2`; page monotonic start `281190.10000002384 ms` minus input `279356.10000002384 ms` is **1834 ms**. These are document-clock times, not host/UI latency measurements.
- Start evidence ID `bb4bc261-9dd8-4a09-ba60-c4b4577a4c66` matches between the page and the persisted native receipt. Operation, asset, attempt and asset hash also match. The receipt reports `uploadStarted`, `isUploading=true`, `belongsToOriginalDraft=true`, `positiveReady=false` and `safeToRetry=false`.
- The first run used only the temporary synthetic accessibility metadata patch, with no start grant. Core persisted `unknown` and kept the asset `visible`. This is a successful negative admission check, not a visual-exit pass.

The complete target and original attachment ID remain in private evidence. Public correlation uses SHA-256 only: target sorted-key compact JSON UTF-8 digest `ec04dc4df726617682ef0070151572c471ec628f4bba4a29dc6f61f8550da586`; original attachment ID UTF-8 digest `874187b39765fe4e2a7658a89afa269deaf9b5880518e9ce974e3a3b1d7f6198`. The target digest agrees with the native selection trace. No browser session identifiers, private paths, screenshots or chat content are reproduced here.

## Boundaries and unresolved outcomes

The later page snapshot has no final proof, no current progress node, `uploading=false` and `startDisqualified=true`; a later persisted receipt is `inputTriggered` while the operation remains unknown. A stored historical start is not current uploading or successful completion. This review does not label the upload successful, authorize another input, or treat a missing progress indicator as safe termination.

The reviewed running log also contained capture `invalidReply` and observe `nativeEventFailed(-1728)` diagnostics, plus a sandbox warning. The observe errors lack operation correlation and are **not attributed to the new image**. Their cause is not established by this review. They neither erase the earlier persisted start receipt nor justify replay; the session is not described as error-free.

The v10 source permits only initial missing progress to wait on its original node. The first finite sample is a baseline; a second strictly larger finite sample below 100 is required, alongside original identity, file-hash and single-input checks. Finite-to-missing transitions, coalesced regressions and node removal/replacement revoke start eligibility. Independent synthetic regression execution passed 66 current-page and 35 legacy tests. Historical v6–v9 observation remains schema 1 and cannot mint new start evidence or input rights. These tests do not establish production, physical-click, business-ABA or network-fault acceptance.

## Subsequent controlled run — not yet accepted

The allowed temporary App overlay grants only `chatgpt-web-zh-progress-start-development-20261027-v1` for synthetic Web acceptance. No production or retry profile is admitted. The subsequent fast build/run is owned by the integration lead; this document records **no PASS for that future run**.

Prepared build provenance: base `0659e1cc603b1963367a2ba3a032414eeb5ad2ed`; synthetic metadata patch SHA-256 `d9638001fc0afb8bfbc13ad9b9f36a66ebc8289121c71b07d75058fd7b3ca7f0`; App acceptance overlay SHA-256 `f686da6cf50b0f1c4e10d0d952b0ab88a4489a0120aefb9e7a4a27a9b0dbfea6`. Both patch hashes were independently read from the evidence files. The lead reported executable SHA-256 prefix `51c999a`; the full executable digest was not independently verified in this review. Build provenance is separate from runtime acceptance.
