# Built-in capture measurement probe

This standalone macOS 13+ tool compares the existing `/usr/sbin/screencapture` path with public screenshot APIs. It is **not a replacement production backend**, a physical acceptance test or an upload test.

```sh
swiftc -parse-as-library -O scripts/benchmark-builtin-capture.swift -o /tmp/riftlet-capture-benchmark
/tmp/riftlet-capture-benchmark --self-check
/tmp/riftlet-capture-benchmark --iterations 5 --output report.json
```

`--output` creates a new mode-0600 JSON file; its parent directory must already exist. The report also goes to stdout. The default probe calls `CGPreflightScreenCaptureAccess()` before creating an application or enumerating ScreenCaptureKit content. If permission is not already granted, it writes **NOT_RUN** and exits successfully. It never calls the permission-request API or changes macOS screenshot preferences.

With permission already granted, the tool shows one nonactivating opaque window containing only four synthetic color bands and device-pixel checker strips. It samples:

- That exact owned window, without a shadow: `screencapture -o -l`, `SCContentFilter(desktopIndependentWindow:)`, and the legacy Quartz window API where available.
- Two rectangles strictly inside the fixture: one integral and one with `.5`-point origins and sizes. These can expose actual `screencapture -R` fractional parsing and Retina pixel behavior; the string self-check alone does not establish support.
- The selected display only when the caller explicitly passes `--allow-desktop-capture`. CI **must not pass this flag** unless it has an independently proven exclusive synthetic desktop. Without it, full-display samples are **NOT_RUN**.

`--display-index N` uses the 1-based `NSScreen.screens` order observed in that run. The report records bounds, scale and ordinal, without names or display serials. `-R` targets the selected display's rectangle; the tool does not assume `-D` has the same ordering. ScreenCaptureKit region samples use a display filter because its `sourceRect` is ignored for single-window filters. SCScreenshotManager requires macOS 14; the legacy Quartz comparison is conservatively not run on macOS 15 or later.

## Optional synthetic image evidence

```sh
/tmp/riftlet-capture-benchmark --iterations 5 \
  --retain-synthetic-images test-results/capture-synthetic-previews \
  --output test-results/capture-benchmark.json
```

The preview directory must be **new**, with an existing parent. Only an owned-window or interior-region sample whose **every decoded pixel exactly** matches the controlled fixture is eligible. Any mismatch retains no preview. Both bitmap row conventions are accepted by the privacy check; that check does not prove correct orientation. WindowServer checks before and after screen-region capture also reject a foreign window above the fixture. Only sanitized **sRGB RGBA8 re-encodes** are saved, with no arbitrary text, EXIF or custom profile labels. Their separate hashes are reported; these are actual captured pixels, **not original PNG byte or wide-gamut evidence**. Original PNG dimensions, bit depth, chunk types, whitelisted color-space description and digest are recorded before conversion. Full-display bytes are **never** retained as artifacts, even with the explicit desktop flag.

The CLI needs a private temporary PNG. Its unique mode-0700 staging directory and mode-0600 files are removed when the sample/run finishes. The tool deletes only its own temporary files. No raw images, source paths, arbitrary window titles, application names, device serials or localized error text are printed. Existing screenshots and Riftlet data are never read or modified.

## Reading the measurements

`captureMS` has different native boundaries: CLI launch through process exit includes PNG encoding and disk output; SCScreenshotManager/Quartz measure API call through returned CGImage. `pngStageMS` is CLI file read or API-image PNG encoding. `readyToInspectPNGMS` is the closer end-to-end comparison, including permission/fixture checks and these stages, **before** metadata inspection and optional preview creation. It is still not click-to-thumbnail or Riftlet import latency.

Each variant labels its first call in the existing process and later warm calls. The process may have used a different variant/backend earlier, so this is **not a cold OS cache benchmark**. Failed first calls are not replaced by later successful calls in first-call summaries. `sckEnumerationMS` is reported separately. Repeat the whole process for startup distributions; do not infer p95 or a winner from five samples.

Memory readings include process RSS, Darwin process-lifetime peak RSS and cumulative child-process peak information. These are **not isolated per-backend peaks**. PNG inspection adds a bounded sRGB decode; it is separate from production processing and from capture memory. There is a 64-million-pixel decoded-image ceiling.

A child screenshot command has a 20-second limit followed by termination of that owned child. The whole probe has a 90-second process watchdog because ScreenCaptureKit cancellation is not assumed to bound a hung framework callback. Timeout reports **INCOMPLETE_TIMEOUT** and exits 3; it does not label an incomplete run successful. Some already validated sanitized previews may remain after that timeout. Individual sample errors are recorded without raw framework error text.

`--self-check` runs PNG/metadata, coordinate formatting, median, full-pixel preview allowlist and contamination rejection using memory-only synthetic bitmaps. It does not initialize NSApplication, check/request TCC or capture a display. macOS CI's successful self-check means **software-only PASS**. A successful default probe means actual API capture of synthetic content on that runner; physical mouse/drag, permission refusal/revocation/recovery, multi-monitor mixed DPI, Spaces/fullscreen apps, HDR/wide gamut, self-exclusion of the actual Riftlet UI, import/upload and subjective latency remain explicitly **NOT_RUN**.

Primary API references: [SCScreenshotManager and screenshot examples](https://developer.apple.com/videos/play/wwdc2023/10136/), [SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter), [sourceRect semantics](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect), [legacy CoreGraphics capture](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage).
