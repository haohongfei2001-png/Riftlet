# Riftlet restricted screenshot candidate — independent CI safety review

Reviewer: non-author `/root/admission_safety_review`.

**Decision: PASS for the complete macOS software verification of `34caed4a5c5b7264c1699b62ea1438e1ce5646ca`.** This is separate from live screenshot evidence and does not declare the new candidate's fresh-screenshot fast-swallow interaction tested.

## Exact revision and run

| Item | Independently verified value |
|---|---|
| Direct candidate source SHA | `34caed4a5c5b7264c1699b62ea1438e1ce5646ca` |
| Git tree | `d1b5c73c4d3c7eda94c7675a18f87b1ee08bafcf` |
| Parent | `375f52d84007ea6644ddcc0380fa52a3591c74ab` |
| Primary workflow | [Native foundation push 40673128250](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40673128250) |
| Primary job | `122764686050`, `macos`, completed/success |
| Corroborating PR workflow | [40673134992](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40673134992), completed/success |
| Actual primary checkout | `git log -1 --format=%H` in the log prints `34caed4a5c5b7264c1699b62ea1438e1ce5646ca` |
| Runtime | macOS 14.8.9 / build 23J631, arm64; Apple Swift 5.10; Node v22.23.2 |
| Reviewed complete log | `engineering/evidence/2026-10-28-sc-restricted-admission/ci-40673128250-success.log` |
| Complete-log SHA-256 | `4388ddd293cbce26d7ef8dc0ac561ae46d918779c117a5906fb27232e2c5fdc2` |

I independently queried the GitHub connector for the primary run's jobs and the candidate commit's PR runs. The primary job and all 18 returned job steps report completed/success, including the native test, detailed outcomes, packaging and executable-check steps. The PR run also reports completed/success. My detailed log review uses the **push run's direct source checkout**, not a PR synthetic merge or the earlier `48574df` source CI.

All 9 previously reviewed implementation-file SHA-256 fingerprints were rechecked against the `34caed4a5c5b7264c1699b62ea1438e1ce5646ca` Git blobs and still match exactly. The only change from `375f52d` is the single constructed-test `uploadStart.evidenceID` correction to a valid UUID. The production decoder, admission implementation, Core, App and bundled page did not change. The page remains byte-identical to the `48574df` blob with SHA-256 `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`.

## Complete native and detailed outcomes

The primary native run compiles successfully and contains exactly **457/457 parallel test execution entries**. It completes successfully and the job proceeds to later gates. There are no XCTest errors or failed test cases in the complete log.

Parallel discovery output alone does not distinguish every possible skip. The workflow therefore reruns its 17 relevant suites with detailed per-case outcomes. I counted **120 explicit passed test cases**, zero explicit skips and zero failures across those suites:

| Detailed suite | Explicit passed cases |
|---|---:|
| `RiftLifecycleTests` | 13 |
| `RiftInputIslandTests` | 3 |
| `DeferredChromeActivityBindingTests` | 3 |
| `RiftSetupControllerTests` | 3 |
| `ReleaseCaptureTests` | 15 |
| `PresentationBoundaryTests` | 4 |
| `WebAcceptanceIntegrationTests` | 5 |
| `PassivePermissionResumeTests` | 8 |
| `ChromeActiveTabDescriptorTests` | 5 |
| `AcceptedSelectionQueueTests` | 18 |
| `SelectionAuthorityTests` | 4 |
| `SelectionSubmissionQueueTests` | 3 |
| `SystemScreenshotWebCandidateTests` | 7 |
| `SystemScreenshotCandidateAdmissionTests` | 13 |
| `SystemScreenshotObservationJournalTests` | 8 |
| `SystemScreenshotCandidateIntegrationTests` | 6 |
| `SystemScreenshotFidelityTests` | 2 |

### Permission wakeup and original click authority

The actual detailed log passes all three deferred Chrome binding cases: one binding is consumed by the first completed capture regardless of success; an old completion cannot steal a later foreground binding; repeated signals coalesce and stopped work cannot restore an old binding. The 8 passive-permission tests pass, including recovery after browser unavailability, waiting for an old call while refusing its grant, denying unrequested/denied grants, dropping late granted results after stop, and retaining cancellation while resume awaits.

The 18 accepted-selection queue tests pass, including strict ACK-before-original-event, no post-event ACK filling, no permission borrowing from another process for old UNKNOWN observation, no lost drain wake when completion occurs during a parked change callback, original selection cancellation/deadline checks, and no downgrade of revoked authority to legacy dispatch. The 4 authority and 3 submission tests also pass, including unpublished target rejection, forged-equal-fields rejection and no overtaking while the first permission check awaits. These are software regressions, not a new real TCC or physical-click acceptance result.

### Historical UNKNOWN and prospective admission

All 13 new admission cases explicitly pass. The critical case supplies a valid original start and then attached observation to a historical F-like UNKNOWN and verifies the v1 profile, unchanged UNKNOWN/visible state, unchanged original operation/attempt, no new marker/start/compensation, observation-only commands and a still-busy original draft lock.

