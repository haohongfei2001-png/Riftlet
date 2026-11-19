# Riftlet — current engineering instructions

Riftlet is a publicly released macOS app. Use actual `main` and the latest stable
GitHub Release; do not resume an old PR because a historical note calls it current.
The verified 2026-11-18 release is 1.0.5 (31). Recheck all three distribution channels before release.

## Read only what the task needs

1. This file and [current product contract](docs/PRODUCT.md).
2. [Issue #115](https://github.com/haohongfei2001-png/Riftlet/issues/115) is the sole
   1.0.6 task. Use its R106-01–11 decisions and V1–V6 acceptance matrix, with
   [progress and candidate receipts](docs/releases/1.0.6/README.md).
3. [Current design decisions](docs/quality/DECISIONS.md) and the relevant source/tests.
4. [Mainline admission](docs/MAINLINE_GOVERNANCE.md) before committing a formal PR.

Latest explicit user direction wins. Current quality decisions supersede conflicting
historical phase restrictions. Old files are retained under `docs/quality/history/`;
`engineering/evidence/` and `research/` remain source-bound historical evidence,
not new permission or a second work queue. Open candidates are not released features.

Start from the actual main containing merged PRs #113 and #114. Preserve the
signed 1.0.5 release, stable feed and unrelated branches. PR #69 is separate.

## Product invariants

- Normal system screenshot → visible edge thumbnail → one explicit click attaches
  that image to the correct click-time Chrome ChatGPT draft. Never send the message.
- Freeze and revalidate the exact process/window/tab/document/composer. Do not guess
  another conversation or let an unowned file input become eligible merely by timeout.
- Enter the setter/change path at most once per attempt. After possible external input,
  uncertain replies are observed by original identity; never resubmit automatically.
- Positively evidenced current-file START permits the fast swallow. START is not READY.
  Preserve old UNKNOWN, receipts and media. Independent later screenshots stay usable.
- Confirmed pre-input failures stay/recover clickable. START still permits the fast
  swallow and truthful “已交给 ChatGPT”; ChatGPT owns upload progress and sending.
  1.0.5 adds narrowly correlated failure aftercare and visible recovery per its product
  direction. Never invent completion, late-failure proof or retry rights. UNKNOWN
  remains non-resubmitting; displaying an image does not grant input authority.
- Keep approved tray/wind-chime/micro-slit forms, tray 2×2 and capture-button placement,
  queue identity, previews and accessibility. Scope settings refinement to Issue #115; no destination expansion or unplanned product modules.

## Data and release safety

- External original screenshots are read-only. Never reset the current SQLite library,
  replay or clear UNKNOWN, replace current data with an old backup, or repurpose production
  profiles for a test. Apply the explicit media dispositions and verified recovery rules of Issue #115, preserving active/unknown/only-copy recovery and legacy retention promises.
  Audit and tests never delete production media; use isolated synthetic data roots.
- Preserve journal/media/SQLite recovery ordering, file identity/hash checks, single-instance
  ownership, safe migrations, folder bookmarks, saved preferences and feedback credentials.
- Preference/UI simplification must not discard valid old or unknown fields. A corrupt
  cosmetic preference must not become a reason to recreate the screenshot database.
- Keep public DMGs/tags, Sparkle keys and signed feed identities intact. A docs/audit PR
  never publishes a new app. Release changes follow the existing signing/notarization and
  explicit release process after independent acceptance.
- Public commits/Issues contain no real user/private screenshots, private chat content, local databases,
  tokens, credentials or session data. Feedback stays in the private feedback channel.
  Native UI captures using synthetic fixtures are allowed as review evidence.
- Respect supported browser/tool/OS access boundaries. Missing access blocks that test only;
  do not bypass it or ask the user to repeat work another authorized executor can do.

## Work and review

- One integration lead owns shared contracts, Main, CI, admission and refs. Parallel workers
  use exclusive paths/worktrees. Finish small, complete packets; checkpoint useful work early.
- Codex implements; a non-author reviewer checks code, product behavior and actual evidence.
  Fix findings through their existing IDs/Issues; do not create duplicate task systems.
- Use short-lived branches from actual main. Keep the existing B→G→H admission process,
  five formal checks and standard two-parent merge. No direct main push, force push,
  squash/rebase, invented review or gate relaxation. Read back actual remote protection.
- Classify evidence separately: source inspection, controlled tests, native GUI, real service,
  signed release. Record FAIL/BLOCKED/NOT_RUN honestly. Old runs retain old SHA/package scope.
- For UX fixes verify the current product host, not only historical test controllers.
  Add focused counterexamples for concrete risks; avoid duplicating implementation in tests.
- Keep ordinary UI short: effective value + necessary action/error. No audit jargon, debug
  settings, repetitive explanations or new frameworks without a measured product benefit.
- Update the quality queue, Issue, exact commits and next action at handoff. Do not claim
  continuous/background Codex work unless a real executor has actually been launched.
