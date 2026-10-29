# Unified product integration — 2026-10-29

## Status

Engineering continuation on the existing Draft PR #15 only. **Not a release or fully accepted product.**
The source checkpoint `a3d18b508c5376ddaa87c45b45953d551c8b369f` (tree `f8ac091d8f3b21148a8df1274459f4f2491f921b`) has actual non-author review and is pinned by the final composition gate. Native/Feedback execution remains a separate job: the complete workflow cannot pass without source admission. Existing historical gates and runtime acceptance requirements remain unchanged. Accurate combined CI and new original-pixel review are pending.

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

Q01: existing PR #15 capability-specific first-use copy retained, not redone. Q02: optional one-page redesign not adopted. Q07: existing scalar/UTF-8 shared validation and per-record sheets retained. Q09: integrated settings and prior native window fixes retained. Additional remaining UI changes are not claimed implemented here. Q03/Q04/Q05/Q06/Q08 require checking against this combined tree before further edits. Q10 physical environment coverage remains separately blocked by the offline authorized Mac.

## Verification and boundaries

The final-source gate pins the non-author-reviewed source above. A software build/test result never substitutes for that review. Native/Feedback workflows run exact combined objects on their normal checks; inherited acceptance scripts are not rewritten to accept this delta. Two architectures, production capture component probes, original-pixel visual/MOV checks and actual runner accessibility variants are retained.

Physical mouse, real Mac permissions, Retina/mixed screens/Spaces, new built-in ChatGPT attachment, Gatekeeper/notarization, and Feedback HTTPS-to-private-Issue acceptance remain NOT_RUN/BLOCKED. Feedback endpoint stays nil. No old H upload is repeated, no UNKNOWN or original media is cleared, and no cloud/private data is collected by this integration.

## Continuation: actual blockers and bounded repairs

The latest branch was refreshed rather than assuming the prior diagnostic-workflow failure persisted. `b3cec64f0ecbf869aff3b17b88d55323d1765393` already includes PR #14 with both parents and removes the disposable workflow. Native [40821969722](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40821969722) failed because three retained integration-test references used the old `isEnabled` property. Commit `d7080499ef4d50ab612c456246da4e1b7688a095` adapts those names to `builtInScreenshotEnabled`, retaining every assertion and expected value. Its non-author review passed.

Native [40830335742](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40830335742), ARM job `123302828056`, compiled and exposed the next genuine failure: AppKit changed the settings scroll style from overlay to legacy during replay; clip width changed 476→461pt and preview width 444→429pt. The genuine size change correctly cancelled the preview. `autohidesScrollers=false` alone did not prevent this style change. The settings document now reserves the public native legacy-scroller width in both styles, without forcing the user's style. The original width/animation assertions are unchanged. Apple API basis: [preferredScrollerStyle](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle), [scrollerWidth(for:scrollerStyle:)](https://developer.apple.com/documentation/appkit/nsscroller/scrollerwidth(for:scrollerstyle:)). This remains a proposed runtime fix until the exact combined tests pass.

The same reviewed source finishes the remaining Q01 title/capability projection; hides already-satisfied folder authorization; wires app-scoped Cmd-, and standard nil-target editing actions; keeps Feedback service capability visible across edits; binds destructive sheet defaults to Keep; and adds explicit safe-close reasons, retry-save and body-only copy. Screenshot admission, Core/Adapters, capture/import, Feedback engine/service and all historical evidence are unchanged from `d708049`.

Non-author review was split by authorship: the Feedback author reviewed Setup/Main and the unchanged protected composition; a different reviewer examined all Feedback UI/tests and the scroller fix. Both reviewed exact `a3d18b5`, with no unresolved findings. Prior `b3cec64` full-composition review also found no new integration safety defect and ran all 24 final-isolation regressions. These are source reviews, not GUI or cloud acceptance. Q06 preview work is still separate uncommitted work at this checkpoint; Q03/Q04 and remaining Q05 are not claimed implemented.
