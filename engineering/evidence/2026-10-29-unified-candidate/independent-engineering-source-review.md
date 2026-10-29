# Riftlet unified candidate — independent engineering review

Reviewer: `/root/engineering_review`, a non-author of the original Quiet Edge candidate and of the integration/UI product edits. The reviewer subsequently implemented the **new unified audit only**; that audit therefore requires a different reviewer's approval. No self-approval is asserted for that file.

## Fixed inputs and ancestry

- Latest formal engineering input: `0e7ea8be148e1124b387e799fd886a7830e96559`.
- Native Quiet Edge handoff: `443d21da1a55c0061eafced823b5406879b96024`; its parent is actual tested source `00dedc7f8164643c3435e3f87aa462e28af0b1c8`.
- Common ancestor: `1920e0562db893a3292af89a89270a26ddb46a5f`.
- Initial unified merge: `8dae90d25b38c10faa11d98cfe4f576c27b1b31e`, with the formal input and native input as its two parents.
- Both `5d6a683652d255af8c1d3e0d9533587fcc27a24d` and `d552a7388af3890bf693bb3fb24f4b8fc5bc12e7` are already native-candidate ancestors. No repeated feature cherry-pick is needed.

## Initial merge result

The initial merge is source-correct within the inspected scope:

1. `RiftletMain.swift`, `Package.swift`, all Capture sources and Core sources are identical to the native candidate at this merge checkpoint. Formal `0e7ea8be` had not changed Main or Package relative to the common ancestor.
2. Latest `FeedbackEngine.swift`, `FeedbackStore.swift`, `FeedbackHost.swift`, Feedback engine tests and Feedback service files are identical to formal `0e7ea8be`. The retry scheduling, local cancellation boundary, secure-delete behavior, delivery/deletion race and external-request budget changes are retained.
3. The merged Feedback UI is identical to the native candidate except for the privacy disclosure. It preserves the formal wording that feedback goes to the developer's **private** feedback destination. Its local/outbox status still does not claim cloud delivery.
4. `FeedbackHost.endpoint` remains `nil`. The existing private repository is not recreated. Both CI workflows retain `macos-15` from the formal reliability increment.
5. `FeedbackUI → RiftletUI → RiftletCapture → RiftletCore` introduces no dependency cycle. New application-created/edited screenshots cannot borrow system-screenshot start/completion/retry admission. The candidate-store check excludes synthetic contamination while allowing such non-admitted local images to remain in history.

## Blocking integration issues identified

### E-01: old historical audit pins cannot validate the combined tree

The native `verify-thin-edge-composition.py` requires the historical internal-beta audit blob `94b09b58…` to remain in the current tree. Formal `0e7ea8be` deliberately updated that script to `d02efe1b8655b22a2aae2a347bba3c4d1c9d20f8` to preserve twelve specific Feedback reliability changes. Changing only the native `REVIEWED_SOURCE` cannot resolve this: its unchanged-historical-gate check still fails.

Resolution implemented in a separate new gate, without editing either historical audit:

- Run exact formal internal-beta audit blob `d02efe1b…` at `0e7ea8be`.
- Run exact native thin-edge audit blob `eff1187ef5a46797266cd6aa69e383dfdf4e3a60` at `443d21d`; this in turn retains its original three historical audits.
- Require those two current audit files to keep the exact pinned objects.
- Require both original commits and the independently reviewed source checkpoint to remain ancestors.
- Compare all current paths, modes, types and blobs against that checkpoint. Only the new gate itself and two individually named, already-existing non-executable handoff records can differ.
- Accept a GitHub PR test merge only with an exact `eba1a4fc…` main parent, a separately checked reviewed-candidate parent, and the fifteen individually pinned website objects. No directory or branch-name exception exists.

The new gate's review pin remains **None / fail-closed** until non-author review of the final source checkpoint. Its implementation and regression tests need review by the root or another agent because this reviewer authored them.

### E-02: Feedback source archive no longer closes its dependencies

The Feedback workflow originally archives Feedback sources, selected App files, CSQLite and Package. The native Package now makes FeedbackUI depend on RiftletUI, which depends on RiftletCapture and RiftletCore. That partial archive cannot independently reproduce its recorded Package build. Archive the complete committed source, or include the complete dependency closure. This changes provenance packaging, not runtime scope.

### E-03: pagination fills the final viewport by repeating prior-page items

Current layout clamps the first index to `N - capacity`; the Next button additionally steps by the current visible row count. A sixteen-image queue with capacity fourteen therefore produces `1–14` then `3–16`, and a short final page's Previous step would use the wrong stride.

Recommended repair: clamp to `lastPageStart = ((N-1)/capacity)*capacity` for positive N/capacity, keep arbitrary indexes within that bound for existing one-row wheel scrolling, and use fixed-capacity logical page boundaries for Previous/Next. Use the same final-page calculation for showLatest and new-capture following. The first slot and pager position stay fixed; the rift line ends at the last actual image. Preserve held-asset, selection and reflow fences.

