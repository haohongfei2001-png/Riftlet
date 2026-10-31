# Internal Beta integration and packaging review — 2026-10-28

Reviewer: `beta_integration_review`, non-author of Feedback and this integration. Read-only review of `/workspace/scratch/16d4559e9aa8/Riftlet-internal-beta`; no worktree/index/source modifications, real screenshot input, app launch, service deployment or credentials access performed.

## Reviewed checkpoint and ancestry

- Official screenshot authority: `e421e6687651c2fac1441410c1af2bd5b8151e55`.
- Real fast-swallow handoff: `c177174e400064d8ec8bb79685c33d01c4e93b89`, direct child of e421, seven new evidence files only.
- Feedback source: `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`, common ancestor with e421 `4b7228a07a23381d3de467a44dd8490d73e26e7e`.
- Reviewed state: c177 worktree with `git merge --no-commit --no-ff f195beb` staged. Automatic Main merge completed without conflict. No history flattening or repeated source cherry-pick is needed.

## Exact preservation checks: PASS

`git diff --exit-code e421 -- <protected paths>` returned 0 for Core, Capture, RiftletUI, Adapters including bundled JavaScript, GUIAcceptance, Resources, ThirdPartyNotices and all existing Core/Capture/UI/Adapter/App/WebPageProgram test directories. The screenshot policies, admission marker, original ACK/selection boundary, upload-start lifecycle, strict completion proof, queue/schema and animation therefore remain exact e421 source at this checkpoint.

`git diff --exit-code f195beb -- <feedback paths>` returned 0 for Feedback Core, UI, Demo, FeedbackHost, Feedback/FeedbackUI tests, services/feedback and Package.swift. No second feedback system or endpoint was substituted.

The only shared Main difference from e421 is exactly 20 added lines and one replaced line: Feedback import, lazy host initialization, menu action, guarded exit flush and closed-enum observation hooks. Package.swift adds independent targets/dependencies while retaining every existing target. Main's newer restricted-candidate strings and screenshot logic are retained; there was no whole-file replacement from the older feedback branch.

## Hook isolation: PASS for source structure; physical latency remains unmeasured

The host stores feedback separately under each mode's `Feedback-v01` directory. Feedback initialization creates its store on a detached utility task. Diagnostic ingestion is a synchronous bounded 64-entry ring, with a closed enum and clamped counts, and performs no network/disk/task creation per event. Existing screenshot arrays are sampled after `rift.render(snapshot)`; no original target/ACK/operation identifiers, screenshots, raw paths, hashes, text, clipboard or acceptance trace are passed to feedback. Hooks do not call QueueStore writes or adapter/selection actions.

The added `applicationShouldTerminate` postpones app termination to save a feedback draft; a save failure cancels quit and reopens the feedback window. This is intentional feedback preservation and does not grant any screenshot input/retry authority. Closing/reopening behavior and local outbox/Keychain lifetime are additionally assigned to the independent Feedback reviewer. This source review cannot claim a measured physical capture/click latency comparison.

## Packaging decision

The ordinary App remains `.capture` with UnavailableAdapter. Its current menu can open the candidate, but that creates a second instance and preserves the ordinary collector. A founder-facing package therefore must identify its candidate entry before first launch.

The lead's chosen minimal package is acceptable: a unified archive containing a complete native `Riftlet.app`, a prominently named executable `Start-Riftlet-Internal-Beta.command` beside it, Chinese first-use instructions and accurate build/source identity. The launcher should call the system `open` on that exact adjacent App with the single explicit `--system-screenshot-candidate` mode. Main/ApplicationMode and Info.plist defaults remain unchanged. The App remains runnable as an ordinary App; direct App double-click must be clearly labelled as ordinary collection-only behavior, not the recommended internal Beta start.

The candidate already has first-use/permissions wiring: `collectsSystemScreenshots == true`, `FirstUsePreferences` keyed by the existing candidate mode directory, automatic setup presentation on its first use, and `usesWebAdapter == true` for Chrome permission gating. The launcher should retain `Riftlet-System-Screenshot-Candidate` as the data root and must not copy/reset/migrate a queue or create a fresh root to bypass old UNKNOWN.

Required packaging validation before final approval: correct executable bit; quoted adjacent-App resolution under a directory containing spaces; no eval, data mutation, process killing, arbitrary argument forwarding, tracing, network or permission automation; native bundle verifier, ad-hoc signature and executable self-checks; package contains the integrated Feedback symbols/source through its actual final build; exact outer/inner hashes and final source SHA. A fake launch command may validate argv without launching a real App. Finder/Gatekeeper/physical first install and Keychain prompts remain real-Mac NOT_RUN until observed; no blanket quarantine removal should be prescribed.

## CI isolation audit

The original Feedback audit is intentionally specific to a two-parent PR test merge whose second parent is the Feedback feature head; it checks actual first-parent engineering ancestry and rejects stale-base assumptions. Its workflow condition only runs it when `head.ref == codex/feedback-v01-20261028`. Thus it will not falsely fail PR #1, but will be skipped there and cannot alone certify the new official combination.

Preserve that script and its four real-Git regression tests. Add a separate official-composition audit with immutable e421/c177/f195 inputs: require the evidence and Feedback commits to be ancestors; compare the protected screenshot paths exactly to e421, Feedback paths and Package exactly to f195; compare shared Main to the expected minimal three-way merge (or exact reviewed patch). Record the actual CI checkout and both source identities. Do not reuse GitHub's stale PR base metadata as the screenshot authority or weaken the audit to ignore differences. Any deliberate packaging/test/document additions should be enumerated outside protected screenshot paths.

## Current verdict and limits

**Source combination: PASS, no unresolved blocking finding at the reviewed uncommitted merge.** Proposed explicit launcher packaging is suitable for the user's internal-candidate request and avoids screenshot lifecycle changes. Final packaging implementation, full final macOS CI, actual artifact integrity and updated pinned audit still need review when they exist; this report is not a premature approval of those later artifacts.

Real screenshot CGEvent fast-swallow acceptance must be archived with its original limits. Physical mouse, no-ACK cold first click, public-production upload, safe failure/retry, live cloud Feedback submission, signing/notarization and broad OS/browser support are not opened by this integration.
