# Unified product integration — 2026-10-29

## Status

Engineering continuation on the existing Draft PR #15 only. **Not a release or fully accepted product.**
The source checkpoint `ee538eb7e3aedc459cbccffbeb0337918fa13b6b` (tree `dcfeb2d5cfc1148a3910c4e177ae7255c77c2c89`) has actual non-author review and is pinned by the final composition gate. Native/Feedback execution remains a separate job: the complete workflow cannot pass without source admission. Existing historical gates and runtime acceptance requirements remain unchanged. Accurate combined CI and new original-pixel review are pending.

## Exact inputs

- Thin-edge source: `2c8cd0371de5e07fd7794f76335381a40403030d` (descends from formal `0e7ea8be148e1124b387e799fd886a7830e96559`).
- Complete built-in screenshot handoff: `6b60f67f6d35272eecff901c507bd75a77874ed6`.
- Common ancestor: `443d21da1a55c0061eafced823b5406879b96024`.
- Experience supplement: `69600ab3c7fa9e373582613bd55d22075234b65a`, read as specification, not merged as a product tree.

The integration uses both real parents; no repeated arrival/entry cherry-picks. The disposable source-object/diagnostic workflow is removed in the product tree. User worktrees, databases, media, main and PR #1 are untouched.

## Magnet failure, evidence and bounded fix

Original run `40770139026`, artifact `12852063171`, source `2c8cd037`, checkout `fb5f18ef`: the delegate starts, the 100 ms-grace cleanup fires first, and removal then produces `finished=false`. Failure remains recorded. No missing image is relabeled a success.

Isolated run `40819965387` tests two independently pinned local diagnostic commits. Direct-main-delegate `1b54745ca7a7cef9275b8736de5c154cc124ff5e` and cleanup-grace `3944b6aa20d9ea3024b966ce3b0803b08d81dec2` each passed unchanged magnet+interrupt evidence checks. These are diagnostic variants, not this combined product.

Repeat run `40820327845`: unchanged original and direct-main variant each passed 5/5 native magnet observations. Original readiness-to-completion observations: 656.047, 636.012, 628.309, 638.978, 655.991 ms. Direct-main: 645.989, 636.001, 642.605, 636.011, 640.110 ms. These are small, capture-loaded samples, not latency p50/p95. The original is timing-sensitive rather than deterministically broken; these results do not isolate the extra dispatch as its sole cause.

The product delta avoids an extra queue turn when `animationDidStop` already arrives on the main thread and allows 500 ms of bounded completion-delivery grace. **The 560 ms trajectory, asset-ready origin, one-sprite limit and immediately live input islands do not change.** Watchdog termination remains `timedOut`, never `finished`. The previous software test accepting either result is replaced by a strict natural-finish assertion, with a separate stopped-render-clock timeout test. The actual pixel/MOV driver still requires a genuine `finished=true` delegate. Exact combined-tree verification is recorded only after it runs.

## Semantic conflict decisions

Preserve PR #15 integrated RiftSettingsForm, five sections, Return/save behavior, source preference observation and latest Feedback backend. Preserve PR #14 strict canonical/legacy preference migration, complete disable lifecycle, safe hidden-directory/ordinary-leaf capture, fd/identity checks, exclusive publication and explicit built-in application import.

Disabling remains effective in the running session even when persistence fails. The integrated settings snapshot therefore carries actual effective state plus a save-failure fact; it cannot roll the switch back on or display “saved”. Enabling still requires a successful durable save. Collection rechecks do not disable this independent local stop control. Default-mode changes preserve fixed slots until the next session.

Both original unit-test bodies are retained apart from explicit API adaptation to the unified settings form. Additional regression coverage checks failed-save disable/enable presentation. No import origin is inferred from system xattrs. Built-in originals and edited derivatives remain `applicationScreenshot`; current upload admission remains closed for that origin.

## Experience disposition at this checkpoint

