# Riftlet native arrival: none / magnet

Date: 2026-10-28 (Asia/Shanghai). Isolated implementation branch:
`codex/arrival-none-magnet-native-20261028`.

## Scope and baseline

Implementation starts at the actually fetched PR #1 head
`1920e0562db893a3292af89a89270a26ddb46a5f`. Design source is PR #10 head
`0b73291652c11f5cb7b6e2792d001eb3340c988b`, with Issue #6's two-mode decision.
All remote branches were enumerated before implementation; the exact snapshot is
in `engineering/evidence/2026-10-28-arrival-native/branch-heads-start.json`.
The predictive-capture branch was observed advancing separately. Its source is
not merged here; see the explicit overlap instructions in the local handoff.

Only `none` and `magnet` exist in the new runtime enum. An absent preference is
distinct from explicit `none`. The provisional engineering fallback is `none`;
**a final product default remains unapproved**.

This is a Draft engineering deliverable. Read the current validation record for
the actually executed checks and source SHA. A software CI pass is not physical
click, Retina, system-capture, desktop appearance or actual-upload acceptance.

## Architecture

The original capture collector still validates/copies/hashes/fsyncs and commits
the same asset through the same queue. Its new optional `onImported` observation
occurs after durable import, owns no durable state and does not await metadata.
The App schedules publication of each committed asset without waiting for other
files in the scan. The existing collector's `onChange` reconciliation remains.

`ArrivalCaptureBridge` owns one serialized optional source reader. A canceled
queued request skips I/O; an already executing filesystem syscall is not claimed
to be forcibly interruptible. New captures supersede only presentation requests.
MainActor never reads screenshot metadata or waits for an animation.

`RiftPanelController` creates the original visual/AX window and two original
image/number input windows at their final layout immediately. Arrival never sets
the queue's transition latch or owns a selection. ImageIO decodes a bounded
thumbnail off the UI actor. If source metadata is not ready when that first
image is published, it stays static; late metadata cannot hide it or start a
belated flight. The candidate deadline is 350 ms after the post-import boundary,
and stale/recovery candidates with first observation older than 2 seconds are
static. No deadline delays input.

The native source sprite and normal row share the exact decoded CGImage and
trilinear minification. A flight uses the actual row's global image rectangle
and actual clipping edge, never a guessed screen-right point. The normal image
alone is hidden during the flight; its number, AX owner and input islands stay
available. Completion restores the existing image, never a second queue record.

`MagnetFlightPresenter` owns one nonactivating, mouse-transparent NSPanel, one
image layer, a fixed edge mask and one cancelable cleanup watchdog. It has no
reference to the store, adapter, receipt policy or file deletion. A generation
and asset identity protect every completion. All native resources are released
before its completion callback; `.finished` and watchdog `.timedOut` are distinct
presentation results and neither is an upload fact.

## Motion candidate

**440 ms is an adjustable native engineering candidate, not an art-accepted
final duration.** The previous design's 560 ms is retained in its historical
files; no design history is overwritten.

| Phase | Relative time | Native behavior |
| --- | --- | --- |
| Form small image | 0–100 ms | Centered on the validated source; initial cap 200 × 130 pt, never initially larger than the source; quintic smooth shrink |
| Directed charge | 100–170 ms | 1.5 deterministic longitudinal cycles; 1.3 pt upper envelope; no random jitter, rotation, particles or glow |
| Attract and settle | 170–440 ms | One continuous position/size path to the exact final RiftLayout frame; fixed clipping plane throughout |

Small envelope: 58 × 46 pt, aspect fitted. Normal layout remains its original
72 × 56 pt envelope, 25% occlusion, 0.7 pt edge, 60 pt pitch and original input
islands (all existing geometry remains configurable). Extremely small or narrow
screenshots preserve their aspect; no promise is made that screenshot text is
readable at coin size. No source is moved or enlarged to manufacture a path.

For normalized travel `u` the default position progress is
`p(u) = 28u^6 - 48u^7 + 21u^8`.
Velocity and acceleration are zero at both endpoints. Acceleration remains
positive until `u = 5/7`, then the image brakes smoothly into its final frame.
The same sprite crosses the clipping edge, so there is no source/target handoff
midway or abrupt scale/velocity splice. Native keyframes sample the mathematical
plan at a configurable 240 samples/second (about 109 default entries); Core
Animation performs playback without a per-frame Swift timer.

The directionally constrained charge is
`1.3 * sin(3πu) * sin²(πu)` points along the target vector. The formation and size
curves use quintic smoothstep. Timings, both image caps, charge amplitude,
acceleration power, sample rate and minimum travel are independently adjustable
in `MagnetMotionParameters`. The edge and occlusion come from `RiftConfiguration`.

The shorter formation/charge phases reduce desktop exposure. A single shared
path removes the prototype's separate final 76 ms target emergence. These are
engineering reasons to test 440 ms; perceived clarity, fatigue and magnetism
remain physical-Mac judgments, not mathematical or browser-test conclusions.

## Zero decorative wait and no-animation behavior

`none` and system Reduce Motion take the same synchronous static path:

- New rows have alpha 1 and their final frame immediately; no arrival fade.
- Press displacement is exactly 0, not a 2.5 pt translation with zero duration.
- A committed `uploadStarted` visibility change closes the visual and input
  windows and compacts the queue synchronously, with no `asyncAfter(0)`.