Existing `RiftLayoutTests.testPagerCapacityAndPlaneDoNotMoveWhenSelectingLastPage` incorrectly assumes equal full line heights on the first and final pages. Replace only that outdated expectation with the correct plane/top/last-image assertions, and assert concrete non-overlapping `1–14` / `15–16` page behavior. Do not weaken pointer or identity assertions.

### E-04: display preference write failure initially retained the unsaved popup selection

During review of the new embedded settings form, popup reselection was inside the item-list rebuild branch. On a failed save, `update(snapshot)` has unchanged snapshot fields, so that branch does not execute and the popup can continue displaying an unsaved choice. Move selection restoration outside the rebuild condition and test an injected persistence error. Reported to the integration author before final review.

### E-05: native auxiliary windows can remain below the active selection overlay

The native screenshot selection panels are screen-wide at `.statusBar`; Settings/History/Feedback are regular windows. The original Host only suspends selection for its own options menu and markup editor. Explicitly opening a native auxiliary window while capture mode remains active can therefore leave the selection overlay above the desired window and interpret clicks as captures.

Resolve at the explicit auxiliary-open boundary: cancel the active capture session, or implement a precisely owned suspend/resume relationship. Do not restore focus or resume capture on every generic activation. Keep actual Spaces/fullscreen/focus validation separate from native software tests.

## Completed reviewer verification

- Exact native historical composition audit at `443d21d`: **PASS**.
- Original ThinEdgeIsolation regression suite: **21 / 21 PASS**, executed locally in isolated temporary Git repositories.
- New UnifiedCandidateIsolation regression suite: **24 / 24 PASS**, 13.790 seconds. Includes preserved Feedback repair, unchanged historical gates, wrong/empty historical results, adjacent additions/deletions, mode/symlink changes, metadata restrictions, Git environment redirection, replacement refs, identical trees without reviewed ancestry, website overlay provenance, wrong merge parent and hidden unreviewed candidate-parent mutations.
- New unpinned unified gate executed against initial merge `8dae90d`: both original historical audits **PASS**, both current gate objects and both original ancestors **PASS**; final result **FAIL**, specifically because the reviewed-source pin is unset. This is the intended review barrier, not a production verification result.
- `git diff --check`: no whitespace errors in inspected edits at the time of review.
- Native visual evidence manifest rejection tests: **6 / 6 PASS**, independently executed by this reviewer. They distinguish unavailable capture from captured output and reject pixel/hash/source changes, path escape/symlinks and unsupported real-input/upload claims.

## Scope not asserted

This is not a final candidate approval. The source review follow-up below covers the root's setting/form/pagination edits before their source checkpoint; exact Native/Feedback CI and the final committed object review remain required. This Linux execution environment cannot establish native AppKit compilation, WindowServer pixel output, physical mouse input, real IME behavior, 1x/2x or rotated multi-monitor behavior, Spaces/fullscreen, or real screenshot-to-browser attachment results. Existing H evidence is preserved and has not been rerun. Production upload, safe failure/retry, original-target proof and final content proof remain independent and unchanged.

## Product-source follow-up before the source checkpoint

The integration author implemented the recommended changes and this reviewer independently reread their product code:

- **E-03 repaired in source:** `lastPageStart` and fixed-capacity arrow boundaries produce disjoint logical pages. `showLatest`, new-capture following and count shrink use the same bound through layout. One-row wheel scrolling retains arbitrary intermediate offsets. Existing held-asset, selection and transition gates are unchanged. The layout regression asserts sixteen items at fourteen-row capacity become `1–14` and `15–16`, and checks safe shrink and off-grid arrows. The double-click digit-reflow test deliberately makes items 9/10 visible without removing its identity checks.
- **E-04 repaired in source:** the display popup always reselects the saved ID, independently of menu rebuilding. A failed display or motion save restores the saved selection. Entry/default-mode preferences, motion, display and archive changes persist before runtime state changes. Opening or refreshing the form never writes preferences, starts capture or reopens a closed settings window. Archive input now rejects partially parsed strings such as `1abc` and preserves explicit zero-as-disabled. Entry preference decoding retains the prior default-enabled behavior for older files.
- **E-05 repaired in source:** explicit Settings, first-use, History, Feedback and archive/motion settings open actions cancel active capture first. Permission requests also cancel capture. The change does not add generic activation-driven capture resumption. Entry preference toggles preserve the separate hide preference, and selecting a new default changes the next session's default without reordering the active session's slots.
- The unified settings sections reuse the existing settings window. Motion previews are isolated synthetic local drawing with no permission, screenshot or upload operation. Closing/rebuilding a settings page stops its preview.
- Feedback retains the latest formal draft-save, close, retry and local/cloud truthfulness behavior. The new changes are top-aligned scrolling and first-presentation versus reopen position/size preservation. `FeedbackHost.endpoint` remains `nil`.
- History reduces visual density, hides unavailable actions and retains exact time in the tooltip/details. Restore/removal admission is unchanged. Number pads respect physical backing-pixel stroke width and Increased Contrast. Reduced Transparency overrides the entry surface's parent alpha, so an opaque material is no longer faded by its container.
- No new changes were observed in Core, Capture, Adapters, Feedback engine/store/Host or cloud service runtime files at this review point.

