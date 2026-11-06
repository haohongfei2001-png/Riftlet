# Beta2 status

| Stage | Current fact |
| --- | --- |
| PR42 integration | DONE standard merge c72fca78245a15a66ea6beaa980ec141f146bc1b; main push CI 4 success / 1 ARM64 test failure; original receipt timing failure retained |
| Shared native state/commands | IMPLEMENTED; sync edits and per-domain save notifications; XCTest execution pending |
| Six-page settings | IN_PROGRESS; new RiftSettingsCenter files owned by review |
| Popover/menu/onboarding | IN_PROGRESS; new RiftControlCenter/RiftOnboarding files owned by diagnostics |
| Real host integration | IMPLEMENTED first pass; real Main owner receipts/appearance/login/actions; isolated settingsReview added |
| Native/visual acceptance | NOT_RUN; real App driver being implemented |
| Beta2 formal PR/CI/package | NOT_RUN |
| Production install/UI merge | NOT_AUTHORIZED until final appearance decision; Beta1 preserved |

No existing production, historical UNKNOWN, accepted attachment source or original design evidence is replaced. Exact phase evidence will be appended in this directory and private beta2-product-20261106 receipts.

## Checkpoint 1 implementation

- Actual full `swift build --product Riftlet --scratch-path .build-beta2-local -j 4`: PASS, first host build 27.72s; isolated review context build 6.80s. Native XCTest still NOT_RUN locally (CLT does not contain XCTest); formal macOS CI remains required.
- Native new source lanes are being finalized, not visual acceptance. Shared model notification tests and Core original-return receipt bounded wait added; no Core production source changed.
- Independent early review fixes: one clear confirmation owned by Main; deferred geometry wording; configuration persistence before display cancellation; login system state retained alongside system call error.
- Explicit `--settings-review UUID` uses the same binary and real ApplicationController/SQLite/collection/settings owners with a fresh identity-marked root, fixture source, separate defaults, disabled Web/Feedback transport/system capture/login. Normal capture build identity and policy stay unchanged.
- Main push CI failure is not reported green: Native run 42184582609 / ARM64 job127781796945 failed on old `returnedReceipt` scheduling assumption. Raw log and source-order analysis retained privately.
