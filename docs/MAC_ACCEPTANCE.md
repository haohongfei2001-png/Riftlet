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

## W2 integrated Web acceptance entry — available, live test NOT_RUN

The actual [source/evidence handoff](../research/web-attachment-handoff-2026-10-27/README.md) is archived at its exact `6f415698` version. The integrated program and App at `97f10b0` compile and pass the native/offline CI. The authorized remote Mac is currently offline; these commands are the direct continuation point, not a claim they ran live.

```bash
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --web-acceptance-self-check
open -n build/Riftlet.app --args --web-acceptance
```

The self-check does not contact Chrome; it verifies bundled resources, mode separation and synthetic-only consumption policy. The interactive mode visibly says **WEB ACCEPTANCE** and has a separate `Riftlet-Web-Acceptance` data root. It creates three ImageIO-generated PNGs, never starts system-folder collection, and validates all recovered records before constructing the real adapter. Quit other modes of the same build before interactive acceptance so their rifts cannot be confused. The menu can add a new generated batch without deleting unresolved history. Do not delete the acceptance database to disguise an UNKNOWN result.

1. Use an authorized test draft in foreground Google Chrome, exact `https://chatgpt.com/`, Chat selected and the observed Chinese UI. Existing text/attachments may remain and must be preserved. Nonmatching routes and input structures are refused. Other threads/locales and Work are outside this acceptance scope and must not be used; the program does not yet independently identify the selected Chat/Work mode. Respect existing Automation/Apple Events JavaScript permissions; the app does not change these settings.
2. Keep the draft input focused and click one generated thumbnail. Record first-click behavior, retained focus, one input, matching image and original draft. The adapter observes its own lifecycle and exact bytes/RGBA; elapsed time never proves success. Only the generated-image development profile may persist `used` and show the existing swallow animation.
3. Observe the same operation through a delayed completion, interruption, route/tab change and restart. Click on UNKNOWN only calls observation, never append. A restart may query Chrome for an old operation; it never starts a new input. Missing original observer/document remains UNKNOWN, and no safe-retry profile exists.
4. Record the tested source SHA, actual OS/Chrome/UI scope and sanitized per-operation evidence. Extend the actual target observations to existing chat threads and click-time browser-tab changes before production admission. Native foreground/window checks alone are not proof of the click-time tab.

Run N01/N02 with the ordinary capture mode and N04–N07 with the existing GUI helper in the same authorized session. Passing the generated-image upload path does not by itself prove **system screenshot → first thumbnail click → correct live draft → safe swallow**. That final product loop remains the highest acceptance gate. The existing used record retains local bytes; post-consumption late-failure queue revival is still unimplemented and unverified, so the production registry stays empty.
