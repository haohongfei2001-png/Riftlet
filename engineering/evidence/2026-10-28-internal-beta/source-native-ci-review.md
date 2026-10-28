# Internal Beta source macOS CI — non-author review

Reviewer: `beta_integration_review`. Review date: 2026-10-28.

**Verdict: PASS for source commit `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`. This is the tested integration-source checkpoint, not the forthcoming final official HEAD.** README/evidence-only changes scheduled after this checkpoint require their own final package/CI identity; this run is not relabelled as that later run.

## Independently checked run and exact log

- Native foundation run [40692933473](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40692933473), direct branch `push`, head `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`.
- Job `122832122361`: completed/success. The reviewer independently retrieved live GitHub run metadata and job steps; **19 of 19 steps completed successfully**. Run update/completion record: `2026-10-28T13:05:13Z` (21:05:13 Beijing time).
- Actual checkout in the full log is also `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`, not a synthetic PR merge.
- Reviewed saved log `/tmp/riftlet-beta-source-native-40692933473.log`: **287,759 bytes, 2,820 lines**; SHA-256 **`d2d04be0b8aed3410f35f10fbb6bfbd034781337c53336c8ec4f2e017a634c22`**. Hash identifies the exact saved bytes supplied for this review, not an independently recompressed GitHub archive.
- Actual runner: macOS 14.8.9, build 23J631, arm64; Apple Swift 5.10 (`swiftlang-5.10.0.13`, clang 1500.3.9.4).

The log contains no Actions error annotation or failed XCTest outcome. Existing filePromise/Node deprecation warnings are warnings, not silently ignored test failures.

## Native results and count discipline

The complete parallel native invocation enumerates **489 unique tests**, indices 1 through 489 without duplicate test identities:

| Module | Unique tests |
| --- | ---: |
| Core | 138 |
| Adapters | 150 |
| Capture | 65 |
| UI | 56 |
| App | 48 |
| Feedback | 25 |
| FeedbackUI | 7 |
| Total | 489 |

The follow-up detailed invocations report **152 unique explicit passed cases, 0 failed and 0 skipped**. All 152 identities are contained in the 489 enumeration. They comprise the existing screenshot/UI detailed subset of 120 plus Feedback/FeedbackUI's 32; they must not be added to 489. The direct source Feedback workflow's repeats are likewise separate executions, not additional unique native cases.

The detailed logs explicitly exercise 13 lifecycle, 3 input-island, 3 deferred Chrome-binding, 3 setup-window, 15 release-capture, 4 presentation-boundary, 5 synthetic-Web composition, 8 passive permission-resume, 5 Chrome descriptor, 18 accepted-selection FIFO, 4 selection-authority, 3 selection-submission, 7 candidate-input, 13 prospective-admission, 8 observation-journal, 6 candidate-composition and 2 fidelity cases, plus all 32 Feedback/FeedbackUI cases. These outcomes include actual software AppKit tests rather than only discovery lines.

Full-suite coverage includes the frozen v1/v2-to-v3 SQLite migrations and rollback/future-schema rejection; original UNKNOWN locks, read-only recovery and no retransmission; original event-before-ACK ordering, lost permission wake, stale grants/ACK rejection; prospective admission marker identity, corruption/noncanonical bytes, single registration/input and old UNKNOWN refusal. Existing safe-failure fixture tests are synthetic policy tests and do not open production safe retry.

## Web, legacy and packaging regressions

- Current integrated page program: **86/86 passed**, 0 failed/0 skipped.
- Legacy observer program: **61/61 passed**, 0 failed/0 skipped.
- TAP summaries across archived replay and diagnostic helpers: 19, 86, 61, 9, 4, 2 and 12 cases, **193 total**, all passing with no skips. Additional round-two fault and round-three probe checks use their existing PASS-oriented reports and passed their workflow steps.
- Original bundle rejection tests: **12/12 passed**.
- New unified-package/launcher tests: **7/7 passed**. The fake-open test validates the real launcher script's exact arguments with spaces and literal shell metacharacters; it does not launch a real App or substitute for Finder acceptance.

## Native build, self-checks and unified package

The release build compiles and links Feedback, FeedbackUI, the separate Demo and the actual Riftlet App. `scripts/build-macos.sh` completes the original strict bundle/resource/notice checks and ad-hoc signing/strict verification. Because the script uses fail-fast execution, its successful completion after those commands establishes that those checks ran; no Developer ID or notarization claim is made.

All five executable checks explicitly pass:

1. Main synthetic durable lifecycle/private import/restart self-check.
2. Bundled-page and isolated synthetic Web composition self-check.
3. First-use persistence/ordinary-production-disabled permission isolation self-check.
4. Original-byte candidate import, new-operation eligibility, real-policy start/independent completion using generated fixtures, old UNKNOWN preservation and read-only restart self-check.
5. Separate synthetic GUI helper self-check.

The source run then packages the **complete unified Riftlet.app** with the adjacent explicit internal-candidate launcher and instructions. The package validator reports:

`source=70cf5881e07ad18f44c96aa3e7200d3be3df2b04; checkout=70cf5881e07ad18f44c96aa3e7200d3be3df2b04`

The reviewed verifier binds fourteen build/test input Git objects, exact package hashes, ordinary capture-disabled behavior and local-only Feedback metadata. Strict signature verification also runs on the copied App. The final log prints both `RIFTLET_INTERNAL_BETA_CHECK_PASS` and `RIFTLET_INTERNAL_BETA_PACKAGE_PASS`. This is a real compiled App package, not the isolated Demo.

Source artifact [12816964364](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40692933473/artifacts/12816964364) is recorded by upload-artifact as **3,573,381 bytes**, SHA-256 **`41c08496cce14df730a6c4904f151b14be6f718c1797dd627bbfbf39d64c096e`**, including the unified Beta ZIP and engineering App/helper/log files. This reviewer verified the upload's actual log record; a later delivery must independently download/hash its final artifact, and must not use this source artifact as if generated from a new final HEAD.

## Committed-tree audit

The reviewer additionally ran the fixed-source audit directly against committed `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`; it returned `INTERNAL_BETA_INTEGRATION_PASS`. The audit retained both c177 acceptance and f195 Feedback ancestry and all exact e421 screenshot/f195 Feedback/accepted evidence/Main blob checks. This is independent of the successful native workflow; the companion Feedback workflow supplies its own CI audit evidence.

## Scope retained

This review confirms source composition, actual macOS software regressions, release build, packaging/signature and executable self-checks. It does not rerun the real screenshot upload. Original e421/c177 CGEvent fast-swallow acceptance remains limited historical real evidence; the new combined App's physical mouse, Finder/Gatekeeper installation, real Keychain/IME/VoiceOver, cold no-ACK first click, UI latency comparison and live Feedback cloud delivery remain separately unmeasured. Ordinary production upload and safe failure/retry remain closed; old F/H/UNKNOWN is not retried, cleared or unlocked.
