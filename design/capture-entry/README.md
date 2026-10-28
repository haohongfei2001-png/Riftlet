# Riftlet capture entry — high-fidelity interaction reference

This directory preserves the user-selected desktop, thin spatial rift, neutral
glass material, continuous entry reveal, and upward expansion. It adds the two
latest interaction requirements from the 2026-10-28 session:

1. **A successful capture keeps the selection session and toolbar open.** The
   user can capture again or use a queued image; an explicit X / Escape ends
   the session.
2. **Window, region, and full-screen modes keep their positions.** Selecting a
   mode moves one active X cover to that position. It does not swap mode icons.

The baseline was carried from the approved `riftlet-anchored-capture.html`
prototype into the isolated implementation branch based on `b4bcfa41`.
This is a design reference for the native implementation, not an embedded
browser product or an upload-admission policy. The latest session instruction
adds this optional capture entry; existing screenshot collection and the
repository's real upload-start / completion / retry boundaries remain separate.

## Open, edit, and rebuild

- Open [Riftlet-Capture-Entry.html](Riftlet-Capture-Entry.html) directly in a
  modern browser. No server, package installation, network, or account is needed
  to use the reference.
- Edit [source.html](source.html), the self-contained source fragment. Its unique
  root is `riftlet-capture-reference-design`.
- Run `python3 design/capture-entry/build.py` from the repository root to rebuild
  the standalone. `--check` verifies that the checked-in standalone matches its
  source and notices.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) contains the icon licenses.
  Only the 22 icon definitions used by this reference are inlined. The large
  Lucide runtime, external CDNs, and chat visualization wrapper are absent.

These files are design documentation. Do not add them, their desktop fixture,
or their canvas renderer to the App bundle or native runtime dependencies.

## What this browser reference actually does

The Finder and Notes windows, wallpaper, menu bar, and Dock are authored
illustrations. Capture renders only an explicit allowlist of these local
elements into a canvas. It **does not capture the operating-system screen,
inspect another app, invoke system capture APIs, or upload an image**.

Clicking a thumbnail simulates queue consumption and explicitly reports
`SIMULATED`. It never accesses a ChatGPT draft, browser session, clipboard,
native bridge, or remote endpoint. Its timed visual exit is not evidence of an
actual upload start or successful attachment. No actual screenshots, private
chat content, browser credentials, or local user files are distributed here.

The outer demo controls and status text explain the reference. They are not
new native product controls or success Toasts.

## Interaction contract

### Entry and session

The fixed entry becomes visible as the pointer approaches. Its line glyph and
glass opacity are independent, continuous channels. The line becomes fully
legible earlier; the material begins earlier than the previous delayed-glass
experiment and responds more slowly. Neither channel blurs the foreground.
Background blur is part of the unchanged glass material.

Clicking the entry immediately opens the default capture mode. The same glass
surface grows upward, the original entry keeps its bounds, and the default
mode's active X appears at the original position. Input is not gated on the
180ms expansion or the cover's animation completing.

Window mode captures on one target-window click, full-screen mode on one
screen click, and region mode on drag release. There is no additional Start or
Confirm step. Successful capture returns to the same `select` session and
same mode with the toolbar open. Optional countdown / editor screens are
subflows; their successful completion resumes that session. Per-capture
options reset after that capture.

X at the active mode cancels the session. Escape dismisses an open options
panel first and otherwise cancels selection; the optional editor's Escape
keeps its original image and returns to selection. Retraction always ends at
the fixed original entry, including when the active X was in an upper slot.

### Fixed mode slots and moving X

There are three physical mode slots: `base` at the entry, `near` immediately
above, and `far` above that. More is always the highest button.

| Default setting | Base | Near | Far | Top |
| --- | --- | --- | --- | --- |
| Window | Window | Region | Full screen | More |
| Region | Region | Window | Full screen | More |
| Full screen | Full screen | Region | Window | More |

The slot mapping is frozen for the open session. Changing selection changes
only `mode`, the active indicator, and button action/accessible label. The
selected slot's mode glyph is covered by X; the prior slot's original glyph
reappears at its unchanged coordinates. One noninteractive visual cover moves
between the fixed buttons, while their semantic actions change immediately.

Only an explicit default-mode setting changes the mapping. In this reference,
that setting applies when the next session opens, so even a settings change
does not move targets under the current pointer. The setting is in-memory for
the browser reference; native persistence belongs to the native configuration.

### Queue during an open capture session

The rift and queued thumbnails remain visible and operable in `select`.
Their hit targets sit above the selection overlay. Hovering a thumbnail hides
the capture cursor/highlight; clicking it never falls through into a new
capture. The same protection applies to pagination and capture controls.

The first visible queue row starts below the capture controls. A screenshot
appears from the rift at its preserved aspect ratio; the rightmost 25% remains
behind the boundary. The local origin-copy feedback is synthetic and does not
erase the illustrated app window. Three images are shown at once, with a
small paging control for additional items. The source bytes in a native app
must not be cropped to match the thumbnail's visual occlusion.

The browser's simulated consume path retains the existing same-position
double-click protection. Production consumption must instead follow the
existing admitted, asset-bound `uploadStarted` contract; a click alone cannot
authorize swallowing a real screenshot.

## Adjustable reference parameters

All distances below are **CSS pixels inside the 560px-tall fixture**. They are
geometry references, not new global coordinates for all native displays.
AppKit should use its display/visible-frame policy and point units, including
Retina scale, without scaling the fixture desktop into the App.