- Failed same-asset rebirth and other visible states use normal static rows.
- Switching to `none` or enabling Reduce Motion cancels a current flight,
  finishes an already-authorized visual exit and removes press animation state.

Queue compaction is immediate in **both** modes in this increment. This avoids
moving native hit windows, a 180 ms click rejection interval, and uncancelable
implicit window-frame animation during a mode switch. Magnet retains its own
arrival and the existing receipt-driven short swallow (120 ms engineering
configuration); these never create receipt evidence.

A pointer down or AX press interrupts decorations. If another row's admitted
swallow is underway, its visual exit finishes before accepting the new original
row, without waiting for the timer. The original asset ID, click timestamp,
input-window identity and original press regions remain bound; the existing
double-click gate is not reset. New captures also settle an earlier visual exit
so their appearance is not delayed by it. Existing target/ACK/business eligibility
restrictions still apply; this change does not claim to solve cold-first-click
or original upload latency.

Only committed `visibility == swallowed && reason == uploadStarted` starts the
swallow. READY alone does not. UNKNOWN stays under the original policy and may
not be retried by animation. Safe-failure same-asset restoration is exercised
with software fixtures; the existing real safe-retry admission remains closed.

## Bursts, cancellation and resources

There is at most one source copy and one pending candidate. New capture
notification cancels the old decoration synchronously. Captures less than
450 ms apart settle statically until the capture stream quiets; they remain in
their original FIFO order. Metadata/decode callbacks cannot recreate an older
flight. Hide, close, settings, screen/Space/backing changes and sleep/wake cancel.
A change to the flying asset's actual row geometry also settles it, including
removal of a different earlier row.

The image decode is capped at 768 px; the existing thumbnail cache retains its
16 MiB/32-item limits. A cleared cache generation rejects late decode reinsertion.
Overlay backing area above 32 million pixels fails closed. These are structural
bounds, not measured RSS/GPU/frame-time/power results. Physical resource traces,
thermal behavior and 60/120 Hz appearance remain NOT_RUN until Mac sampling.

## Source rectangle admission

`com.apple.metadata:kMDItemScreenCaptureGlobalRect` is read from the original
file, not a private copy that omits xattrs. The entire original file signature,
screenshot marker and bounded metadata are rechecked. Four finite numbers, a
known capture type, one unmirrored display, consistent image pixels/backing scale,
current topology and the same destination display are required. Missing,
ambiguous, changed, spanning, cross-display, wrong-unit or padded-window results
fall back without delaying capture. No cursor position or window guess exists.

**No OS build has been physically validated for this undocumented coordinate
contract in this deliverable. `ArrivalSourceProfile.admittedOSBuilds` is empty.**
Ordinary execution therefore uses static capture arrival even when `magnet` is
stored. The settings' native preview remains functional. Local engineers can
explicitly run `--arrival-metadata-candidate` to exercise the strict candidate
reader/renderer using new system screenshots. That flag only admits experimental
source geometry; it changes no ApplicationMode, upload policy, database or retry
authority. After evidence review, admit exact tested builds in the narrow profile;
do not accept all versions or substitute a guessed source. The local handoff
specifies this gate and how to record failing conditions.

Current Apple documentation calls `NSWindow.SharingType.none` legacy and advises
against using it for capture exclusion. No such promise or private API is used.
Mouse transparency, short lifetime and immediate cancellation reduce exposure;
they cannot guarantee that a subsequent system screenshot omits the decoration.
That remains a real acceptance condition. See `ARRIVAL_SOURCE_GEOMETRY.md` for
primary sources, transforms, system-thumbnail behavior and the read-only probe.

## Settings and local evidence

The menu has a native “截图动效…” window with exactly two choices and a shared
Core Animation preview. Explicit selection is atomically persisted in the
existing mode data root's `arrival-motion-settings.json`; unavailable/corrupt/
future settings fall back without overwriting bytes. A failed save leaves the
current mode unchanged. Reduce Motion overrides playback without overwriting
the preference. Preview is generated locally and never imports or uploads a file.

`--arrival-trace` emits opt-in JSON software boundaries: durable-import observed,
row/input available, image decoded, decoration started/ended and end reason.
It emits no image bytes, filename, source path, chat or browser content. Its
timestamps are not capture time, display photons or physical input provenance.
Correlate with the source probe and real screenshot action/recording as described
in `ARRIVAL_NATIVE_LOCAL_ACCEPTANCE.md`; do not subtract wall-clock from uptime.

## Protected integration surface

Modified existing product files are only `RiftletMain.swift`, `CaptureService.swift`,
`RiftPanelController.swift` and `ThumbnailCache.swift`. New geometry, motion,
preferences and preview code live in separate files. `RiftLayout`, Core, SQLite,
all adapters, receipt/admission rules, original media and prior evidence stay exact.
Existing animation-specific tests explicitly select magnet; archive fencing now
tests a real active press instead of the retired no-source fade.

The new exact-path audit first executes the immutable 42-check Beta composition
audit on baseline 1920e056. It then checks every candidate-tree object and each
individually permitted modification/addition. No directory is exempted; original
uploads, Feedback, evidence, Package and unrelated code remain protected. The
final audit pins reviewed source/test objects after the source checkpoint.

Deliver through a separate Draft PR targeting the engineering branch. Do not
advance PR #1/main or merge the predictive-entry branch. Local integration and
physical acceptance instructions are in the adjacent handoff document.
