# Beta2 status

| Stage | Current fact |
| --- | --- |
| PR42 integration | DONE standard merge c72fca78245a15a66ea6beaa980ec141f146bc1b; main push CI 4 success / 1 ARM64 test failure; original receipt timing failure retained |
| Shared native state/commands | IMPLEMENTED; sync edits and per-domain save notifications; first formal Native XCTest jobs running |
| Six-page settings | IMPLEMENTED; real native controls/owners; scoped visual and keyboard results retained; final acceptance pending |
| Popover/menu/onboarding | IMPLEMENTED; guide sizing fixed; full programmatic popover run still FAIL, actual status-item input NOT_RUN through available tool |
| Real host integration | IMPLEMENTED; real Main owner receipts/appearance/login/actions and isolated settingsReview; independent persistence restart PASS for exact d72 candidate |
| Native/visual acceptance | run01–run06 retained separately; run06 9 PASS / 4 FAIL and runner timeout; scoped CUA/visual/restart results do not overwrite it |
| Beta2 formal PR/CI/package | Draft PR43 opened at 974e0bc; initial CI active, inherited source gates FAIL; ARM64 intermediate packages exist; final G/H/CI/App/ZIP pending |
| Production install/UI merge | NOT_AUTHORIZED until final appearance decision; Beta1 preserved |

No existing production, historical UNKNOWN, accepted attachment source or original design evidence is replaced. The chronological checkpoints below retain their facts at that time; the latest checkpoint and table describe current scope. No `BETA2_REVIEW_READY` or `PRODUCT_READY` claim is made.

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

## Checkpoint 5 source corrections verified; driver activation evidence pending

At `ea312a6`, all six onboarding frames reached the intended 652×608 pt and independent visual review closed the first-size finding. The same cached colors now resolve from the appearance supplied by AppKit; native light/dark tokens were checked, while high-contrast matching fixture tests remain distinct from an actual system preference switch. CUA confirmed Command-W invokes the native sheet after the dirty state was independently observed, Continue preserves it, and Quit/Discard exits while retaining the prior 24-hour archive value.

Run03 retained a driver click-before-enabled failure. At `4174a04`, the driver now waits for actual enabled controls, and successful popover captures wait for a full-sized stable WindowServer window. Run04 produced complete normal/paused/save-failure popover images but two presentations closed before capture, so the full run remained FAIL and restart was not attempted. The available evidence does not establish why those two popovers closed. The next driver-only correction waits for the settings window's existing activation request and records bounded activation/popover notifications; it adds no product focus gate or repeated-click recovery.

## Checkpoint 6 preserved failures, independent restart and formal Draft PR

Separate sanitized bindings now preserve [run04](evidence/native-run-04.json), [run05](evidence/native-run-05.json) and [run06](evidence/native-run-06.json), including original report/runner/review hashes. Run04 has 11 PASS / 2 FAIL and normal exit, with scoped independent approval of three complete control images. Run05 has 9 PASS / 4 FAIL and a runner timeout; a draft left by its failed case awaited quit confirmation. The source/timeline review approved only removal of the unconditional resign observer and one regression, retaining native transient and explicit closure paths.

Run06 executes that exact `d72f966` source. The first light popover remains visible through handback and is captured at full geometry; later programmatic opens still close prematurely. It remains 9 PASS / 4 FAIL, 26 PNG / 3 NOT_RUN, and runner INCOMPLETE after 180 seconds. Its actual completed report was retrieved from the same root and verified against process/runtime identity; the runner's missing stdout path is not fabricated. The remaining cause is unresolved; additional work is limited to bounded driver diagnostics.

[CUA using the exact original d72 App](evidence/cua-native-exact-d72f966.json), without a wrapper, observed isolated startup, guide Escape and original process absence after Command-Q. The tool could not expose the status bar; real status-button opens, second-click closure and outside-click dismissal remain NOT_RUN. Quit's tool timeout supplies no normal exit code. This is a tool/evidence limitation, not a new proven product defect.

[Independent restart-only verification](evidence/independent-restart-d72f966.json) used the same original package/root and a different process after the run06 process was absent. It exited 0 in 0.466 seconds; five JSON files and loaded owners, SQLite pause/visibility, one media/asset mapping, zero operations and zero START remained equal, and first-use UI did not reappear. This scoped PASS does not alter run06 FAIL or assert the formal runner's successful-first-run restart path passed. No UI action, browser, production root, login or permission mutation occurred.

[PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) is Draft, initial head `974e0bcde40f3f4d25ef1f1bbe0acc7d74575dc0`, base `c72fca78245a15a66ea6beaa980ec141f146bc1b`. At 2026-11-06 10:56 UTC the first [Native run 42205691399](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691399) has source admission FAIL and ARM64/Intel unit steps in progress; [Feedback run 42205691613](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691613) has source admission FAIL and native/service SUCCESS. The Feedback historical composition step is skipped. The source record is still inherited from PR42; final source review and admission-only H remain required. Independent build/CI/package work continues while native diagnosis remains accurately scoped.
