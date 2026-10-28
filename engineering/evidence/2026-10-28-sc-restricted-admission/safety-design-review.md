# Riftlet restricted screenshot admission — independent safety design review

Reviewer: non-author `/root/admission_safety_review`.

Review base: formal `871d825a43a759bb6dd8ded9cdc99a340d8e0e64` plus the evidence-only merge from `493d1d8b898d18e34709463d2dceca8c85ad4014` in `/workspace/scratch/16d4559e9aa8/Riftlet-sc-admission`.

Status: initial source/design review; implementation and final CI not yet reviewed. This report does not claim another live Mac screenshot or private-evidence verification.

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

Pending root's actual diff and final macOS CI.