Q01: capability-specific first-use titles and explanations are consistent. Q02: optional one-page redesign is not adopted; the existing three-page flow remains. Q03: confirmed request and next mode are independently presented, with the original countdown, fixed slots, moving X, exposure exclusion and session cancellation. Q04: the same pointer-free peek panel presents owner/revision-bound reasons; repeated projections do not renew timers, and settlement refreshes an initially deferred prepared state without replaying input. Q05: already-readable source access no longer prompts redundant authorization; existing separate capture/Automation guards remain. Q06: complete history previews use a separate single-flight bounded decoder, checked file identity and SHA256, stale-result rejection and correct Retina small-image sizing. Q07/Q08: persistent service capability, safe destructive defaults, guarded save-close, explicit retry and body-only copy are implemented. Q09: existing five-section settings/window behavior is retained with app-scoped Cmd-, and standard editing actions. Q10: actual CI accessibility variants remain required; physical environment coverage is separately blocked by the offline authorized Mac. All new native behavior remains runtime-pending until the exact combined CI executes.

## Verification and boundaries

The final-source gate pins the non-author-reviewed source above. A software build/test result never substitutes for that review. Native/Feedback workflows run exact combined objects on their normal checks; inherited acceptance scripts are not rewritten to accept this delta. Two architectures, production capture component probes, original-pixel visual/MOV checks and actual runner accessibility variants are retained.

Physical mouse, real Mac permissions, Retina/mixed screens/Spaces, new built-in ChatGPT attachment, Gatekeeper/notarization, and Feedback HTTPS-to-private-Issue acceptance remain NOT_RUN/BLOCKED. Feedback endpoint stays nil. No old H upload is repeated, no UNKNOWN or original media is cleared, and no cloud/private data is collected by this integration.

## Continuation: actual blockers and bounded repairs

The latest branch was refreshed rather than assuming the prior diagnostic-workflow failure persisted. `b3cec64f0ecbf869aff3b17b88d55323d1765393` already includes PR #14 with both parents and removes the disposable workflow. Native [40821969722](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40821969722) failed because three retained integration-test references used the old `isEnabled` property. Commit `d7080499ef4d50ab612c456246da4e1b7688a095` adapts those names to `builtInScreenshotEnabled`, retaining every assertion and expected value. Its non-author review passed.

Native [40830335742](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40830335742), ARM job `123302828056`, compiled and exposed the next genuine failure: AppKit changed the settings scroll style from overlay to legacy during replay; clip width changed 476→461pt and preview width 444→429pt. The genuine size change correctly cancelled the preview. `autohidesScrollers=false` alone did not prevent this style change. The settings document now reserves the public native legacy-scroller width in both styles, without forcing the user's style. The original width/animation assertions are unchanged. Apple API basis: [preferredScrollerStyle](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle), [scrollerWidth(for:scrollerStyle:)](https://developer.apple.com/documentation/appkit/nsscroller/scrollerwidth(for:scrollerstyle:)). This remains a proposed runtime fix until the exact combined tests pass.

The same reviewed source finishes the remaining Q01 title/capability projection; hides already-satisfied folder authorization; wires app-scoped Cmd-, and standard nil-target editing actions; keeps Feedback service capability visible across edits; binds destructive sheet defaults to Keep; and adds explicit safe-close reasons, retry-save and body-only copy. Screenshot admission, Core/Adapters, capture/import, Feedback engine/service and all historical evidence are unchanged from `d708049`.

Non-author review was split by authorship: the Feedback author reviewed Setup/Main and the unchanged protected composition; a different reviewer examined all Feedback UI/tests and the scroller fix. Both reviewed exact `a3d18b5`, with no unresolved findings. Prior `b3cec64` full-composition review also found no new integration safety defect and ran all 24 final-isolation regressions. These are source reviews, not GUI or cloud acceptance. Q06 preview work is still separate uncommitted work at this checkpoint; Q03/Q04 and remaining Q05 are not claimed implemented.

## Reviewed combined experience source

