# Beta 2 native product integration — 2026-11-06

Latest user authorizes standard PR42 merge, complete native V2 implementation, isolated Mac review and installable Beta2 candidate. No replacement of installed Beta1 or merge of the major UI PR before final appearance decision. Preserve production state and attachment architecture.

- Formal base: c72fca78245a15a66ea6beaa980ec141f146bc1b (standard PR42 merge, parents b61fc46/fdbf4c3, tree1816948 matches tested source exactly).
- Branch: codex/beta2-native-product-20261106; isolated worktree riftlet-beta2-native-product-20261106/Riftlet.
- Design: existing design/settings-control-center-20261106 at83b8ee478f13d3714697eda4cb3a7785576cb6e0; revision2 HTML c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58. No new browser prototype or information architecture.
- Beta1 executable preserved: c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4.

## Ownership and active work

Root owns shared UI snapshot/commands, SettingsStateModel notifications/synchronous edits, Main/real persistence integration, Package/CI, refs and candidate packaging. review owns new six-page native SettingsCenter views/controllers/tests. diagnostics owns native NSPopover/NSMenu and three-step Onboarding controllers/tests. readiness_independent is non-author source/CI/evidence reviewer. Exclusive filenames are recorded in STATUS before implementation.

Read the pinned design revision2 IMPLEMENTATION-HANDOFF, original CONFIGURATION-MAP/INTERACTION-SPEC/TOKENS and revision2 VISUAL-REFINEMENT. Existing SettingsStateModel, appearance and login owners are authoritative. Build native AppKit, not WKWebView. Preserve every effective customization and compatibility field. Snapshot refresh must not rebuild editing controls or apply stale drafts.

## Required delivery

Six pages + three customization levels + dark/accessibility behavior; real domain saves/retries/drafts/close sheets; shared menu/popover/setting commands; unchanged first-use keys and existing SQLite history; actual AppKit visual/interaction evidence; exact independently reviewed G/direct H and five CI checks; verified ARM64 app/zip and isolated candidate launch, no production install. Finish all independently executable work before final handoff.

## Current checkpoint

PR42 source/admission/five checks/artifacts independently revalidated and merged. Main push CI finished 4 success / 1 ARM64 failure (Native42184582609/Feedback42184582764), original evidence preserved; old receipt test now waits boundedly for the actual durable receipt. Shared UI contract, native surfaces, and real host first integration build; native runtime acceptance and formal CI still pending. No Beta2 PR or candidate acceptance yet. Do not call PRODUCT_READY or BETA2_REVIEW_READY from source-only progress.
