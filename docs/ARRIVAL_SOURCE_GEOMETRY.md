# Arrival source geometry: evidence, limits and local probe

Date: 2026-10-28. Scope: optional decoration only. A rejected source does not reject,
delay or change the durable screenshot asset. Actual system screenshots, display
layouts and file-ready timings in this increment remain **NOT_RUN** until observed
on a local Mac; generated plist/desktop tests do not close those cases.

## Evidence and coordinate contract

Apple documents `CGDisplayBounds` in global display coordinates relative to the
main display's upper-left. Cocoa screen coordinates use the lower-left of the
menu-bar display. `NSScreen.main` follows the window with keyboard focus and must
not be used as the primary-display origin during conversion. Screen backing scale
describes backing pixels per logical unit; a file's pixel dimensions are a separate
quantity. Sources: [CGDisplayBounds](https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)),
[Cocoa coordinate systems](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html),
[NSScreen](https://developer.apple.com/documentation/appkit/nsscreen).

No public Apple contract for the shape, units, availability or version coverage of
`com.apple.metadata:kMDItemScreenCaptureGlobalRect` was found during this review.
The ScreenFloat author's first-hand implementation report describes recent
`screencapture` output as a top-left capture rectangle obtainable through the file
attribute; his earlier report describes a historical value containing only X.
These are useful empirical leads, **not current Riftlet Mac acceptance**:
[2022 development report](https://blog.eternalstorms.at/2022/04/29/development-journal-screenfloat-2-entry-3-busy-doing-nothing/),
[2016 investigation](https://eternalstorms.wordpress.com/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/).

`ScreenshotSourceMetadataReader` therefore accepts only a bounded plist array of
exactly four finite numeric values, positive raw width/height, a true screenshot
marker, and exact `selection`, `window` or `display` capture kind. Boolean numbers,
numeric strings, rectangle strings, one-value legacy data and unknown kinds fail
closed. It reads the **original file** after import, through an ephemeral observation
carrying its complete imported signature. Both descriptor/path identity and
metadata stability are checked; no original or private image bytes are written.

`ScreenshotSourceGeometryResolver` requires one unambiguous, unmirrored containing
display, matching AppKit/Quartz logical dimensions, matching image pixels and
backing scale within one pixel of rounding, and the same destination display.
For source rectangle `R` in display `D`, conversion is:

```text
appKitX = D.appKitFrame.minX + R.minX - D.quartzBounds.minX
appKitY = D.appKitFrame.maxY - (R.maxY - D.quartzBounds.minY)
width/height = original logical rectangle dimensions
```

This handles negative display origins without guessing a whole-desktop pixel
scale. It never tries multiple interpretations and chooses the convenient one.
Full-display capture must match the whole display. Spanning captures, another
destination display, overlap/mirroring, off-screen rectangles, missing attributes
and image/scale mismatches resolve to no source animation. Window shadow/padding
mismatches also fall back; no inferred crop, title-bar offset or source window is
invented. These checks establish consistency only: they cannot prove that a new
OS release still writes the same undocumented coordinate convention.

## File readiness and existing collector

Apple's user guide explains that the floating thumbnail remains available briefly
before saving, and that the Screenshot app's Options menu can disable it. It gives
no bounded millisecond guarantee. Riftlet does not change that setting:
[Apple screenshot guide](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac).

The inspected engineering baseline already has directory event monitoring,
complete ImageIO decoding, source signature checks, private copy/hash/fsync and a
durable queue insert. `FolderWatcher` uses a 60 ms first-event coalescing interval;
`CaptureService` requires 120 ms of unchanged signature and starts bounded retries
at 150 ms. In a quiet single-event path this schedules the second scan roughly
210 ms after that event **before copy and persistence costs**. This is code
configuration, not a measured system capture latency or a guaranteed minimum;
extra filesystem events, late metadata and I/O change the actual interval.
Do not add 120 ms again to the 60 + 150 ms scheduling path.

`readyUptime` means durable import notification time, not original capture time.
Recovered/pending sources and delayed observations must not replay a stale source
animation. Animation metadata work belongs off the UI actor; late/absent metadata
must leave the immediately usable final row in place.

## Read-only Mac probe

From an isolated checkout on a Mac:

```sh
swift scripts/arrival-source-probe.swift --file '/absolute/path/to/new-screenshot.png'
swift scripts/arrival-source-probe.swift --watch '/absolute/screenshot/directory' --seconds 30
```

The script opens no capture UI and changes no settings. Continue using the existing
system shortcuts. `--watch` requests 20 ms **probe-only polling**, excludes
existing files, and emits anonymous sample numbers, current display geometry,
raw rectangle/kind, pixel dimensions and complete 64 px ImageIO decode observations.
It never emits image contents, filenames, paths or window titles. Output stays
local unless the operator deliberately shares reviewed metadata.

This standalone observer does not implement or certify the product validator.
`probeFirstSeenToReadableMS` is only a probe interval. Each discovery records the
actual previous/current poll starts and discovery gap: scan/decode work and OS
scheduling can exceed the requested 20 ms interval. Filesystem birthtime is not
capture time; neither keyboard release nor product clickability is observed.
Real capture-to-file and file-to-clickable measurements
require independently correlated operator/GUI evidence and product timing.

Use new, non-private screenshots to record region/window/fullscreen on supported
OS builds at 1× and 2×, plus displays left/above/below the primary and mixed scale.
Compare raw rectangle coordinates with independently known actual capture bounds.
Record missing metadata and shadow mismatch as fallbacks, not failed collection.
Test unchanged topology, topology changes between capture and file readiness,
and another destination monitor. No coordinate convention gains accepted status
merely by passing the synthetic parser tests.

## Subsequent capture pollution

Current Apple documentation describes `NSWindow.SharingType.none` as a legacy
constant no longer used by macOS. It must not be claimed to exclude a decorative
window from the next system screenshot:
[Apple sharing-type documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum).
One bounded nonactivating, mouse-transparent overlay, prompt cancellation,
`orderOut` and resource release limit exposure; real repeated shortcut captures
remain necessary to measure self-inclusion. No private exclusion API or replacement
shortcut is authorized by this implementation.
