# Riftlet context for all AI contributors

## Source priority
1. The latest explicit user instructions, including standing authorization in the current session.
2. Recorded user constraints in `docs/PRODUCT.md` and `docs/DECISIONS.md`; retain superseded decisions as history.
3. Evidence in original Pro / Codex research.
4. Unapproved visual or technical suggestions.

The Pro report is a technical recommendation, not full product approval. Codex's first test **did not validate real ChatGPT attachment insertion or ready**.

## Phase
**2026-10-27: the user explicitly authorized formal engineering, implementation, tests, CI and a Draft PR.** This supersedes the previous pre-development restriction (P07), which is retained as historical context in the decision register. Work on an isolated feature branch; do not overwrite main, merge unreviewed work, publish a release, approve visual candidates or enable unvalidated attachment completion.

Read **latest user-approved [docs/INTERACTION_CONTRACT_2026-10-27.md](docs/INTERACTION_CONTRACT_2026-10-27.md)** first, then `docs/PRODUCT.md`, `docs/DECISIONS.md`, `docs/ENGINEERING_PLAN.md`, `docs/ADAPTER_CONTRACT.md` and `docs/VERIFICATION.md`. Historical READY-only swallow instructions in older engineering/design material are superseded only for **visual queue exit**, not for upload completion/security admission. Production success and safe-retry profiles remain empty until independently reviewed real evidence is admitted. Simulation must be isolated and synthetic-only.

## Autonomous parallel execution — standing authorization, 2026-10-27

The user explicitly requests sustained parallel engineering without routine user approvals or participation. The lead engineer owns sequencing, reversible implementation decisions, task allocation, fixes, tests, independent technical review and Draft PR updates. Do not ask the user to choose libraries, resolve implementation details, approve each increment or repeat permission already granted. Technical admission/review in these documents means evidence-based engineering review, not a new user-approval step.

- Use `docs/EXECUTION_BOARD.md` as the live work queue. Read it at session start, claim a READY packet, finish a small verifiable increment, and continue to the next available packet while the execution session permits. Do not stop at a plan or make completion of a draft PR a reason to wait for the user.
- One integration lead plus up to three independent implementation/review roles is the current concurrency budget. Assign exclusive write paths or separate worktrees. Only the lead changes shared Core contracts, `Package.swift`, App composition, CI, the integration branch and remote refs; contributors propose those edits rather than racing on them.
- Separate implementation dependencies from real-environment verification and production enablement. Missing GUI, AX, upload anomaly evidence, a final logo or signing credentials must not block unrelated code. Record the exact missing prerequisite and resumption trigger, park only the affected packet, then take another READY packet.
- Use the smallest reversible default for unresolved engineering choices and record it. Keep visual parameters adjustable and production adapter profiles disabled until admitted. Preserve originals and used private media while cleanup semantics are deferred; add safe accounting/error handling without inventing deletion approval.
- Build/test failure, data-loss or wrong-target defects, unknown-result replay, missing required license notices and simulation leakage are not deferrable for the affected change. Fix or isolate that change; other lanes continue. Independent review is performed by a non-author reviewer and resolved by the lead, not forwarded to the user for routine decisions.
- Keep reviewable work on the feature/integration branch and Draft PR. Main integration, public release, final brand/visual approval and any unavailable OS/account authorization are outside this development increment and must not become day-to-day blockers. Never bypass repository protection or platform permission controls.
- Record the exact source SHA, relevant checks, review result and evidence scope. A pure documentation change can cite an unchanged, previously tested native tree; do not relabel that old run as a new test. GUI and real ChatGPT tests remain separately explicit.
- At handoff, leave a clean checkpoint, current branch/head, the next concrete action and any scoped wait condition. A GitHub workflow is a test/build executor, not an always-running coding agent. Do not claim unattended 24-hour execution unless an actual authorized executor has been provisioned and observed running. No periodic empty progress commits or notifications are needed.

## Current shared implementation boundary

Core/UI/App implement the new lifecycle in SQLite v3. Read [docs/UPLOAD_STARTED_CONTRACT_V1.md](docs/UPLOAD_STARTED_CONTRACT_V1.md) before touching the Web/Core boundary. The local Mac executor owns Web/Chrome evidence and source; the integration lead owns Core/UI/App and the formal branch. Do not infer start from input/placeholder or grant retry from completion. Default production start/completion/safe-retry registries remain empty. Preserve v1/v2 data through the v3 migration; do not reset an old queue to work around UNKNOWN.

## Core contract
macOS screenshot → thumbnail emerges from a rift (no screenshot = no visible rift) → **one click to the current click-time active ChatGPT draft** → on **positively evidenced upload start**, a **very fast swallow animation hides the thumbnail**; do not wait for verified READY. Only **explicit or extremely high-confidence actual failure** rebirths it, **as a normal immediately clickable screenshot with the usual idle-archive/remove lifecycle**. A non-clickable reborn failure image violates the latest product contract; improve failure-evidence calibration instead. UNKNOWN after upload start stays hidden in local internal history, observed without blind retry, and must not permanently obstruct distinct later screenshots. Long-unused visible items auto-archive; individual and bulk removal exist; preserve original system screenshots. Backend upload success and safe-retry evidence remain stricter, independent from visual disappearance. **No valid current composer/attachment input means no swallow**. No success Toast: the user sees attachment progress and completion in the ChatGPT draft. Single/bulk clearing only changes Riftlet visibility, never remotely deletes an attachment. Optimize near-consecutive clicks only if safe. No pinned/guessed target, automatic chat send, mandatory drag/drop, picker or daily new shortcut. **Hold-to-drag is a pending idea only, not an approved feature.**

Typical active queue 2–3, occasionally a little over 10. Avoid a general-purpose screenshot manager.

**Public repository:** never commit real screenshots, private chat content, local machine secrets or browser authentication/session data.

## Additional release UX decisions — 2026-10-27

Read [docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md](docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md) and [docs/PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md](docs/PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md) when implementing first-run, native UX or capture/self-inclusion behavior.

- **P29:** A real foreground ChatGPT draft with usable file/composer input must allow direct one-click attachment even when the text editor does not hold keyboard focus. Do not equate `document.hasFocus()` with `editor===document.activeElement`; validate original target, text, selection and cold first click.
- **P30:** Make self-capture pollution a research and evidence issue, not an impossible universal promise or license for intercepting screenshot shortcuts. Respect ordinary macOS capture methods and permissions.
- **P31/P32:** No-composer click gets light press/reset (no false swallow); archive waits until hover/mouse press/selection/animation is over, including reborn screenshots and wake.
- The user also approves a lean public-release UX baseline: honest support matrix, permission onboarding, separate pause/hide, local history, image fidelity, storage safety, flexible/accessibility-aware native controls, text feedback/opt-in diagnostics, safe updates and small real-user acceptance. No automatic scope expansion into AI/OCR/cloud/general clipboard software.

The Pro feasibility brief is **for research only**; it does not grant code changes, production profile enablement or permission changes. Keep existing engineering branch ownership and truthfully scoped tests.
