# Internal Beta source — independent Feedback CI review

Reviewer: `/root/beta_feedback_review`, non-author of the reviewed implementation and workflow changes.

## Result and identity

**PASS.** Independently read GitHub run metadata and job steps, then inspected and parsed the complete local copy of the actual job log.

- Run: `40692933838`, [Feedback v0.1](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40692933838).
- Job: `122832124074`, `feedback`.
- Trigger: push to `codex/riftlet-real-mac-acceptance-internal-beta-20261028`.
- GitHub head and actual checkout both: `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`.
- Actual tree: `5d970fd354f1a4a8c70b0ec0b1a027825944f8b5`.
- Actual parents, in order: `c177174e400064d8ec8bb79685c33d01c4e93b89`, `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`.
- Run status `completed`, conclusion `success`; updated 2026-10-28 21:04:16 Asia/Shanghai (13:04:16 UTC).
- Environment: macOS 14.8.9 / 23J631, arm64, Apple Swift 5.10, Node 22.23.2.

Log reviewed: `/tmp/riftlet-beta-source-feedback-40692933838.log`, **94,466 bytes / 1,149 lines**.

Exact saved-byte SHA-256: `1d9dddaa36bc16e8a4ec7fae5e06fdac45acd8640058e4cf85931c0576a06fd0`.

This digest identifies the saved log copy actually reviewed, not the ZIP artifact. No claim is made that this source run already tests a subsequent final documentation commit.

## Actual results

| Check | Observed result |
| --- | --- |
| Original Feedback Git isolation regressions | 4/4 passed |
| Added three-source internal Beta Git audit regressions | 7/7 passed |
| Pinned integration audit on the actual checkout | 31/31 checks PASS |
| Feedback native tests | 25 unique cases passed |
| Feedback software AppKit tests | 7 unique cases passed |
| Combined selected native/UI run | 32 tests, zero failures; every case explicitly passed, no skipped case |
| Close/reopen/termination repeat | Same 2 cases repeated 3 additional times, all passed |
| Service SQLite/mock HTTP tests | 18 passed, 0 failed/cancelled/skipped/todo |
| Offline Feedback Demo | Release build, ad-hoc packaging and build verification PASS |
| Exact-source/log artifact upload | Succeeded |

The native log contains 38 passed outcome records but only **32 unique tests**: each of the two `FeedbackCloseTests` cases appears four times (initial run plus three repeats). Do not report 38 distinct tests, and do not add these 32 again to a complete native CI total that already includes the same modules.

The actual pinned audit JSON has result PASS, exact 70cf588 revision/tree/parents, and 31 passing checks. It validates e421/c177/f195 ancestry, protected screenshot paths, exact Feedback delivery paths, all seven original H evidence files through their directory object, the 16 unchanged App files outside Main/Host, and reviewed Main blob `5b1c64348cc0661f0de359c45a54158e828d6c22`.

GitHub job metadata reports **11 successful steps and one intentionally skipped step**. The skipped old `Verify actual Feedback and current screenshot composition` step is explicitly restricted to PRs whose head branch is `codex/feedback-v01-20261028`; this source run is an internal Beta push. Its absence is expected. The unconditional new `Verify archived evidence and pinned unified Beta composition` step ran and passed, so composition was not skipped altogether. Neither workflow-level skip nor repeat counting is represented as missing native test execution.

The Demo build emits `FEEDBACK_DEMO_BUILD_PASS; OFFLINE_SYNTHETIC; CLOUD_NOT_RUN; PHYSICAL_GUI_NOT_RUN; NOT_NOTARIZED`. It is not the founder's combined Riftlet App package. Source artifact logged as `12818345766`, 229,360 bytes, uploaded ZIP SHA-256 `c38413a0e49b45bc5b8b231b0a6fcaac60aeef1d9a73b76d41b29be9d6e6e891`; this reviewer has not downloaded and recomputed that archive.

Existing `filePromise` deprecation warnings and tool/runtime warnings are visible; no test failure, skipped native case or CI error is hidden. This review does not describe the log as warning-free.

## Documentation clarifications rechecked

Read the integration lead's working-tree corrections after the preceding handoff review:

- Packaged README now says only actively selected whitelist diagnostics are included and they **can** be previewed before sending; it no longer implies that opening preview is mandatory.
- `docs/INTERNAL_BETA.md` now says diagnostics do not automatically collect **chat text**, and explicitly distinguishes deliberately entered feedback text as normal draft/report content.

Both recommendations are resolved in the reviewed working tree. They were not part of this run's 70cf588 commit and must be committed/packaged at the final checkpoint. No product code needed changing.

## Scope retained

This is actual combined-source Feedback CI, not live receiver/D1/private Issues acceptance, physical window/IME/VoiceOver, Keychain permission or a new real screenshot upload. Endpoint remains nil; user submission is local queued feedback without cloud success. H remains the separately archived e421 software CGEvent limited PASS. Ordinary production screenshot upload, safe failure/retry, old UNKNOWN replay/unlocking and cloud deployment remain closed.

The full Native foundation run and final complete-App artifact require their separate actual result review; they are not inferred from this Feedback job.
