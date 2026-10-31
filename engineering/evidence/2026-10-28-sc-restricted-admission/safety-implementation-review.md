# Riftlet restricted screenshot admission — independent safety design review

Reviewer: non-author `/root/admission_safety_review`.

Review base: formal `871d825a43a759bb6dd8ded9cdc99a340d8e0e64` plus the evidence-only merge from `493d1d8b898d18e34709463d2dceca8c85ad4014` in `/workspace/scratch/16d4559e9aa8/Riftlet-sc-admission`.

Status: implementation source review PASS after the corrections described below; final commit SHA and macOS CI binding pending. This report does not claim another live Mac screenshot or private-evidence verification.

## Finding requiring a code fix

**Do not put the historical candidate-v1 profile IDs into the new admission maps.** `TransferCoordinator.recover`, `recoverOriginalObservations`, an UNKNOWN reclick, and `observePending` all reconcile the original operation using the current receipt policy. The existing candidate normalizer maps an exact attached envelope to `verifiedReady` under `chatgpt-web-system-screenshot-attached-candidate-20261028-v1`. F is intentionally still UNKNOWN/visible and has this exact attached observation. Admitting that v1 profile would make a routine observation consume F and release its lock, violating the user's explicit old-UNKNOWN boundary even without another input.

## Minimal implementation recommended

1. Keep both historical candidate-v1 IDs unadmitted forever in this change. Add separate new IDs for the newly reviewed start and independently reviewed completion scope. Keep safe-failure and retry maps empty. Ordinary capture continues to construct `UnavailableAdapter` and empty policies.
2. Persist a small, code-owned eligibility checkpoint using the existing SQLite `saveCheckpointIfAbsent` API. No schema migration is needed. Bind it to admission version/scope plus the full `ObservationIdentity` (asset, operation, attempt, original hash, full target), and verify the immutable stored asset and stored operation against the request.
3. Create eligibility **only on the new `append` path, before `begin`**, after PNG and full-file/hash validation. Require the durable operation to be the request's exact active operation in `dispatchIntent`. A stale `dispatchIntent` request snapshot for a durable UNKNOWN must fail. Verify these durable bindings and insert the first marker in one SQLite transaction: a narrowly named overload `saveCheckpointIfAbsent(_:for:dispatching:asset:)` avoids the await-between-check-and-insert race while leaving the general observation API unchanged. This is an atomic issuance check, not a new state machine or a claim of cross-process atomicity with a later browser call. Never create, infer, or repair eligibility during `reconcile`, recovery, journal observation, or receipt application.
4. First-write semantics are essential: an existing conflicting or corrupt marker must not be overwritten to accept a newer observation. Prefer rejecting enrollment if any marker already exists, including an identical one: persisted eligibility authorizes subsequent observation, not another append/begin. This also blocks duplicate append snapshots before the original receipt has been applied. Missing or invalid eligibility during observation must produce only historical unadmitted receipts, or throw fail-closed so Core retains UNKNOWN. No old first-start/attached journal entry, legacy receipt, argument, default, plist, or page-controlled field may grant eligibility.
5. During observation, select the admitted normalizer/profile only after validating this persisted eligibility. Valid newly admitted operations may still complete after restart; marker reads must therefore permit their later unresolved/succeeded phases while retaining all immutable identity checks. Missing marker on F/A/D must leave their v1 observation mapping and unresolved locks intact.
6. Keep the existing first-observation journal unchanged as evidence, not authority. Do not rewrite old receipts, first starts, identity fields, attempts, source image, or database contents to make old operations eligible.

The existing coordinator already supplies the required no-replay behavior: recovery never calls append; old UNKNOWN selection and polling only call reconcile. The existing policy and QueueStore already supply start → swallowed and independent attached → succeeded without animation or state-machine changes.

## Narrow scope that can be enforced without touching the page program

The frozen `TargetLease` must be `adapterID == chatgpt-web`, `.webChat`, `applicationID == com.google.Chrome`, and contain a recognized `logicalDraftIdentity` with exact profile `chatgpt-composer-react-persisted-20261027-v1`. This represents the existing ordinary thread used by the evidence. Home has no logical identity; a newly created local draft uses a different local-chatgpt profile. Requiring only `.webChat` would accidentally admit Home.

The unchanged v13 page independently binds the original root, original form/editor/document and logical draft, and rejects Work, temporary, or read-only threads. It also verifies the current observed Chinese composer structure. The target does not encode an exact Chrome build; do not claim an exact runtime-browser-version gate that is not implemented.

