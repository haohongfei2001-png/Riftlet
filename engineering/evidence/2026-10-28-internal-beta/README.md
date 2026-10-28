# Unified internal Beta integration evidence · 2026-10-28

The original H acceptance is archived verbatim from c177174; it ran e421e668. Feedback delivery f195beb is merged by actual ancestry, with only the reviewed minimal Main wiring. The complete candidate App and entry point are described in [the current handoff](../../../docs/INTERNAL_BETA.md).

## Independent reviews

- [Original real evidence consistency and archival scope](real-evidence-review.md), by beta_evidence_review (non-author of the Mac execution).
- [Feedback privacy, sidecar, lifecycle and isolation](feedback-review.md), by beta_feedback_review (non-author).
- [Shared source composition and candidate entry](integration-review.md), by beta_integration_review (non-author).
- [Package, CI and another author's Git audit](packaging-review.md), by beta_integration_review (non-author).
- [New audit implementation and meaningful Git regressions](integration-audit-implementation.md), authored by beta_evidence_review, reviewed by beta_integration_review and the lead.
- [Immutable input identities and original CI statuses](integration-inputs.json).

The lead authored packaging, CI and current handoff changes; neither the author nor a source-only review substitutes for the final full macOS runs. The precise committed source, actual CI checkout, complete Native/Feedback logs and verified artifact are recorded in the final [PR #1 integration handoff](https://github.com/haohongfei2001-png/Riftlet/pull/1). Source-checkpoint CI is never relabelled as the final combined run.

## Successful source checkpoint (not the final formal HEAD run)

`70cf5881e07ad18f44c96aa3e7200d3be3df2b04`, tree `5d970fd354f1a4a8c70b0ec0b1a027825944f8b5`, parents c177174 and f195beb. Both workflows directly checked out this source SHA.

- [Native 40692933473](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40692933473): success, 489 unique native tests, detailed 152-subset with no skips, current/legacy 86/61, packaging12+7, Release, strict ad-hoc signature, five executable self-checks and unified Beta package. All 19 steps successful.
- [Feedback 40692933838](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40692933838): success, native32 included in489, two close tests repeated three additional times without increasing counts, SQLite/mock-HTTP18, Git4+7, committed-composition31, offline Demo build. The old PR7-only audit is the one expected skipped step; the new pinned audit ran and passed.
- [Machine-readable source CI and archive record](source-ci-summary.json), [actual committed composition](source-integration-audit.json), [downloaded source artifact verification](source-artifact-verification.json).
- Full retained logs: [Native](source-native-40692933473.log) and [Feedback](source-feedback-40692933838.log), with byte counts, SHA-256 and normalization disclosed in the summary.
- [Native source-CI non-author review](source-native-ci-review.md), [Feedback source-CI non-author review](source-feedback-ci-review.md), [handoff wording review](handoff-review.md). The two wording suggestions were applied in the final checkpoint: preview is optional; excluded body means chat body, not user-authored feedback text.

The source artifact was downloaded and its outer GitHub SHA-256 checked, then the inner complete App, launcher executable bit, all manifest hashes and 14 source/checkout input objects verified. The final checkpoint adds these records and precise documentation/packaged README wording, with unchanged executable source; it receives a fresh final formal-head CI and artifact. Refer to the exact final PR #1 handoff for that separate run rather than reusing the source package as the final delivery.

No real screenshot was uploaded again, no cloud resource was created, no endpoint configured, no feedback-author branch/App overwritten, and no main merge or public release performed. H remains a software-CGEvent limited PASS; physical mouse and no-ACK cold-first-click are not accepted. Old UNKNOWN, original media and audit remain protected.
