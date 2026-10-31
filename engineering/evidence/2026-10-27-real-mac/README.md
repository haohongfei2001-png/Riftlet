# Local Mac acceptance and integration handoff

2026-10-27, Asia/Shanghai. This is actual local execution against the existing application, not another implementation. The source checkpoint is `1909771d45ad00290dffe245b9a42e6e9f55203c`; subsequent evidence-only commits do not change the tested native tree. The formal integration owner remains Pro / Draft PR #1.

## Result

| Requested gate | Result | Actual scope |
| --- | --- | --- |
| W2 complete acceptance | **FAIL — not fully accepted** | Five generated PNG inputs on real Chinese ChatGPT Home reached verifiedReady. First selection/focus, independent attachments, controlled late-error compensation/restart and one real A→B→A revocation passed. Existing-thread support, real network anomalies and the full navigation/race matrix remain unproved. |
| N1 complete acceptance | **NOT_RUN as a complete suite** | Three actual macOS window screenshots imported once, originals/private hashes preserved, offline capture recovered; real 2/3/12 helper scenes and reopen ran. Hit-through, physical hotkeys, display/Spaces transitions, lid wake and ten-minute resources remain unverified. |
| System screenshot → one click → real draft → swallow | **NOT_RUN** | Production source/consumption remains disabled. Generated-image success is not permission to bypass production admission. The normal capture queue has three retained screenshots and has not uploaded them. |

The product is **not ready for ordinary daily use**. No ChatGPT message was sent. No main merge, release, website/brand change, second PR, account/security setting or paid service change occurred. The testing application and helper were stopped after the final checks; queues, media, originals and unsent test drafts were preserved.

## Environment and provenance

- Local macOS 27.0 (26A428), Apple M5 arm64; Swift 6.4 Command Line Tools. Xcode/XCTest.framework was absent: local native compilation and standalone SQLite smokes ran, full XCTest ran on macOS CI.
- Chrome 156.0.8078.48, authenticated sessions and working Apple Events. Two Chrome processes with the same bundle ID existed; only one owned the relevant visible windows. The transport now binds PID plus launch identity.
- Two physical displays were present: DELL S2725QS (3840×2160, logical 1920×1080, 120 Hz) and MB16NCG (1600×2560, logical 800×1280, 155 Hz, rotated). Presence does not prove hotplug/fullscreen/wake behavior. Stage Manager was active.
- Initial main was `3f5248d6b1c0d32ad80141cbdee4ee16945e6f7b`, clean. The independently checked formal PR branch was `485fa87a31140f9d2e428db69ec5e0599b1f96ae`. Work used a separate managed worktree and `codex/riftlet-real-mac-acceptance-20261027`; main and Pro's integration branch were preserved.
- Root operated the live Mac. `late_failure` proposed/reviewed Core compensation and authored focused tests; `web_safety` implemented/reviewed adapter/page changes; `native_gui` independently reviewed native/Core integration. Exclusive source ownership was maintained. These are technical reviews, not human GitHub approvals.

## Fixes and source commits

| Commit | Fix and consequence |
| --- | --- |
| `268e70b3a20ec141fd5f7f079a56585f29b06adf` | Synchronous AppKit launch frees delegate Tasks: the original process ran but never initialized the queue/UI. PID-addressed Chrome events avoid the wrong Chrome process. Explicit Chinese Chat/Work gate. SQLite v2 compensation, identity-correlated late failure, idempotent queue revival and observation-only success watch. |
| `0100f4654b079cc05f0bca141a9bf2134d6d6d3e` | Re-arm an invalidated page with a new bounded generation; old operations remain tied to their original generation and cannot replay. |
| `f58b22762d1dc42368a6e13fe2ef3a8e2d156106` | Freeze a pre-acknowledged lease synchronously on the original selection boundary; no post-click recapture. Native event/ACK ordering, wake reset, page focus/visibility lifecycle revocation and synchronous pending-mutation drain. |
| `1909771d45ad00290dffe245b9a42e6e9f55203c` | Separate conservative Chrome-tab serialization from exact receipt identity, preventing rearm/navigation/window movement from bypassing UNKNOWN/compensated locks. Add current-focus hard check (page v4), idle prearming before a new image, AX/held-pointer guard, and helper reopen recovery under Stage Manager. |