| Item | Fine pointer | Coarse pointer |
| --- | --- | --- |
| Entry size | 36 × 36 | 44 × 44 |
| Entry center | y=246; 32px from right | y=246; 36px from right |
| Expanded glass | 36 × 132 | 50 × 188 |
| Mode centers above entry | 32px, 64px | 46px, 92px |
| More center above entry | 96px | 138px |
| Upper mode button size | 30 × 30 | 44 × 44 |
| Closed / open radius | 10 / 12 | 10 / 12 |
| Queue row top / spacing | 308 / 62 | 308 / 62 |
| Thumbnail image envelope | max 72 × 48, natural ratio | same |
| Visible thumbnail fraction | 75% | 75%, with at least a 44px hit width |

One material surface owns the border, fill, shadow, and backdrop blur. The
toolbar container is transparent. Light/dark colors remain in the source's
`--rf-glass`, `--rf-edge`, `--rf-selected`, and `--rf-shadow` variables; its
background blur remains 18px with saturation 1.15. The final icon rendering
retains the approved preview's 16px Lucide footprint and local stroke styles.

### Reveal and motion

- Glyph: full plateau at `0.35 × desktop width`, entry radius `0.60 × width`;
  rise/fall constants 18/170ms; per-60Hz-frame alpha caps 0.26/0.08.
- Glass: full plateau at `0.08 × width`, entry radius `0.46 × width`;
  rise/fall constants 96/150ms; alpha caps 0.065/0.06.
- Both have a spatial exit envelope 1.5 times their entry radius. A stationary
  nearby pointer remains stable; moving outside the exit radius reaches zero.
- Weak direction/arrival anticipation is bounded to 700ms and decays over
  240ms. Thumbnail proximity suppresses idle entry anticipation. Actual nearby
  hit targets do not wait for either opacity to catch up.
- Glass opening uses a 180ms quintic smoothstep, interruptible from its current
  progress. Partial reversal scales duration, with a 64ms lower bound. Fine
  height is `36 + 96p`; coarse height is `44 + 144p`, width `44 + 6p`.
- Upper symbols keep their final coordinates and reveal from below. The mask
  edge is `96p + 1` for fine and `max(0, 141p − 2)` for coarse, with the
  zero-progress special case. Its feather points inward and reaches zero at
  the fully open endpoint. This prevents symbols appearing above the glass.
- Active X cover motion is 105ms with `cubic-bezier(.2,.7,.2,1)`. Only the cover
  moves; mode hit targets and original glyph positions remain fixed.
- Arrival/consume/origin-copy feedback is approximately 100/80/80ms. These are
  reference values, not real capture or upload latency claims.
- Reduced-motion mode removes finite visual transitions. No continuous idle
  loop or animation-gated interaction is introduced.

## Native mapping and evidence boundaries

| Native component | Responsibility represented here |
| --- | --- |
| `ScreenshotEntryController` + `ScreenshotEntryConfiguration` (`RiftletUI`) | Independent optical channels, one expanding material surface, fixed mode slots, migrating active cover, immediate actions, settings |
| `InteractiveScreenshotController` + `ScreenshotMode` (`RiftletCapture`) | Real AppKit target-selection overlay and system `screencapture` output for the chosen target; window/full click and region release |
| `ScreenshotEntryHost` (`RiftletApp`) | Connect real result to `PrivateAssetImporter` and the existing `QueueStore`; keep the capture session active after success |
| `RiftPanelController` | Existing real queue, capture-layer ordering and header clearance, scoped temporary suppression needed around real pixel capture |
| `ScreenshotMarkupController` | Optional native per-capture editing, keeping its result/original and returning to the same capture session |

This table records the implementation responsibilities of the parallel native
work, not proof that a particular macOS build has passed GUI acceptance.
`sourceFeedback()` is a local canvas illustration. It must not be cited as
proof that the native app performs source-to-rift motion, excludes itself from
all system screenshots, captures correct native bytes, preserves focus, or
uploads an attachment. Do not borrow this reference's unconditional simulated
consume timer for production.

Real acceptance still requires an actual Mac: permission handling, correct
window/display/region capture, cancellation without output, exclusion of the
app's own UI for its own capture operation, one import per completed capture,
position stability across displays/Spaces/scales, and a queue click that
preserves the actual click-time destination. Existing Core and adapter
admission, provenance, UNKNOWN, original-byte preservation, and safe-retry
requirements remain intact.

## Verification

`verify.cjs` checks the offline reference through Playwright. Set
`PLAYWRIGHT_PATH` if Playwright is not on Node's module path, and optionally
`CHROMIUM_EXECUTABLE` to an installed local Chromium binary. Set
`RIFTLET_QA_ARTIFACTS` to an internal scratch directory to save screenshots and
a JSON result; generated QA captures are not part of the product assets.

```sh
python3 design/capture-entry/build.py --check
node design/capture-entry/verify.cjs
```

The targeted checks cover unchanged slot positions after repeated mode
switches, active-cover alignment, consecutive window captures, immediate
region/full capture, queue click isolation while open, explicit cancel,
settings changing only the next session, cancellation during region drag,
and 320px fine/coarse layouts. Network requests and runtime errors are also
checked. These tests use only the included synthetic desktop and do not admit
any native or real-upload behavior.
