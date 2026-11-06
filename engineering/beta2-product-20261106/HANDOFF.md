# Beta 2 native product integration — 2026-11-06

Latest user authorizes standard PR42 merge, complete native V2 implementation, isolated Mac review and installable Beta2 candidate. No replacement of installed Beta1 or merge of the major UI PR before final appearance decision. Preserve production state and attachment architecture.

- Formal base: c72fca78245a15a66ea6beaa980ec141f146bc1b (standard PR42 merge, parents b61fc46/fdbf4c3, tree1816948 matches tested source exactly).
- Branch: codex/beta2-native-product-20261106; isolated worktree riftlet-beta2-native-product-20261106/Riftlet.
- Draft PR: [#43](https://github.com/haohongfei2001-png/Riftlet/pull/43); initial remote head `974e0bcde40f3f4d25ef1f1bbe0acc7d74575dc0`, base `c72fca78245a15a66ea6beaa980ec141f146bc1b`. No merge or production replacement has occurred.
- Design: existing design/settings-control-center-20261106 at83b8ee478f13d3714697eda4cb3a7785576cb6e0; revision2 HTML c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58. No new browser prototype or information architecture.
- Beta1 executable preserved: c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4.

## Ownership and active work

Root owns shared UI snapshot/commands, SettingsStateModel notifications/synchronous edits, Main/real persistence integration, Package/CI, refs and candidate packaging. review authored the new six-page native SettingsCenter and assigned tests; it now owns this documentation/evidence handoff. diagnostics authored native NSPopover/NSMenu and three-step Onboarding and is preparing only bounded driver diagnostics. readiness_independent is the non-author source/CI/evidence reviewer. Product edits remain coordinated through exclusive filenames; this evidence update changes no product source.

Read the pinned design revision2 IMPLEMENTATION-HANDOFF, original CONFIGURATION-MAP/INTERACTION-SPEC/TOKENS and revision2 VISUAL-REFINEMENT. Existing SettingsStateModel, appearance and login owners are authoritative. Build native AppKit, not WKWebView. Preserve every effective customization and compatibility field. Snapshot refresh must not rebuild editing controls or apply stale drafts.

## Required delivery

Six pages + three customization levels + dark/accessibility behavior; real domain saves/retries/drafts/close sheets; shared menu/popover/setting commands; unchanged first-use keys and existing SQLite history; actual AppKit visual/interaction evidence; exact independently reviewed G/direct H and five CI checks; verified ARM64 app/zip and isolated candidate launch, no production install. Finish all independently executable work before final handoff.

## Current checkpoint

PR42 source/admission/five checks/artifacts were independently revalidated and merged. Its main push CI finished 4 success / 1 ARM64 failure (Native42184582609/Feedback42184582764); that original evidence remains, and the old receipt test now waits boundedly for the actual durable receipt.

Beta2 has a Draft PR and packaged ARM64 candidates, with real isolated native evidence through [run06](evidence/native-run-06.json). The reviewed observer removal is present in exact source `d72f966` / runtime `54749ad5695a5edd6e2eb6077e4456be4498d02b43f7451fb911bb99bfedf545`. Run06 remains 9 PASS / 4 FAIL and runner timeout; it is not a complete native acceptance pass. [Exact original-package CUA](evidence/cua-native-exact-d72f966.json) observed launch, guide Escape and process absence after Quit, but status-item interaction was unavailable through the tool. [Independent same-package restart](evidence/independent-restart-d72f966.json) separately passed normal exit and persistence readback without changing the original failure.

Initial PR CI is [Native 42205691399](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691399) / [Feedback 42205691613](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691613). At 2026-11-06 10:56 UTC both source gates are FAIL with inherited PR42 admission still present; Native ARM64 / Intel are running, and Feedback native and service is SUCCESS (its historical composition step is skipped). Builds continue independently while final non-author source review, G/direct H, final five checks and package identity remain pending.

Next work is bounded diagnosis of the remaining programmatic popover route and completion of formal CI/package/source review. A new driver diagnostic has not yet inherited d72 runtime evidence. Do not wait for a blanket full-driver green result to do independent work, do not rewrite FAIL into PASS, and do not declare `PRODUCT_READY` or `BETA2_REVIEW_READY`. Actual status-button/second-click/outside-click evidence and the final appearance decision remain explicit gaps. Production Beta1 and all historical data remain preserved.
