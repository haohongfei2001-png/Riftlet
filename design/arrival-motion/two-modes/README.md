# Riftlet · Arrival motion / Two-mode decision

Date: 2026-10-28. **User-approved modes: `none` (无) and `magnet` (磁力吸引) only.** This replaces the nine-mode candidate list in Issue #6 for product scope. All other motion explorations remain historical research; they are not selectable options or pending defaults. **No production default has been approved.** The offline prototype initially shows `none` as a conservative preview baseline, which is not an App-wide default decision.

## Deliverable and status

- `Riftlet-Arrival-Two-Modes.html`: a standalone synthetic, interactive 1440×900 logical-point desktop. Tests capture types, 3/12 captures, queue interaction, upload-start swallow, explicit-failure rebirth, source-unavailable and second-display fallback, reduced motion, mode settings and frame playback.
- No real screenshot monitoring, no actual upload, no macOS preference mutation, no AppKit build in this design branch. The real engineering branch, active macOS tests, and PR #1 remain untouched.
- The artifact is an implementation prototype, not final evidence of real macOS source-rectangle availability, window level, performance or click-through behavior.

## 1. No animation · `none`

`assetReady` immediately displays the final aspect-fitted image. Decorative source overlays, arrival, press displacement, swallow displacement, row sliding, and rebirth movements are **zero duration**. A successful start still has the same authorization/evidence gating as the formal system: showing without motion is not permission to upload, assume success, delete the source, or retry an unknown operation.

The visible rift exists only while the queue has visible records. Queue numbers, target identity, click and selection semantics do not change. Failure restores the **same** asset, as an ordinary clickable thumbnail; UNKNOWN remains hidden. Reduced motion uses this same static presentation, not a third preset.

## 2. Magnetic attraction · `magnet`

Use the same source image as the durable queue asset, rendered only as a non-interactive decorative copy. Animate its spatial trajectory, never the original screenshot file or the underlying desktop pixels. All times start at **assetReady**, never at keyboard shortcut press or file-system event receipt. Nominal duration **560 ms** is a design candidate for native acceptance, not a hard gate.

| Segment (relative) | Time | Motion and continuity |
|---|---:|---|
| 1 · Form small copy | 0–123 ms | Draw a bounded image copy at the source center (initial footprint at most 240×150 pt). Ease to a clear **58×46 pt maximum** preserving the source aspect ratio. Avoid a whole-screen flash for full-screen screenshots. |
| 2 · Charge | 123–224 ms | 1.5 damped cycles along the vector pointing to the rift. Maximum longitudinal displacement **1.85 pt**, tiny perpendicular offset and tilt (≤0.008 rad). The center returns to its stable starting point. No visible repeated shake at rest. |
| 3 · Attraction | 224–484 ms | Travel toward the target on a near-straight path with normalized progress **t²·²⁵**. Scale continuously from the small copy to the final fitted-image size as the image reaches the fixed edge plane. The last part is clearly faster than the first. |
| 4 · Cross the edge | 484–560 ms | The source copy is fully occluded; the target copy emerges from behind the same fixed edge with **ease-out cubic**. The two phases meet at the occlusion boundary—no arbitrary teleport, bounce, burst or flash. |

The screenshot remains fully usable **from assetReady**. `pointerDown` on its assigned row identity cancels any decorative source motion immediately, preserving the existing 80 ms interaction press and the independent receipt-driven `uploadStarted` / failure / UNKNOWN semantics. The prototype allows clicking mid-flight, but native input-window behavior still requires real GUI evidence.

### Geometry and guards

The existing engineering fit envelope is **72×56 pt** with aspect ratio preserved, approximately 25% width occluded, a **0.7 pt** straight edge and an 8 pt outer no-input inset. In the synthetic 1440×900 scene the contact plane is x=1432 pt, the first image is centered about y=207, and row pitch is 60 pt. These are not universal device coordinates.

Source geometry is **optional** and must be credible and convertible to the target screen's point-space. A candidate source is `com.apple.metadata:kMDItemScreenCaptureGlobalRect` from the screenshot file; its reliability across screenshot types, macOS releases, delayed metadata, Spaces, Retina and multi-display layouts remains **unverified in Riftlet**. Do not intercept ordinary macOS screenshot shortcuts just for this effect.

When missing or stale, on another screen without a validated transfer transform, outside a safe visible frame, during Reduce Motion, or on an overlay/window creation failure, **fall back immediately to `none`** while preserving the stored `magnet` preference for future valid captures. Do not play an unapproved alternate preset. Do not introduce delay to capture ingestion, active hit areas or uploading.

### Concurrency and interruption

At most one source-end decorative flight may be active. A newer capture snaps the previous decorative copy to its final queue state, retains both assets, and animates only the newest. A click or hide/close cancels the associated flight; stale callbacks cannot resurrect or reorder an asset. Queued row display numbers are recomputed only from the real queue. Physical screens, high DPI, 10+ bursts, click-through on overlay edges, self-capture contamination and battery load still need macOS acceptance.

## 3. Proposed native integration contract

Keep one ingestion and upload state machine. Only visual presentation differs:

```swift
// Specification sketch; not compiled and not integrated into PR #1.
enum ArrivalPreset: String, Codable { case none, magnet }
struct ArrivalContext {
    let assetID: UUID
    let sourceRectInGlobalPoints: CGRect? // never assume reliable
    let sourceDisplayID: CGDirectDisplayID?
    let targetFrameInGlobalPoints: CGRect
    let shouldReduceMotion: Bool
}
protocol ArrivalPresenter {
    func present(asset: AssetRecord, preset: ArrivalPreset, context: ArrivalContext)
    func cancelDecoration(for assetID: UUID)
}
```

The native UI should instantiate a temporary click-through visual-only layer for magnet, not an input surface and not a second asset. Its teardown is independent of upload success. The actual `RiftLayout` row hit windows and `PointerSelectionGate` keep controlling pointer ownership. A single preference enum is stored; user-facing settings expose **only** 无 / 磁力吸引. macOS Reduce Motion is a presentation override, not a selectable third mode.

## 4. Acceptance criteria

1. `none`: 0 ms decorative motion for arrival, press offset, swallow, queue shift and failure rebirth; asset identity and upload gating unchanged.
2. `magnet`: visually readable small image at full/window/region source, subtle directional trembling, accelerated attraction, continuous clipping into a straight rift, no particle or flash.
3. Any mode: a row is selectable during arrival, no phantom second click after queue compaction, and no uploading without valid current target or actual start receipt.
4. For missing source/unsafe screen conditions and Reduce Motion, presentation is instantly static but the capture is not dropped; no unapproved effect appears.
5. New captures interrupt only decorative flights, never queued assets, original screenshot bytes, upload receipts or UNKNOWN history.
6. Real Mac gate: System Screenshot PNG and saved metadata on one/two monitors, mixed 1×/2×, region/window/full, Spaces, fast consecutive screenshots and click-through; measure input→assetReady independently from animation duration.
7. CI/reviews for the AppKit implementation belong to the formal engineering integrator; this design branch must not be merged into main or PR #1 without their review.

## 5. Evidence scope

The standalone Chromium in-memory prototype was tested in Linux with synthetic images. Verified: only two UI modes, preference panel's two entries, magnet duration and no-source/dual fallback, mid-arrival selection to simulated receipt-driven swallow, same-asset failure rebirth, and no-animation static effect. JavaScript syntax was checked using Node 22. **No physical Mac screenshot, accessibility/WindowServer, or real ChatGPT attachment test was run for this design candidate.**