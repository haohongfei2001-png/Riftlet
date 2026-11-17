# Riftlet — current engineering instructions

Riftlet is a publicly released macOS app. Use actual `main` and the latest stable
GitHub Release; do not resume an old PR because a historical note calls it current.
The 2026-11-14 audit baseline is 1.0.1 (23); this is a dated fact, not a future version pin.

## Read only what the task needs

1. This file and [current product contract](docs/PRODUCT.md).
2. [1.0.5 current entry](docs/releases/1.0.5/README.md), its audit, product direction
   and Codex handoff. Read only the relevant work packet.
   [2026-11-14 evidence](engineering/quality/2026-11-14/progress.json) and the
   old quality handoff are dated history, not an additional work queue.
3. [Current design decisions](docs/quality/DECISIONS.md) and the relevant source/tests.
4. [Mainline admission](docs/MAINLINE_GOVERNANCE.md) before committing a formal PR.

Latest explicit user direction wins. Current quality decisions supersede conflicting
historical phase restrictions. Old files are retained under `docs/quality/history/`;
`engineering/evidence/` and `research/` remain source-bound historical evidence,
not new permission or a second work queue. Open candidates are not released features.

The active next-version task is [1.0.5 product closeout](docs/releases/1.0.5/CODEX_HANDOFF.md).
At the 2026-11-18 audit, main was `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`;
PR #110 held the unmerged 1.0.4 build 27 candidate at
`f3153b10dac4445720f1c20c8836ddbbea625c49`. Public download was 1.0.3 and the
repository stable feed was 1.0.2. Re-read actual remote state before implementation.
Integrate the valid 1.0.4 changes into a separate 1.0.5 worktree; do not restart from
old main alone or resume already merged PR #101. PR #100/#109 are dated planning;
#69/#77 are separate candidates, not automatic dependencies. Issue closure, source
admission, native acceptance and release approval remain distinct.

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
  queue identity, previews and accessibility. Scope settings refinement to the 1.0.5
  product direction; no destination expansion or unplanned product modules.

## Data and release safety

- External original screenshots are read-only. Never reset the current SQLite library,
  replay or clear UNKNOWN, replace current data with an old backup, or repurpose production
  profiles for a test. Implement 1.0.5 lifecycle/cleanup only within its explicit product
  direction, preserving active/unknown/only-copy recovery and legacy retention promises.
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