Apply the new target restriction to new-input capture/validation/enrollment, not to the general target check shared by old read-only reconciliation. Otherwise old Home/legacy observation would be unnecessarily broken.

PNG input already has local original-file validation, no-follow descriptor checks, exact file size and two SHA256 passes, and existing 8 MiB / 16,777,216-pixel transport bounds. The F evidence explicitly covers PNG bit depth 8 / color type 6 (RGBA). The current 33-byte IHDR preflight can enforce those bytes before a new operation is created; PNG16, palette, grayscale/RGB or other formats should not inherit this admission. Compression/filter fields must remain standard. The public F evidence does not explicitly record interlace, so do not describe a particular interlace value as measured evidence. Existing transport bounds are implementation bounds, not proof that every image shape up to those bounds has been tested live.

## Required meaningful regressions

| Regression | Required behavior |
|---|---|
| Historical F-like UNKNOWN, valid original attached observation, no marker | Remains UNKNOWN/visible; active operation ID and attempt unchanged; no start row; no eligibility marker created; no append/begin/chunk/commit |
| Same old target and another asset after F-like attached observation | Old operation continues holding its dispatch conflict; observation does not unlock the draft |
| Historical A/D-like unavailable page/tab and old unsupported format | Original read-only observe only; stays unresolved, no new identity, no replay or clear |
| Newly dispatched eligible PNG | Exactly one begin/commit and one attempt; durable eligibility before begin; real structured start yields first-start row and swallowed visibility but not succeeded |
| Same eligible operation, later exact attached proof | Background observe succeeds under the distinct completion admission; no second input |
| Restart after new admitted start | Existing marker permits original-only final observation; first-start fact and identity retained; no resend |
| Start-only policy | Start may swallow, but attached cannot succeed without the independent completion map |
| Completion-only policy | Start cannot create admitted first-start fact; complete proof is required independently |
| Unknown/input-triggered/attachment-looking but inexact/error/uploading evidence | No implicit start or completion; no approximation, no relaxed content proof |
| Missing/corrupt/future-version/foreign-profile marker | Fail closed; never recreate during observe; original marker remains unchanged |
| Marker copied across asset/op/attempt/hash/full target/store | Refuse admission; every identity component and stored asset/operation must match |
| Stale request with durable UNKNOWN supplied to enrollment | Refuse enrollment and all input |
| Duplicate append with the same durable marker and original dispatch snapshot | No second begin or commit; marker permits observation only |
| Synthetic provenance/generated asset/foreign observation profile | Cannot acquire real screenshot admission |
| Home, local new draft, Work, other application/session, unrecognized logical identity | No new input admission; existing old-op read-only behavior preserved |
| PNG16/palette/unsupported format/out-of-bounds/corrupt private bytes | Fail before input; preflight-only failures should not create operations; post-header hash mismatch remains conservative UNKNOWN without begin |
| Safe-failure/retry | Maps remain empty; failed or invalidated observations never reopen an automatic/new attempt |
| Ordinary mode | No Chrome bridge or candidate admission despite the new internal candidate map entries |

Existing tests already cover journal first-write immutability, strict envelope decoding, synthetic-origin isolation, source-version gating, original identity matching, old unsupported-format reconciliation and corruption before begin. Extend the existing candidate tests rather than introducing a new state machine or broad test harness.

## Packaging / reporting implications

`SystemScreenshotCandidateSelfCheck` currently asserts all three maps are empty and expects new observations to stay UNKNOWN/visible. It must be updated to exercise the new admitted path and retain a separate historical-UNKNOWN fixture. Its generated image/fake executor remain software evidence, not live screenshot acceptance.

The existing UI connection is sufficient: `QueueStore.apply` sets `swallowed` with reason `uploadStarted`; Main refresh includes recently retired visible records and calls `RiftPanelController.render`; that renderer animates only the start reason. Candidate mode has no extra animation block. `SetupPresentation` currently says no automatic swallowing or success and needs accurate restricted-admission wording. Main's menu also has a literal “开始/成功待审” string; its production-closed tooltip remains accurate. Any minimal wording adjustment in the isolated integration branch must preserve the independent feedback branch.

The final handoff must separate evidence review (source `48574df`, new real screenshot F) from the newly built candidate's software/native CI. The actual new candidate fast-swallow experience remains to be confirmed on another fresh system screenshot. Do not retransmit F, A, D, or any old UNKNOWN during that test.

## Implementation review addendum

Decision: **PASS for the reviewed implementation**, subject to the full macOS CI and final revision binding. No remaining source blocker was identified.

### Actual implementation checked

