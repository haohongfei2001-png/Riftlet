# Native foundation acceptance on a real Mac

Status: checklist, **not passed GUI evidence**. Commands require macOS 13+ and Xcode Command Line Tools / a compatible Swift toolchain. Do not repeatedly audit installation; run once and record any exact missing prerequisite.

```bash
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
open build/Riftlet.app --args --simulate
```

The synthetic mode clearly says SIMULATION, uses `Riftlet-Simulation`, does not watch Desktop or connect to ChatGPT. Its successive clicks demonstrate success, explicit failure and UNKNOWN. UNKNOWN may lock that synthetic draft; it must not re-upload merely to make the demo look successful. Quit it before testing normal collection with `open build/Riftlet.app`.

The built app has an ad-hoc development signature. This is build validation, not a notarized download or public release. A signed/stable bundle and onboarding permissions remain release work. No new daily shortcut, picker or confirmation is introduced by the intended completed product.

| Case | Method and acceptance |
| --- | --- |
| N01 original preservation | Take three **system** screenshots into the configured local folder; check source still exists and private byte hash matches. Ordinary copied image with screenshot-like filename must not enter. |
| N02 baseline/restart | First install does not flood existing screenshots; quit, take a new screenshot, relaunch; new screenshot appears once. Repeat events/rename do not create duplicates; separately captured equal pixels remain separate. |
| N03 partial/failed storage | Run synthetic filesystem tests. In a scoped test directory verify partial writes/delayed metadata/directory replacement/disk errors; never delete original or mark import seen before durable success. |
| N04 nonactivation | With a separate text field focused, click each thumbnail and type a character. Focus remains in the original input. No Send/Return is generated. First click works without activating Riftlet. |
| N05 hit behavior | A lower-window click counter verifies gaps, outer8pt, number, image, transparent corners and animation boundaries. `hitTest(nil)` or a screenshot is insufficient evidence. |
| N06 display | 2/3/12 images; screen scale1×/2×, small height, fullscreen app, Space changes, Stage Manager if used, external display remove/add and lid sleep/wake. No unreachable/newly lost item; scroll overflow preserved. |
| N07 pointer binding | Press on A while state update removes another item; release selects original A. Rapid double-click never attaches the replacement row. Numbers become contiguous only after shift. |
| N08 system self-inclusion | Test Cmd-Shift-3/4/4+Space/5, timed and floating preview variants. Record whether rift/image/number appears. No prior promise that sharingType.none excludes it. |
| N09 resources | Ten-minute idle CPU/footprint/wakeups, then a burst and wake cycle. Report actual values and environment; no invented zero-CPU/MB claim. |
| N10 latency | T0 system capture done, T1 complete file available, T2 persisted and clickable; separate T0→T1 and T1→T2. The floating thumbnail delay is not watcher latency. |

Record OS/build/chip, toolchain, screen scale/visibleFrame, source destination and preview setting once. Use only synthetic fixtures in public logs. Actual screenshots remain local. The source path's system permission may need one-time authorization; do not ask for full-disk/screen-recording/AX permissions that this collection-only build does not use.

The app now subscribes to screenshot preference file/parent events and automatically rebinds through `CaptureSourceBinding`; synthetic plist replacement, parent recreation, old-folder partial files and restart cases pass macOS CI. Actual Screenshot.app preference propagation remains N01/N02 acceptance, together with any one-time permission/bookmark onboarding. Wake and menu reload are recovery paths rather than the claimed ordinary workflow.

## Synthetic GUI acceptance helper

`RiftletGUIAcceptance` is a separate executable, not a resident service or production upload adapter. CI archives it as `Riftlet-GUI-Acceptance.zip`. From source on an authorized interactive Mac:

```bash
swift run RiftletGUIAcceptance --self-check
swift run RiftletGUIAcceptance > /tmp/riftlet-gui-observations.jsonl
```

The first command verifies generated image bytes/hash/dimensions and layout/state fixtures; its marker explicitly says `GUI_NOT_RUN`. The second opens actual 2/3/12 synthetic scenes. Use the helper's underlying click probe and focus field for N04/N05, then repeat with a separate application for cross-app focus. Use delayed reorder while holding a thumbnail for N07; compare recorded asset IDs rather than changing row numbers. Success/failure/unknown controls are clearly simulated; they supply no ChatGPT receipt evidence.