The other cases establish one new append with durable registration; no duplicate append even before its first receipt is applied; first-writer nonce behavior across admission actors; original-only restart completion; independent start and completion policies; unadmitted/ordinary-policy isolation; marker corruption, foreign identity, extra fields, whitespace and duplicate keys fail closed; stale dispatch snapshots cannot enroll durable UNKNOWN; a caller-supplied admitted profile cannot bypass the marker; unsupported Home/local/unrecognized/Work/non-Chrome targets and unsupported PNG representations refuse before new input. Historical Home/local/PNG16 operations retain only their original observation path.

The 8 journal cases explicitly pass: immutable first observations across restart and concurrency, no corrupt or conflicting replacement, missing/wrong-store identity rejection, no observation before dispatch, and no synthetic/foreign identity admission. Candidate integration self-check tests and old unsupported-format observation pass separately.

### SQLite migration and recovery

The successful 457-test native run includes the existing frozen v1→v3 and v2→v3 migration cases, preserving unstarted UNKNOWN visibility without inventing starts or rewriting original facts; migration failure rolls back original rows/schema; unsupported future versions preserve legacy rows. Recovery tests cover full identity mismatch, receipt-before-intent rollback, unavailable/missing bytes retaining UNKNOWN target locks, and preventing an old success from consuming a new attempt. The change introduces no schema version or operation-state-machine migration.

## Page, legacy and exact-content regressions

Seven TAP groups complete with zero failures and zero skips: archived evidence replay 19; integrated page program 86; legacy observation 61; round-five diagnostic helper groups 9/4/2; stage-two diagnostic fixtures 12. The separate round-two fault harness reports 8 PASS groups, and the read-only round-three network probe reports 12 PASS groups. These harnesses run offline and do not authorize live failure/retry behavior.

The actual page log includes the exact-sRGB equality and mismatched-preview rejection case; progress disappearance without a final image load remains UNKNOWN. Strict start counterexamples, unique input, full operation/attempt/asset/target binding, and independent final proof all pass.

The v9/v10/v12/v13 monitor and legacy cases explicitly preserve original operations: new v13 borrowing does not mutate/stop old owners or repair old closures; wrong root/accessor/spoofed/ambiguous/stopped owners refuse; historical progress cannot become schema2/new uploadStarted; missing old registries are not installed; original completion and late-error identities remain exact; old v9 UNKNOWN retains its original lease. No old begin/commit/retry path is added.

## Release package and executable checks

The offline packaging suite runs **12 tests, OK**, including malformed metadata, missing executable/notices, duplicate/stale page resources, symlinked resources and false public-release metadata rejection. The Release build completes successfully. `RIFTLET_BUNDLE_CHECK_PASS` confirms expected layout, permission strings, exact source resources and notices. The unchanged `build-macos.sh` runs ad-hoc signing followed by `codesign --verify --strict` under `set -euo pipefail`; successful package creation after that point confirms both commands returned successfully.

All five executable self-check success markers are present:

1. `RIFTLET_SELF_CHECK_PASS` — private import, durable start visibility, delayed synthetic completion and restart.
2. `RIFTLET_WEB_ACCEPTANCE_SELF_CHECK_PASS` — bundled source, isolated synthetic-only policy; Chrome and GUI not run.
3. `RIFTLET_FIRST_USE_SELF_CHECK_PASS` — persistent presentation and disabled-production permission isolation; real permissions and GUI not requested/run.
4. `RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_PASS` — one generated software input, restricted start and independent completion, durable new registration, legacy UNKNOWN preservation and read-only restart; Chrome/system screenshot/GUI not run.
5. `RIFTLET_GUI_HELPER_SELF_CHECK_PASS` — generated image/layout/status fixtures; GUI not run.

The log records successful development App/helper ZIP creation and upload of 35 files in [artifact 12809587008](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40673128250/artifacts/12809587008), named `native-foundation-34caed4a5c5b7264c1699b62ea1438e1ce5646ca`. The uploaded outer artifact ZIP digest is `7c4165ec311fc0ea19d0507c4980ad08e2b4ad05839de3211d5151593d6565c8`. This digest describes the outer CI archive, not the nested App ZIP or a signed release. The build is expressly development/ad-hoc, not notarized or publicly released. I reviewed its build/check/upload logs; I did not launch the downloaded App in this container.

## Prior failure and final handoff boundary

The first PR run `40672786893` failed because the new fake bridge supplied a non-UUID start evidence ID. This failed run remains part of the record. Only that generated fixture changed; no real evidence predicate was weakened. The new direct-SHA run above passes all 13 admission tests and the full later workflow, resolving the earlier incomplete verification.

This approval binds the tested source SHA `34caed4a5c5b7264c1699b62ea1438e1ce5646ca`. If the final formal HEAD only adds documentation/reports/logs, verify and state that executable inputs match this tested source; do not describe an unexecuted doc-only revision as an independently executed CI checkout. Any material executable-input change needs its own verification.

The next real-Mac task still uses **one different, new actual system screenshot** in the supported ordinary existing Chrome ChatGPT thread: one click → genuine uploadStarted → existing fast-swallow UI → independently proved attached → background succeeded. Do not retransmit F/A/D or any old UNKNOWN, fabricate a start, clear the database, or infer success from early swallowing. Safe failure/retry and ordinary production remain closed; PR #1 remains Draft, with no main merge/public release. This software CI creates no additional live-Mac, physical-click, TCC, safe-retry or production-admission claim.
