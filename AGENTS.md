# Riftlet engineering

Start each change from the actual `main`. Check the latest public Release, riftlet.com and the signed stable appcast for the version users receive. The verified baseline for the November 25 recovery fix is **1.0.10 (65)**, product PR #132 and distribution PR #133. Use the [current release and work status](docs/quality/ITERATION_STATUS.json), [product contract](docs/PRODUCT.md), [decisions](docs/quality/DECISIONS.md) and [mainline process](docs/MAINLINE_GOVERNANCE.md).

## Screenshot behavior

- One explicit click takes a screenshot out of the active tray and puts it in recent history, including clicks without an attachment target. Recent history holds up to 20 clicked or archived screenshots. Scroll up for history and down for the active tray.
- The supported destination is an editable ChatGPT web draft in ordinary Google Chrome or Microsoft Edge. Freeze and revalidate the click-time process, window, tab, document and composer. Preserve the original draft, text, selection, attachments and PNG.
- Perform at most one file input per selection. A positive START records ChatGPT receiving the attachment. Preserve earlier operations and UNKNOWN receipts. Only another explicit selection can initiate another attachment. Sending is always the user's action.
- A failure never recreates an active card or schedules a retry. In the full library, “Restore to tray” changes local visibility only. For a shelved click without a target, prove the click has ended and that there is no operation for the asset before offering restoration.
- Keep approved tray, wind-chime and slit designs, capture controls and the existing settings. Prefer a targeted regression and an existing control over a new permission, observer or workflow.

## Historical material

PRs #41, #101, #119 and #122 and the 1.0.5–1.0.8 phase instructions are historical. The old execution board, archived quality plans, research and evidence retain their original scope and commit identities. Begin new work at current main. The five active engineering entry points are tracked in [the quality index](docs/quality/README.md).

## Data and release safety

- External original screenshots are read-only. Never reset the current SQLite library,
  replay or clear UNKNOWN, replace current data with an old backup, or repurpose production
  profiles for a test. Preserve active media, uncertain operations, sole copies and existing retention choices.
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
- Update the existing quality status and relevant Issue when their state changes. Do not claim
  continuous/background Codex work unless a real executor has actually been launched.