- `SystemScreenshotCandidateAdmission` registers only through adapter append after the private file's first full hash. Its versioned registration binds source ID, separate start/completion IDs, complete original identity and a fresh enrollment UUID. Existing marker rejects another append. `admits` is read-only, verifies exact persistent identity/active operation, rejects prepared or terminal-failed requests, validates native target/origin/metadata, and requires canonical sorted-key serialization to equal the stored bytes. Missing marker takes the historical v1 path. Corrupt or foreign marker fails closed.
- `QueueStore.claimDispatchCheckpoint` validates the complete actual stored dispatch-intent operation, immutable stored image and active operation in the same transaction as `INSERT OR IGNORE`. The nonce and retained-byte equality distinguish concurrent claims. Existing general checkpoints, schema v3, operation transitions and receipt application are unchanged.
- `WebAttachmentAdapter` permits only the historical v1 candidate profile at construction. An injected admitted-v2 profile cannot bypass the marker. The adapter uses v2 only after the registration check; history without registration continues v1. Scope checks are in new-input capture/validate/append only; original-only reconciliation retains compatibility. Enrollment precedes the sole begin; no new begin/commit/retry path exists.
- The PNG representation gate now validates the first 33 bytes retained from the **same descriptor and same full SHA256 scan** that authorizes actual upload. The earlier preflight remains for rejection before creating an operation. This closes the separate-descriptor format race while retaining both existing full-file hash passes. Type 6 / depth 8 / standard compression/filter / noninterlaced are conservative candidate requirements; no conversion or approximation was added.
- `SystemScreenshotCandidateConfiguration` contains only the two new v2 `.webChat` map entries and an empty safe-failure map. The factory supplies journal and admission against the same store only for the explicit screenshot candidate. Ordinary capture still returns `UnavailableAdapter` and empty policy. Synthetic acceptance remains separate.
- `SystemScreenshotCandidateSelfCheck` now exercises a newly admitted start, immediate swallowed state without succeeded, restart preserving the hidden operation, and later independently admitted completion with the same visibility revision and no second input. Its F-like historical fixture has a distinct private filename and must retain v1/UNKNOWN/visible/no-marker/no-start under an otherwise valid attached observation. It remains generated-image/fake-executor software evidence.
- `RiftletMain.swift` changes are limited to three strings: self-check result description, explicit candidate launch explanation and candidate menu description. Permission recovery, ACK ordering, original click handling, observation scheduling and UI animation logic are unchanged. Setup text accurately describes the restricted start/completion behavior and closed retry/ordinary production boundaries.

### Review corrections resolved before approval

1. Atomic registration issuance was added so another actor cannot change the stored operation between a separate phase check and marker insert.
2. Candidate constructor remains v1-only even though the normalizer recognizes the new admitted profile; a caller cannot inject v2 as the missing-marker fallback.
3. Completion reviewer found the two-descriptor PNG-scope race and the packaged historical fixture's duplicate `file_name` constraint violation. Both were corrected and independently re-read in this source review.
4. Marker decoding now rejects unrecognized or noncanonical stored fields, including fields silently ignored by `JSONDecoder` alone.
5. The PNG gate's comment now distinguishes the explicit conservative noninterlaced requirement from the public evidence, which does not separately report interlace.

### Verification limits

This review inspected actual implementation and shared source, not only the proposal. The container cannot run native AppKit/Swift tests. Full macOS CI, packaging and executable self-check results must be bound to the final SHA before delivery. The new candidate's live fast-swallow interaction remains a separate fresh-screenshot Mac retest; old F/A/D and every old UNKNOWN must remain unreplayed.

Historical original-only polling may update an observation, latest receipt or diagnostic reason under existing Core behavior. The preserved boundary is the original identity/attempt, unresolved state, visibility and dispatch conflict, not a claim that an entire live SQLite database stays byte-for-byte unchanged.

### Reviewed implementation file fingerprints

These fingerprints record the source snapshot approved before CI; a final SHA binding is still required. The page program was also compared byte-for-byte with the `48574df` Git blob and is unchanged.