The next source checkpoint is `c81f24b388c0a4d54c3c470a23df60f0cc31b6a3` (tree `2f21eea44cebde6de3111607ccc2dcc2eb88d474`), a descendant of the same Draft PR #15 and both original integration inputs. No independent product branch is introduced. Native run [40831099906](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40831099906) passed source admission but stopped at the new sheet test's missing Swift argument label; this checkpoint changes only that call to `performKeyEquivalent(with:)`, preserving the original Return/Escape, queue-state and send-count assertions. No runtime pass is inferred from the compiler repair.

Non-author review is bound to exact Git blobs: the integration reviewer checks the unchanged security composition, helper, workflow and Main wiring; the experience reviewer checks Q04 and the independently authored Q06; the lead checks the independently authored Q03; the magnetic reviewer checks the Feedback test API correction. The Q04 review found a deferred prepared-state projection and required a read-only refresh after the exact selection is released. The Q06 review found an unverified thumbnail fallback and required an initially empty full-preview shell plus a valid-PNG replacement regression. Both findings are repaired; no self-review substitutes for these independent module reviews.

The original native driver is byte-for-byte unchanged: all 46 scenes and five real WindowServer MOVs remain required. Six additional static captures follow that full suite: history portrait/light, wide/dark, missing file at 360×280, Feedback actual fixture SQLite save failure at 560×500, queue explanation and confirmed-countdown/next-mode presentation. The supplemental verifier reuses the original source/hash/pixel/owned-window checks and keeps the one-titled-window requirement. Its local self-check rejects 34 unsafe observations; original 18 visual-manifest and 24 final-isolation regressions pass. These are Linux checks of scripts, not Swift/macOS execution.

Supplemental files are synthetic and helper-owned. The SQLite fault is a fresh private journal-path collision using the real save path and DisabledFeedbackTransport; it neither injects a production bypass nor accesses user data. Capture state and queue explanations are explicitly synthetic presentation fixtures, not real capture, rejection or upload evidence. Endpoint configuration, cloud deployment, private-Issue delivery and real ChatGPT acceptance remain unchanged and unverified.

## Native runtime findings and next reviewed repair

Exact HEAD `f744aa703bf4421efd929463b0005930fba267e2` passed all four source-admission jobs. Native [40833279966](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40833279966) compiled on ARM and Intel, then the full 723-case test invocation stopped on three failure groups: the Feedback sheet lost its Keep default and Return did not dismiss; AppKit advertised the expected plain-text compatibility type in addition to `.string`; and the history replacement regression remained in loading state. No original 46-case/5-MOV or supplemental visual result exists for this failed run. The two prior settings-width assertions did not recur, but no successful detailed suite was inferred from a failed full invocation.

Feedback [40833286409](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40833286409) compiled and ran 49 native cases; five assertion failures belonged to three cases. Its 117 isolation and 20 Node service tests passed. Repeated-close tests and demo packaging did not run after failure. Native PR ARM job `123312149222` additionally observed the unchanged deadline regression still prepared after its fixed 150ms wait; both push architectures executed it without failure. Core and that original test are unchanged, and the next complete run must still pass it.

The reviewed repair `ee538eb7e3aedc459cbccffbeb0337918fa13b6b` (tree `dcfeb2d5cfc1148a3910c4e177ae7255c77c2c89`) changes only five files. Sheet key equivalents are configured before presentation, then Keep receives defaultButtonCell and first responder synchronously after beginSheetModal. All original Return/Escape/default/queued/zero-attempt assertions remain, with a further post-layout stability assertion. Clipboard checks allow only the two observed plain-text representations and require each to equal the original body.

History uses a bitmap-independent image-view intrinsic size and a bounded footer, ensuring an empty preview has a positive viewport before decode. This removes the source path where a zero viewport returned silently without starting verification. A new actual AppKit empty-shell→verified-image→minimum-window regression checks usable dimensions and original-byte preservation. The rejected valid-PNG replacement still has its original two-second failure requirement; no decoder, hash, file identity, ownership or display budget guard changes. The historical logs did not report viewport dimensions, so final confirmation belongs to the new native execution. Non-author review is bound to exact source objects: magnetic reviewer for Feedback, experience reviewer for history.
