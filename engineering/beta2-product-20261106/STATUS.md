# Beta2 status

| Stage | Current fact |
| --- | --- |
| PR42 integration | DONE standard merge c72fca78245a15a66ea6beaa980ec141f146bc1b; main push CI 4 success / 1 ARM64 test failure; original receipt timing failure retained |
| Shared native state/commands | IMPLEMENTED; sync edits and per-domain save notifications; XCTest execution pending |
| Six-page settings | IMPLEMENTED; native controls/owners, final native visual fixes under validation |
| Popover/menu/onboarding | IMPLEMENTED; native controls/menu, final native visual fixes under validation |
| Real host integration | IMPLEMENTED first pass; real Main owner receipts/appearance/login/actions; isolated settingsReview added |
| Native/visual acceptance | First packaged run: 13 functional groups PASS, 30/33 frames, PARTIAL plus exit timeout; corrected candidate/restart verification pending |
| Beta2 formal PR/CI/package | NOT_RUN |
| Production install/UI merge | NOT_AUTHORIZED until final appearance decision; Beta1 preserved |

No existing production, historical UNKNOWN, accepted attachment source or original design evidence is replaced. Exact phase evidence will be appended in this directory and private beta2-product-20261106 receipts.

## Checkpoint 1 implementation

- Actual full `swift build --product Riftlet --scratch-path .build-beta2-local -j 4`: PASS, first host build 27.72s; isolated review context build 6.80s. Native XCTest still NOT_RUN locally (CLT does not contain XCTest); formal macOS CI remains required.
- Native new source lanes are being finalized, not visual acceptance. Shared model notification tests and Core original-return receipt bounded wait added; no Core production source changed.
- Independent early review fixes: one clear confirmation owned by Main; deferred geometry wording; configuration persistence before display cancellation; login system state retained alongside system call error.
- Explicit `--settings-review UUID` uses the same binary and real ApplicationController/SQLite/collection/settings owners with a fresh identity-marked root, fixture source, separate defaults, disabled Web/Feedback transport/system capture/login. Normal capture build identity and policy stay unchanged.
- Main push CI failure is not reported green: Native run 42184582609 / ARM64 job127781796945 failed on old `returnedReceipt` scheduling assumption. Raw log and source-order analysis retained privately.

## Checkpoint 2 native inspection and review fixes

The intermediate native workbench was actually opened via CUA. Pause and Hide remained independent and combined status was visible. Dark selection changed native window surfaces; after Quit, the isolated SQLite rows were `capture_paused=true`, `user_hidden=true`, and the appearance JSON was `dark`. Assets/operations remained zero. This was an intermediate debug binary, not final artifact acceptance. Original private observation JSON and launch hashes are retained.

Inspection led to V2-alignment fixes: four native NSSwitch controls with consistent row labels; first settings presentation restores the target 960×684 content size then clamps to the actual screen. A white right-edge area in the CUA image remains unattributed until owned-window capture/frame metadata; it is not declared a product clipping failure or PASS.

Nonauthor source review also closed duplicate clear confirmation, independent login call errors, display-persistence ordering, instance-lock-before-fixture-writes, onboarding display-item identity/tracking, and active editor replacement. Native UI background refresh retains editing controls. New test helpers await actual actions, not a fixed short sleep.

There are 67 methods in the five new UI/Host/environment test files, plus two new existing-model notification tests. Parser/native build success is not XCTest execution. The full same-App settings review driver is now implemented; automated raw-window/native persistence run still pending.

## Checkpoint 3 original native failures and focused corrections

The packaged `45418bba` ARM64 App was executed in a fresh UUID review root. Its 13 real native control/owner/SQLite groups passed, but three popover frames were unavailable and the process failed to exit. The runner correctly reported incomplete. The original report, 30 raw WindowServer PNGs and timeout remain unchanged; sanitized bindings are in `evidence/native-run-01.json`.

Independent review found four visual corrections: popover switch labels had too little width, preview geometry text overlapped the next card, selected position lacked a visible native mark, and onboarding's first window opened at 562 rather than 652 pt. These are focused corrections to the existing V2 implementation, not a new design.

A small actual AppKit reproduction confirmed that the previous `terminateLater` path did not run its MainActor cleanup; returning cancel while cleanup runs and explicitly requesting termination after success exits normally in the reproduction. Main now uses this flow, preserves the existing Feedback save decision, and asks the settings draft sheet before quitting. During approved cleanup the settings host blocks new edits/actions. Actual packaged exit and same-root fresh-process restoration still require the next run. System logout/shutdown acceptance is NOT_RUN; no system preference or logout is performed.

The intermediate CUA observation did not independently prove its process exited. Its recorded persistence remains valid; the later packaged timeout is not erased by an earlier absence from the app inventory.

## Checkpoint 4 normal exit and remaining native findings

The exact `bc903f7141b1218dcd93964cc301fcb911a90bd3` ARM64 candidate (binary `b478590ab9bf2a3ef730a9a32e30df2ef6dd9ad08d1b99d5640bf6ba9dc4211c`) completed the second native run and exited normally in 20.16 seconds. Twelve of thirteen groups passed; onboarding size failed, so the runner correctly did not start the restart stage. All 27 requested frames were written, but independent visual inspection rejected the seven control-center images because the AppKit-to-WindowServer rectangle cropped them. File existence is not visual acceptance. Settings preview caption and selected-position marks were visually confirmed fixed.

CUA with an explicitly UUID-bound test wrapper and the unchanged candidate executable verified Return through onboarding, explicit position selection, Command-comma, custom archive editing, Command-Q confirmation, Continue preserving the draft, and Apply-and-close. The exact scoped process exited and the actual lifecycle file contained 22500 seconds (6.25 hours). Command-W did not trigger closing: the standard responder Close menu route was missing and is now added as a narrow native-menu correction. These observations do not claim physical mouse, real IME, browser upload or final wrapper/package identity.

Onboarding sizing and exact-own-window capture coordinates are being corrected without changing the popover for screenshots. Cached settings colors also need their high-contrast choice resolved from each effective appearance rather than the preference at color creation. New native evidence must validate these corrections; the original run02 and CUA failures remain preserved.
