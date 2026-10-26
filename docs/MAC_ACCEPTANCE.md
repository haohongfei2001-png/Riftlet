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

The app reloads the system screenshot destination on wake or the developer menu's reload action. Live preference-change notification/bookmark onboarding is a remaining integration task; a menu reload is not asserted as the completed product's everyday workflow.

Real ChatGPT tests are separate and use [the inherited W00–W07/M00–M06 procedure](../research/technical-decision-2026-10-26/03_MAC_VALIDATION.md). Build/test/animation success never substitutes for that evidence.