**Source verdict:** no unresolved blocking logic defect found in the inspected product changes. This is conditional source review, not a claim that native compilation or physical acceptance passed. The current shared edits are not yet pinned to a final source commit.

### Native visual evidence helper

The helper's export path is restricted to `--visual-clean` and rejects the software input/AXPress acceptance modes. It creates a new non-symlink output directory, enumerates visible windows from its own `NSApp`, obtains each corresponding WindowServer ID, and passes only those IDs to `CGWindowListCreateImageFromArray`. It does not invoke a TCC request, desktop screenshot command, browser adapter or production data store. The synthetic privacy backdrop covers the selected display's visible frame; auxiliary windows are explicitly layered above that helper backdrop. This is fixture presentation, not production window-order acceptance.

Output PNGs retain original WindowServer pixel dimensions and include source/checkout identifiers, pixel/point scale, timestamps, bytes and SHA-256. Missing native capture becomes `NOT_RUN`; no layer rendering or synthetic reconstruction is substituted. Every manifest leaves physical input, real screenshot, real upload, cross-application focus and normal production window order `NOT_RUN`. The timeline uses sampled native frames with measured timing and capture overhead, not a fixed-frame-rate or latency benchmark. Independent visual review is still required.

The subsequently added MOV writer was also read independently. It encodes the same native CGImages with actual monotonic capture timestamps, caps the capture interval at 6.45 seconds and 200 captures, limits pooled encoder buffers to three, and records backpressure drops instead of interpolating or duplicating frames. Encoder completion is bounded separately. Original content is drawn 1:1; odd dimensions add at most one black edge pixel, separately recorded from content size. Movie failure is reported independently as `NOT_RUN`. The codec is explicitly lossy and original PNGs are retained. Actual compilation, decoded orientation, frame count and timestamp verification remain pending; the Python driver still needs MOV validation/linking at this review point.

`CGWindowListCreateImageFromArray` is a legacy capture API and current macOS SDK compatibility must be established by the exact new native build. Source review alone cannot resolve its availability diagnostics on the selected runner. No dynamic symbol or permission bypass is proposed.

### Exact new audit regression inventory

1. `testExactReviewedCandidatePassesBothOriginalAudits`
2. `testMissingReviewPinFailsClosed`
3. `testProductChangeFailsEvenUnderPreviouslyAcceptedDirectory`
4. `testFeedbackRegressionCannotBorrowThinReview`
5. `testNeighborAddedDeletedOrExecutablePathsFail`
6. `testUncommittedEditsDoNotSupplyExpectedSource`
7. `testIdenticalTreeWithoutReviewedAncestryIsRejected`
8. `testOriginalAuditMustRemainExactEvenInReviewedCheckpoint`
9. `testWrongHistoricalBlobAndEmptyHistoricalListFail`
10. `testDuplicateHistoricalPathFails`
11. `testFalseHistoricalPassWithWrongRevisionFails`
12. `testHistoricalFailureAndEmptyChecksFail`
13. `testOnlyNamedExistingMetadataCanChange`
14. `testMetadataCannotBeDeletedOrSymlinkedOrExecutable`
15. `testMetadataMustAlreadyExistInReviewedSource`
16. `testGitEnvironmentCannotRedirectRepositoryOrObjects`
17. `testReplacementRefsCannotReplaceReviewedObjects`
18. `testExactTwoParentMainWebsiteMergePasses`
19. `testWebsiteOverlayOnOrdinaryCandidateIsRejected`
20. `testUnknownMainAndExtraMergeParentsAreRejected`
21. `testCandidateParentCannotHideUnreviewedChangesInTestMerge`
22. `testMainOverlayObjectAndNeighborChangesAreRejected`
23. `testOverlayPolicyCannotContainWrongBlobOrDuplicateOrTraversal`
24. `testCliRejectsPinOverride`

The root independently reviewed the new audit implementation and tests after this reviewer authored them. The review of product changes is independent of product implementation authorship; approval of the gate is held by the root, not self-certified here.


## 冻结前二次复核记录

非作者 engineering_review 已再次核对两个 workflow 的 unified gate、原测试与 pipefail、完整 Feedback source archive、设置失败回滚/整串小时解析/Return 保存、标题栏可达性恢复、打开辅助窗口前取消截图，以及 helper MOV 验证与独立 NOT_RUN。2026-10-29 本轮冻结前结论为无新增源级 blocker，可创建 exact source checkpoint；Swift 编译、实际 MOV 解码方向/采样 PTS 与新原尺寸视觉结论均等待本轮 CI。此记录不替代最终 SHA 树复核。NativeVisualEvidence manifest 当前 9/9 PASS，前文 6/6 为此前阶段。