JSONL records synthetic IDs, event counts, geometry and focus observations; typed text and key codes are not logged. No automatic GUI PASS is emitted. Record the exact tested source SHA, OS/screens and the observed N04–N07 outcomes. Missing physical screens or an interactive session leave only the relevant cases untested.

Real ChatGPT tests are separate and use [the inherited W00–W07/M00–M06 procedure](../research/technical-decision-2026-10-26/03_MAC_VALIDATION.md). Build/test/animation success never substitutes for that evidence.

## Formal combined-source checkpoint

The formal branch now includes third-round `11aec04` / `159b3ef` and the complete `6344eb0` handoff, with the reviewed PID/launch observer-cache fix at `aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b`. Use [INTEGRATION_HANDOFF](INTEGRATION_HANDOFF.md#第四轮直接动作) for the fourth-round worktree and concrete actions. Keep all older branches, stores/media, UNKNOWN, compensation and clipboard journal intact. v7 does not restore all old v6 observation capability; no target backfill, replay or DB clearing is allowed as a workaround.

## W2 integrated Web acceptance entry

The [original source archive](../research/web-attachment-handoff-2026-10-27/README.md), [first-round evidence](../engineering/evidence/2026-10-27-real-mac/README.md) and [second-round evidence](../engineering/evidence/2026-10-27-real-mac-round2/README.md) retain their distinct scope. The current v7 development program supports only the actually observed Chinese Home/thread Chat structures with generated PNGs. Scoped ordinary-thread success, background observation/DOM compensation and a real UI100-bound XHR abort belong to the second-round v6 execution; third-round v7 did not add a new upload. Complete W2/N1 and the production two-operation loop remain unaccepted. The commands below are the existing entry, not a claim they were run on a live Mac by the integrator.

```bash
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --web-acceptance-self-check
open -n build/Riftlet.app --args --web-acceptance
```

The self-check does not contact Chrome; it verifies bundled resources, mode separation and synthetic-only consumption policy. The interactive mode visibly says **WEB ACCEPTANCE** and has a separate `Riftlet-Web-Acceptance` data root. It creates three ImageIO-generated PNGs, never starts system-folder collection, and validates all recovered records before constructing the real adapter. Quit other modes of the same build before interactive acceptance so their rifts cannot be confused. The menu can add a new generated batch without deleting unresolved history. Do not delete the acceptance database to disguise an UNKNOWN result.

1. Use an authorized foreground Chrome test draft with the observed Chinese Chat UI. Home requires its unambiguous Chat/Work header with Chat pressed and Work unpressed. An ordinary `/c/…` route additionally requires the exact marked composer, textbox/input and current committed React business identity; the URL alone grants no authority. Work, temporary, readonly, ambiguous or unobserved structures refuse input. Preserve existing text/attachments and Automation/Apple Events settings.
2. For the focus-retention control, start with the draft input focused and click one generated thumbnail. Separately test a real cold first click without a composer pre-click, deliberate wait or second thumbnail click; prior composer focus is not a product prerequisite. Record any refused cold click as an availability defect, not a passed first-click trial after rearming. Record retained focus, one input, matching image and original draft. The adapter observes its own lifecycle and exact bytes/RGBA; elapsed time never proves success. Only the generated-image development completion profile may persist `used`; early visual swallow separately requires an admitted upload-start profile. Legacy completion without a start event exits silently.
3. Observe the same operation through a delayed completion, interruption, route/tab change and restart. Click on UNKNOWN only calls observation, never append. A restart may query Chrome for an old operation; it never starts a new input. Missing original observer/document remains UNKNOWN, and no safe-retry profile exists.
4. Record the tested source SHA, actual OS/Chrome/UI scope and sanitized per-operation evidence. Complete the real first-click, same-tab A→B→A, same-URL replacement, multiwindow and input-time changes before production admission; the scoped ordinary-thread result does not cover that matrix. Native foreground/window checks alone are not proof of the click-time tab.

Run N01/N02 with ordinary capture and physical N04–N07 with the existing helper. Passing generated-image upload does not prove **system screenshot → first thumbnail click → correct live draft → safe swallow**. POST100 is a real native XHR abort after UI100 with UNKNOWN retention; late post-consumption compensation was tested with a DOM marker, not a network failure. MID never bound/aborted the byte request and remains NOT_EXERCISED. Production success and safe retry stay disabled.

## Fourth-round real-Mac continuation

Follow the [formal handoff](INTEGRATION_HANDOFF.md#第四轮直接动作) directly. Restore a reliable exact-tab connection, then collect event→ACK→frozen target→one input for a real cold-first-click and real same-tab business transition. AX/hover are hints; monitor commit counts are not an ABA verdict. No waiting, second click or pre-click in the composer becomes a daily prerequisite. The read-only MID probe has 12 VM groups but has never been used on a real byte request; actually bind that request before attempting a fault.

Use the existing helper's real geometry, source, `probeKeyInputEligible` and underlying-recipient diagnostics. Present the actual probe underneath before an automated CLEAR/GAP control pair. CLEAR was not hit in the archived automated trial; a predicted row hit is neither a pass nor fail. The prior whole-row acceptance path is unchanged. Rejection of a transparent-area selection alone does not prove cross-window pass-through. Finish held reflow, replacement-row double click, cross-app keyboard focus and screen transitions without relabeling automated input as physical.

N08 is now an actual isolated failure: with only the capture App running and no helper, a system CLI region screenshot contains Riftlet thumbnails. Preserve the private image, investigate a supported exclusion mechanism incrementally, and do not claim `sharingType.none` or unverified hide timing guarantees exclusion. This single CLI case is not the whole keyboard-shortcut matrix. N10 still needs capture-done T0, complete file T1 and first-clickable T2; third-round mtime→import ≈234 ms / firstSeen→import ≈162 ms are partial only. Ten-minute capture-only resource measurements already exist; keep their load/source provenance and measure Web/root-monitor work separately.

Source `159b3ef` passed 228 native tests and 38 page VM tests in CI, but earlier native/helper exploration did not freeze all exact source. Its GUI notes remain scoped observations. Verify the newly integrated observer rebind on actual Chrome relaunch when available; the OS PID-reuse case itself was not run by the integrator. No new production profile or safe retry is admitted.

## 2026-10-27 — latest product UX addendum (P29–P32)

The existing W2 instruction to **keep the draft input focused** is a historical **controlled technical precondition**, not the latest product acceptance requirement. The user's actual V1 requirement is **one Riftlet click without first clicking/focusing a usable ChatGPT text editor**. Read [RELEASE_UX_REQUIREMENTS](RELEASE_UX_REQUIREMENTS_2026-10-27.md) and the [Pro feasibility brief](PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md). Do not replace earlier W2 test evidence; expand acceptance with new cases below:

| New case | Minimum real-environment acceptance |
| --- | --- |
| N11 Web focusless attachment | Foreground supported ChatGPT **Home and existing conversation** with unique usable composer; start with active text cursor in editor, chat body, sidebar or harmless page space; after the first physically real Riftlet click, exactly one append to clicked original draft, old text/selection/attachments preserved. Need no extra text-field click, manual rearm wait or second Riftlet click. A browser address-bar focus or modal must be scoped separately, never guessed as safe. |
| N12 Mac focusless attachment | Supported installed macOS ChatGPT client/variant, real AX tree and field-unfocused cases; no overwrite, wrong target, unintended Send or paste into a different focused control. Do not claim support from synthetic AX/pasteboard tests alone. |
| N13 invalid composer feedback | No valid composer, unsupported mode, source unavailable or permission denied: no real input, no swallow; only subtle press/reset and optional on-demand explanation. Normal success: **no Riftlet success Toast**. |
| N14 self-inclusion feasibility | Independently distinguish capture sources (Cmd-Shift-3, 4, window, Screenshot.app toolbar/timer/floating, multi-display/fullscreen); identify whether Riftlet App or helper made the pixels, document exact OS/screens/permissions, and compare public-API candidates. **No blanket promise of exclusion before proof**, no silent screenshot engine swap. |
| N15 archive-interaction race | Artificially expire a visible screenshot while hovering, mouse down, reorder, upload-start boundary, after wake/clock change; no tile disappears from under the user's active pointer. Reborn failed screenshots retain the normal lifecycle and archiving behavior. |

These are **not yet PASS**. Screenshots and records remain local/synthetic where appropriate. The current production adapters stay disabled until independently reviewed evidence and the established actual Screenshot→Click→Draft acceptance.
