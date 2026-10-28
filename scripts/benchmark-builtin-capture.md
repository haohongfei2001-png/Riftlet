# Built-in capture measurement probe

This standalone macOS 13+ tool compares the existing `/usr/sbin/screencapture` path with public screenshot APIs. It is **not a replacement production backend**, a physical acceptance test or an upload test.

```sh
swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" scripts/benchmark-builtin-capture.swift -o /tmp/riftlet-capture-benchmark
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

The CLI defaults to `--cli-output-layout hidden-parent`: an ordinary PNG basename in a fresh hidden mode-0700 staging directory, precreated with mode 0600. This matches the production write layout that keeps application-owned originals out of the independent nonrecursive system collector. Only that exact URL is validated and read; output at a different name is a failed sample. Diagnostic alternatives `regular-leaf` and `hidden-leaf` exist only to reproduce output-path behavior. The report includes the layout, child exit status, failure stage and a metadata-only inventory of that call's owned directory, without names or paths. The tool deletes only its own temporary files. No raw images, source paths, arbitrary window titles, application names, device serials or localized error text are printed. Existing screenshots and Riftlet data are never read or modified.

The earlier hidden-leaf candidate was rejected by actual macOS capture: the CLI exited 0 but its exact output was missing. Intel run [40758912572](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40758912572) captured all three window/region variants with a hidden parent and ordinary leaf; the arm64 fixture was occluded and those layout tests were NOT_RUN. This does not establish full-display, Retina, or production publication behavior. The production engine additionally publishes the file without replacement using directory descriptors and `linkat`; that path is covered by process regressions and the separate opt-in `BuiltInCaptureNativeProbeTests`.

## Reading the measurements

`captureMS` has different native boundaries: CLI launch through process exit includes PNG encoding and disk output; SCScreenshotManager/Quartz measure API call through returned CGImage. `pngStageMS` is CLI file read or API-image PNG encoding. `readyToInspectPNGMS` is the closer end-to-end comparison, including permission/fixture checks and these stages, **before** metadata inspection and optional preview creation. It is still not click-to-thumbnail or Riftlet import latency.

Each variant labels its first call in the existing process and later warm calls. The process may have used a different variant/backend earlier, so this is **not a cold OS cache benchmark**. Failed first calls are not replaced by later successful calls in first-call summaries. `sckEnumerationMS` is reported separately. Repeat the whole process for startup distributions; do not infer p95 or a winner from five samples.

Memory readings include process RSS, Darwin process-lifetime peak RSS and cumulative child-process peak information. These are **not isolated per-backend peaks**. PNG inspection adds a bounded sRGB decode; it is separate from production processing and from capture memory. There is a 64-million-pixel decoded-image ceiling.

A child screenshot command has a 20-second limit followed by termination of that owned child. The whole probe has a 90-second process watchdog because ScreenCaptureKit cancellation is not assumed to bound a hung framework callback. Timeout reports **INCOMPLETE_TIMEOUT** and exits 3; it does not label an incomplete run successful. Some already validated sanitized previews may remain after that timeout. Individual sample errors are recorded without raw framework error text.

`--self-check` runs PNG/metadata, coordinate formatting, median, full-pixel preview allowlist and contamination rejection using memory-only synthetic bitmaps. It does not initialize NSApplication, check/request TCC or capture a display. macOS CI's successful self-check means **software-only PASS**. Only individual samples with `status: CAPTURED` establish actual API measurements. Exit code 0, a successful CI step, or `COMPLETED_MEASUREMENT_PROBE` alone does not: all attempted samples may have been safely refused. Read `capturedSampleCount`, `errorSampleCount`, the per-variant summaries and sample reasons. Visibility rejection diagnostics contain only the tool's own fixture geometry; foreign-window overlap is reported as a generic veto without foreign metadata. The CI additionally runs `verify-capture-probe-outcome.py`: an actual CLI output error fails the job; an unavailable fixture remains NOT_RUN, and valid PNGs grant only PASS_FILE_OUTPUT_ONLY. This gate does not turn canary matches into full-image fidelity acceptance. Physical mouse/drag, permission refusal/revocation/recovery, multi-monitor mixed DPI, Spaces/fullscreen apps, HDR/wide gamut, self-exclusion of the actual Riftlet UI, import/upload and subjective latency remain explicitly **NOT_RUN** for this standalone tool.

Primary API references: [SCScreenshotManager and screenshot examples](https://developer.apple.com/videos/play/wwdc2023/10136/), [SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter), [sourceRect semantics](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect), [legacy CoreGraphics capture](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage).