Core details and actual standalone checks: [core-review.md](core-review.md). Machine-readable live receipts, original identities, UTC times and sanitized capture checks: [live-evidence.json](live-evidence.json). Native scene/reopen observations: [gui-scenes.json](gui-scenes.json). CI/build results: [verification.json](verification.json).

## Live Web results

All inputs below used the packaged integrated App and generated PNG media. No real screenshot was admitted to the Web adapter. `inputCount=1` is the page's observed file-change count for each operation, not an assumption from a click or a timer. Verified completion required original file hash, exact operation/draft identity, unique attachment identity, observed upload lifecycle and independent final preview pixel comparison.

1. At `268e70b`, operations `C7FFAF4E…` and `534E778D…` each reached used/verifiedReady on the same controlled Home draft. Native CUA thumbnail selections were single actions; Chrome/editor focus remained. The second upload preserved the first attachment and controlled text. Three older pre-input validation failures in the queue were preserved; they are not counted as successful first attempts. The first successful operation therefore has attempt 4.
2. At `0100f46`, `DC0108C2…` reached used/verifiedReady after a new page lease, preserving two earlier attachments. A POST100 fault probe installed through Apple Events observed the UI reach 100% but observed **no upload requests and injected no abort**. Its temporary hooks and UI were stopped/removed. This is **not** a passing network-failure test. An initial late-DOM-error attempt was inconclusive after the lease had been invalidated; the test node was removed.
3. At `f58b227`, `1C95A118…` reached used/verifiedReady with one input, three existing attachments and text preserved, and original editor focus retained. Inserting a test `role=alert` node into **that exact generated attachment card** caused the real observation watch → receipt → SQLite → UI chain to restore the original queue position as unknown/compensated. One compensation audit retained both receipts. An observation click and application restart retained attempt 1, one input and one audit row. Removing the test alert did not reconsume or retry. This is a **controlled DOM error**, not a network failure.
4. On the same v3 page, actual Chrome tab A→B→A switching changed the original lease from valid to invalid even though focus returned. The original input count remained one. This tests page epoch revocation, not every delayed native-event or two-window race.
5. At `1909771`, v4 rearmed the original tab. Native AXPress on another pending image created `36A24D96…`, which failed **before input** with “Original draft has an unresolved upload; no input occurred.” The older compensated operation remained. This verifies the tightened lock in the integrated App.
6. In another controlled Home tab, v4 operation `5B04733C…` reached used/verifiedReady with one AXPress, one input, hash verification and pixel proof. The new Home tab already contained the same original controlled text; that text and editor focus were preserved. Attempted setup of replacement text refused because the draft was already nonempty; the existing text was not overwritten. This is an AX invocation test, not physical mouse-down timestamp evidence.

Two existing conversation tabs were structurally inspected under the user's explicit authorization. One contained several writing-document editors plus a single actual form composer; neither supplied the observed Home Chat/Work group. No private conversation text was exported and no attachment was inserted into either thread. Current source reliably refuses those structures; it does not claim arbitrary thread support.

An automation pitfall was also resolved: selecting a tab in a background Chrome window does not make that window the active upload target. Final native tests explicitly brought the intended window to the front and verified the exact tab. The production transport itself never activates a different window; it rejects a mismatched active identity.

## Native acceptance detail

