# Build 61 read-only QA window inspection

The exclusive GUI operator can inspect a previously enrolled signed Chrome or Edge window with the following commands. Use a private output destination. The JSON includes private QA browser and WindowServer handles.

```sh
sh build-window-inspector.sh /path/to/frozen/Riftlet /path/to/instrumented/Products/Debug /private/path/window-inspector
/private/path/window-inspector controls
/private/path/window-inspector diagnose /private/path/to/qa/suite/signed61/edge edge
/private/path/window-inspector receipt-only /private/path/to/qa/suite/signed61/edge edge
```

The build uses the checkout’s existing QA identity, read and descriptor helpers and the instrumented RiftletAdapters and RiftletCore modules. The inspector entry point offers only these three modes. `controls` uses synthetic CGRect and WindowServer dictionaries. `receipt-only` reads already-written, owner-scoped files. `diagnose` calls public read-only macOS APIs and sends typed, noninteractive Apple Event get-data requests only to the authenticated enrolled window. It requires the expected build-61 artifact manifest, the original pre-creation snapshot, signed QA challenge and existing navigation/entry receipts. Neither this tool nor its output grants a product input.

## Reading a snapshot

| JSON object | Meaning |
| --- | --- |
| `process` | Vendor code signature, registered bundle, PID, kernel birth, active/hidden state and activation policy of the enrolled browser. |
| `session` | Current console and caller/browser UID comparisons. The audit-session comparison is present only after both unprivileged OS queries succeed. A denied query preserves its errno and an unknown audit-session result. |
| `enrolledBrowser` | The original browser scripting window and tab identifiers, one-window-scoped tab membership/selection, native QuickDraw top-left bounds, visible and minimized flags. Missing Apple Events authorization or an unavailable property leaves fields unknown. |
| `accessibility` | One entry per AX window of the signed browser. Includes observed role, subrole, point bounds and minimized, focused, main and modal states, with per-property AX statuses. Identifiers, when provided, are represented by a per-snapshot keyed token. The documented AX window API does not supply a direct CGWindowNumber. Same-bounds candidates remain explicitly distinct from a shared handle. |
| `windowServer` | All and separately on-screen surfaces for the exact PID. Each owned row supplies the CGWindowNumber, layer, Quartz bounds, opacity, ordered-on-screen metadata and bounds differences from the enrolled native window. A unique, correctly sized layer-zero window and the first positive-alpha rectangle at its center have separate results. Overlapping rectangles can include transparent or input-transparent regions. |
| `displays` | AppKit frames and visible frames in points, primary-display-based Quartz conversions and the independent CGDisplayBounds for each display. The tool reports whether each conversion agrees. The usable rectangle excludes menu bar and Dock areas as reported by AppKit. |
| `recordedPresentationActions` | Prior presentation intent/result pairs of the unique enrolled family and exact active scope. A missing result remains unknown. Existing NS activation return, AXRaise result, AE return and later foreground samples have separate fields. A previously recorded generic error code cannot establish an OSStatus. |

The browser's Apple Event window ID is in Chromium's scripting namespace. The WindowServer window number addresses a compositor surface. An AX window identifies an accessibility object. Compare signed PID and birth, geometry, unique candidates and original-window membership before interpreting a cross-API relationship. Directly comparing integers from the two namespaces proves nothing.

Use the primary display’s AppKit top edge as the common reference for every display. AppKit uses a bottom-left origin. AX position and the Quartz window list use a top-left coordinate system in logical points. Do not multiply window coordinates by Retina scale. The offline controls cover displays above, below and left of the primary screen, local overlap, transparent rectangles, ambiguity and read failures. The result does not enumerate Spaces or report Stage Manager membership. [Apple AX position](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute) · [Apple CG window bounds](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds) · [Apple visible frame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)

The snapshot reads metadata at multiple times and records the native bounds and kernel birth again at the end. AX roles, window frames and rectangles can change between reads. No window title, document title, notification text, personal tab location, screenshot or page body is requested. The .get-data requests address the already enrolled browser window’s known properties.
