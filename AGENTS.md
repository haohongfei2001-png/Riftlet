# Riftlet context for all AI contributors

## Source priority
1. Explicit latest user constraints in `docs/PRODUCT.md` and `docs/DECISIONS.md`.
2. Later explicit user decisions.
3. Evidence in original Pro / Codex research.
4. Unapproved visual or technical suggestions.

The Pro report is a technical recommendation, not full product approval. Codex's first test **did not validate real ChatGPT attachment insertion or ready**.

## Phase
**2026-10-27: the user explicitly authorized formal engineering, implementation, tests, CI and a Draft PR.** This supersedes the previous pre-development restriction (P07), which is retained as historical context in the decision register. Work on an isolated feature branch; do not overwrite main, merge unreviewed work, publish a release, approve visual candidates or enable unvalidated attachment completion.

Read `docs/ENGINEERING_PLAN.md`, `docs/ADAPTER_CONTRACT.md` and `docs/VERIFICATION.md`. Production success and safe-retry profiles remain empty until independently reviewed real evidence is admitted. Simulation must be isolated and synthetic-only.

## Core contract
macOS screenshot → automatic collection → click tiny thumbnail once → append to intended ChatGPT draft → only upon verified ready, swallow. Definitive failure reverses. Unknown preserves the item and checks before any retry. No automatic chat send, drag/drop, picker or daily new shortcut.

Typical active queue 2–3, occasionally a little over 10. Avoid a general-purpose screenshot manager.

**Public repository:** never commit real screenshots, private chat content, local machine secrets or browser authentication/session data.