| File | SHA-256 |
|---|---|
| `Sources/RiftletAdapters/SystemScreenshotCandidateAdmission.swift` | `32327ee95cc51aa467ea8bfcb4a6269679946f3b9ca2b41cd41e6cb7573b282c` |
| `Sources/RiftletAdapters/SystemScreenshotWebCandidate.swift` | `93f69480ff0d8d9c8e6755336e69999750d6e2046699f558b96a0c2b340c73ae` |
| `Sources/RiftletAdapters/WebAttachmentAdapter.swift` | `a3209235123335be26903d1286b8822554487c8e98bac50c82970827a42569ad` |
| `Sources/RiftletCore/QueueStore.swift` | `d42e0437572fe5670eb769576e26d09ede74802f7aed699755d2262345f54e85` |
| `Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift` | `21f689146ac99838a7aacbd485000926518bfadf10909be48db3b8b0b11b0858` |
| `Sources/RiftletApp/SystemScreenshotCandidateSelfCheck.swift` | `e9db6da908ebe79455e6239ccedf6564edf60c700201fe362ad697b1874dbb1e` |
| `Sources/RiftletApp/RiftletMain.swift` | `a4a67f2c8f1f713bc117140430e35ed1b45ee79c7821c67fff138d577b5ea531` |
| `Sources/RiftletUI/SetupPresentation.swift` | `7654fd5a7ca16e26287aaa67ad8418cb0d2e161e267e8a5afc229803bf8f93dc` |
| `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js` | `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b` |

## Published candidate revision binding

The exact published candidate **`375f52d84007ea6644ddcc0380fa52a3591c74ab`** was independently checked from Git blobs against all 9 reviewed source-file SHA-256 fingerprints above: **9/9 exact matches**. Its tree is `ad081286e07e12c43cb0b7b750c45032078a8734` and its parents are `871d825a43a759bb6dd8ded9cdc99a340d8e0e64` and `493d1d8b898d18e34709463d2dceca8c85ad4014`. The local worktree was clean and at this exact SHA during the check.

The full new macOS runs identified for this candidate are push `40672755431` (job `122763418622`) and PR `40672786893`. They were queued when supplied; this source binding does **not** attest their outcome. The earlier source run `40656871851` is not used to approve this new candidate. Native permissions/original-click, legacy/UNKNOWN, packaging and executable self-check log review remain pending the new exact-SHA run.

## First candidate CI failure review

Reviewed the complete supplied log `engineering/evidence/2026-10-28-sc-restricted-admission/ci-40672786893-failed.log`, for PR run `40672786893` / job `122763525170`. This PR job actually checked out merge commit `6349afb880bb88cd9d1f2e9c46dccd415bb0ea16` (candidate `375f52d` into formal `871d825`), not the direct candidate commit.

The native code compiled successfully (`Build complete! (34.80s)`). The parallel native run reached 457/457 scheduled tests and reported exactly four XCTest errors, all in the new admission tests and all `invalidField("upload start")`:

- `testAdapterWithoutExplicitAdmissionRetainsObservationOnlyProfiles`
- `testCompletionOnlyPolicyCannotAdmitStartAndProductionDefaultsRemainClosed`
- `testLegacyUnknownStartAndAttachedNeverAcquireAdmissionOrReleaseOriginalLock`
- `testNewAppendStartsOnceAndRestartedCompletionNeedsItsSeparateAdmission`

The existing strict decoder requires upload-start evidence ID to be a 36-byte valid UUID. The constructed bridge supplied `constructed-admission-start`, violating that requirement. Inspection confirms its other start fields meet the existing predicate. The proposed correction changes only that test-fixture field to `00000000-0000-4000-8000-000000000003`; it does not change the production validator or any source file. This is the correct scope of repair.

No other compile or test error was present in the supplied log. All seven preceding TAP groups reported zero failures (19, 86, 61, 9, 4, 2 and 12 tests). The workflow stopped at the failing native step, so subsequent detailed gates, Release packaging and executable checks were **not run** in this job. This failed run is retained as evidence and is not treated as complete CI approval. A new full exact-revision run after the fixture correction remains required.

## Final tested-source and CI disposition

The fixture-only correction is committed as `34caed4a5c5b7264c1699b62ea1438e1ce5646ca`, tree `d1b5c73c4d3c7eda94c7675a18f87b1ee08bafcf`, parent `375f52d`. All 9 implementation fingerprints above still match its Git blobs exactly. Its direct-checkout push run `40673128250`, job `122764686050`, and corroborating PR run `40673134992` independently report completed/success through the GitHub connector.

The full push log was independently reviewed: 457 native execution entries, 17 detailed suites containing 120 explicit passed cases with no detailed skips/failures, all 13 admission regressions passed, required permission/ACK/UNKNOWN/legacy/migration coverage, Release packaging and all five executable self-checks completed. **The pending-CI condition is resolved for this exact tested source.** The complete outcome and retained limits are recorded in `/tmp/riftlet-admission-ci-safety-review.md`; live candidate fast-swallow acceptance still requires another new real screenshot.