| Case | Actual outcome |
| --- | --- |
| N01 originals/import | **PASS, scoped**: three `/usr/sbin/screencapture -x -o -l` captures of the safe helper window into the configured directory. Native screenshot metadata true; originals preserved; private SHA-256 equal; exactly one new row per capture. No physical-hotkey claim. |
| N02 baseline/restart | **PASS, scoped**: first normal launch imported zero historical files; captures increased 0→1→2→3; the third occurred while Riftlet was stopped and imported once on restart. Equal-pixel captures remained separate occurrences. Actual save-location setting change was NOT_RUN. |
| N03 storage failures | Synthetic/native Core/Capture tests only; no live disk-exhaustion claim. |
| N04 first selection/focus | **PASS, controlled Web subset** for generated-image CUA/AX selections and retained editor focus. Physical pointer timing, every thumbnail, and typing during an in-flight slow upload are NOT_RUN. Continued text after a completed upload was preserved. |
| N05 hit-through | **NOT_RUN conclusively**. App-bound automation can target an underlying window directly; System Events coordinate calls produced no helper mouse-event evidence. Neither is accepted as physical transparent/gap hit-through proof. |
| N06 scenes/displays | Real helper scene counts 3→12→2→3 ran; twelve native row windows and the decorative line were observed. Main controls hidden by Stage Manager were restored via the new standard reopen handler. Ratio/overflow/fullscreen/Spaces/hotplug/lid matrix is NOT_RUN. |
| N07 pointer/reorder/double-click | Deterministic model tests and code review only; held physical pointer/reflow and rapid double-click GUI acceptance NOT_RUN. |
| N08 self-inclusion | Window capture of the safe helper worked. Cmd-Shift-3/4/4+Space/5, delayed/floating-preview and full-screen self-inclusion NOT_RUN. |
| N09 resources | Ten-minute idle/burst/wake measurement NOT_RUN. No zero-CPU or memory budget assertion. |
| N10 latency | Two command-level observations: capture 0.127/0.128 s; capture-return→database observation 0.311/0.438 s, the latter including restart. These are **not** measured T0→T1→clickable-T2 and do not prove the end-to-end latency budget. |

## Remaining delivery blockers

- Prove actual interrupted and post-100% network failures in the page's true request execution context, including associated error/automatic-retry behavior. The attempted bridge did not intercept requests; do not relabel it or a DOM fault as this evidence.
- Implement and test a narrowly evidenced existing-thread/mode profile. Do not select the first visible textbox or infer Chat merely from `/c/`.
- Finish delayed-click/fast navigation/multi-window/multi-profile and same-URL business-draft replacement evidence. Prearming improves availability but a click before a verified ACK must still refuse; first-click success on a just-opened/unarmed surface is not guaranteed.
- Lease generations and watches are bounded (32 page generations/operations per generation; 64 watched successes). They fail closed. Continuous ordinary-use behavior at those bounds is not accepted. Genuine logical draft identity is still needed to replace the conservative whole-tab unresolved lock; no retry profile exists to clear an ambiguous old upload.
- Finish the physical N1 cases above, then independently admit the specific production source/completion/failure profile and run the actual system-screenshot two-operation path. Do not remove the synthetic-only fence for a demo.

## Pro integration instructions

The independent branch is the deliverable; do not reset or replace the formal engineering branch. Preserve any current Pro changes, fetch, and apply the four source commits in order on Pro's own integration worktree, followed by the evidence-only commit(s):

```bash
git fetch origin codex/riftlet-real-mac-acceptance-20261027
git log --oneline 485fa87a31140f9d2e428db69ec5e0599b1f96ae..origin/codex/riftlet-real-mac-acceptance-20261027
git cherry-pick 485fa87a31140f9d2e428db69ec5e0599b1f96ae..origin/codex/riftlet-real-mac-acceptance-20261027
```

Run the required native/page checks on the resulting integration tree. The same Draft PR #1 remains the review entry; this task did not modify its branch or merge it. Migration is transactional v1→v2; retain existing queue/media and do not downgrade the database or replay UNKNOWN. A previous page-program generation's operations remain observation-only if the new program cannot recover their original state.

The next concrete product step is the narrowly scoped real network-failure harness plus an evidenced ordinary-thread Chat discriminator. The local Mac is available; the old “Mac offline” checkpoint is historical, not a current blocker. No background coding service or periodic automation was created.
