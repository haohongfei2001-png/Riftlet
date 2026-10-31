# R2.1 native microimages — independent integration handoff

Implementation source: `1e834902794048942f112aee98bc5fcec5566930`; formal parent retained: `253ac8db92bfba9083d485b71b84c594223da217`. Draft PR #24 is independent of formal PR #1. No release or production admission is granted here.

## Product delta

- Three free-edge contours, neutral number surface, fixed seam contact, shared clipping plane for the image and light shadows. Zero occlusion uses a closed perimeter; narrow exposed slices suppress the contact band. Left geometry mirrors ornaments, never source pixels. Press feedback no longer translates the image or its input islands.
- Continuous preview: 450 ms cold dwell, 90 ms warm dwell, fixed current-page canvas, atomic image/UUID/rank update, session/request/revision fences, one active decode and one replaceable pending request. Same-ID grace preserves eligibility; stale callbacks and fade tasks cannot restore old pixels or hide a renewed preview.
- A new screenshot outside the current page no longer cancels its stable preview. Actual visible identity/geometry changes still cancel it.
- Strict upload-start still owns swallow eligibility; only the visual displacement was changed to cover the complete exposed width. Magnetic arrival keeps original geometry validation, lifetime and interruption guards.

## Two reviewable implementation commits

1. `37c2fafafdfc0e349f796f5bdee4e1cf5c214779`: native appearance, visual fixture capture, unchanged input islands.
2. `4e28f36073c0d7103a0fb2b8cca819d676fdcfd1`: bounded continuous preview and deterministic regressions.

`be7106e431f9a00688090b8b97f1efcec0018df1` retains the formal test correction unchanged and preserves both parents; `bb5c9f7011fb1db30a16a8d0b6564b5be929e3c8` fixes noncurrent-page arrival cancellation. Integrate the reviewed branch delta against current formal source; do not blindly reapply already-present formal commits.

## Scope and design decisions

Original ZIP, final JSON, 20-page PDF, interactive prototype source and handoff were read; original hashes are in `design-inputs.json`. Current final JSON/handoff supersede the package's historical `8b70cb0` source audit and approximate CSS blur. AppKit shadow radii use the explicit native initial values. No old R2 implementation is reapplied.

The original design assumes ordinary number bounds of at least 10×16 pt; integrated R2 actually permits a smaller frame. The existing frame/hit region is preserved. The new neutral surface is painted inside it; no extra mouse-receiving area is introduced. Native window evidence must be consulted before declaring pixel-perfect parity.

Core, adapters, Capture, App composition, Feedback, database, preferences, source/retry/continuation admission and original files are byte-identical to the formal parent. No user database or browser was opened. Only fixed, original design-package synthetic images are checked in as visual fixtures.

## Validation boundary

Local ARM release/UI/helper compilation and development App packaging passed. Local Command Line Tools cannot execute XCTest; cloud native jobs are authoritative for tests. The local App is ad-hoc, unnotarized and has not been launched into the shared desktop.

Non-author source review: PASS after resolving findings, including the final arrival-preservation regression. Native images, movies and runner test outcomes are recorded separately below. The exact formal source-admission gate intentionally remains unchanged and rejects this new source until the sole formal integration owner independently reviews and admits the composed tree.

Physical mouse, mixed-DPI multi-monitor transitions, real Chrome/upload, and final combined-App human visual approval are NOT_RUN. Synthetic strict-start projection is animation evidence, never upload proof. This task does not repeat or relabel prior real attachments.

## First native run and targeted correction

Run `41183490795` at `bb5c9f7` found invalid negative contour handling and implementation-coupled regression assertions. `CGRect.width` normalizes a negative size: the geometry guards now explicitly inspect `size.width/height`. Swallow tests now measure content coordinates through its actual moving parent; Reduce Motion follows the real animation owner and retains zero-sample, duration and phase checks. Press is intentionally stationary under R2.1. The new input test compares actual native unpadded R2 windows with padded R2.1 windows, including normalized input frames, at scalar tolerance 1e-9 rather than relaxing half-point failures. A hidden-window control confirmed that AppKit normalizes both configurations equivalently. No visible local test window was presented.

These corrections are `1e834902794048942f112aee98bc5fcec5566930`. The inherited formal test file remains byte-identical to the formal parent. Source review PASS was repeated on this exact SHA. Native outcomes below supersede only affected test failures; the first run remains retained.

## Native visual inspection

Non-author review of the original ARM WindowServer 1× outputs, followed by bounded Intel 1× checks of right90/left25/preview/final refill: **limited PASS**, no visible integration blocker found. Left/right 0%, 25% and 90% occlusion retain source orientation and proportions; neutral numbers remain present; transparent fixtures show a display-only checker; preview shows the full image clear of the input islands. Synthetic strict-start frames retain the image before the projected start, then remove its content, number and ornaments before safe refill. No residual frame/shadow was observed in sampled frames.

Original PNGs, variable-cadence movie, frame times and checksums are under `native-arm64/` and `native-x86_64/`; every frame checksum was read back and verified. These are actual WindowServer-owned synthetic product windows, not HTML renders, user screenshots, uploaded attachments or physical input. The movie does not sample every frame of the 120 ms transition and is not a latency benchmark. Pixel-for-pixel CSS/AppKit shadow equivalence is not asserted.

### Remaining final combined-App acceptance

- Real 2×/mixed-scale monitor transitions and final physical desktop appearance; current CI native output is 1×.
- Physical IMAGE/NUMBER/CLEAR/GAP routing, focus preservation and continuous clicking on the integrated App; this branch verifies input geometry and native callbacks, not a human mouse.
- A recorded warm-preview A→B→A sequence under real pointer movement. Deterministic AppKit tests cover 450/90 ms eligibility, fixed canvas, atomic identity and late decode cancellation; the captured preview is static.
- Formal combined App's true upload-start/complete flow and magnetic arrival. This visual increment preserves the source boundaries and tests synthetic lifecycle projections; it does not replace P0 real-upload acceptance.

## Integration instructions

The sole formal owner should review this branch against its then-current HEAD, preserve both the R2 source and formal timing correction, and apply only the R2.1 delta. The two principal commits remain separately reviewable; include their necessary follow-ups. No shared Core contract or App composition change is required. Keep original product-admission registries unchanged. Update the exact composition source pin only through the existing independent formal review process, then run combined ARM/Intel/Feedback CI on that exact composed source. This branch deliberately cannot satisfy the old exact-source pin and must not be described as a fully green formal workflow.

The helper, six fixed design fixtures, capture script and one existing native-workflow step are acceptance-only. They do not install an adapter, open a database or touch Chrome. Final visuals are implementation candidates until the designated visual acceptance; no new user settings or upload modes are added.

## Exact CI and artifact results

Tested source `1e834902794048942f112aee98bc5fcec5566930`, GitHub test-merge checkout `e3dee8ae81dff89762f4ee513e3c93cf3723a261` (same product tree).

| Check | Result | Exact run/job |
|---|---|---|
| ARM native tests, release build, packaging, WindowServer evidence and system accessibility variants | PASS | Native `41183924489`, job `124486831925` |
| Intel native tests, release build, packaging, WindowServer evidence and system accessibility variants | PASS | Native `41183924489`, job `124486832013` |
| Feedback regression | PASS | Feedback `41183924475`, job `124486831808` |
| Exact formal source-admission gate | FAIL / intentionally not repinned | Native job `124486831784`; Feedback job `124486831974` |
| Non-author source review and limited ARM/Intel native visual review | Limited PASS | exact source above; scope and exclusions above |

The overall workflows are **not green** because the exact formal source gate rejects the new independent increment. No test/build failure is being waived. The formal owner must review the final combined tree and update its composition gate before claiming formal CI success.

- [Native run and both architecture artifacts](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41183924489)
- [Feedback regression run](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41183924475)
- [Independent Draft PR #24](https://github.com/haohongfei2001-png/Riftlet/pull/24)

`ci-results.json` records immutable artifact IDs and ZIP hashes. The local compiled ARM App has the separate hash in `local-package.json`; cloud archives contain their actual architecture's development App/internal Beta. They are not notarized or publicly released. This handoff-only successor changes evidence, not the tested source tree; it is not a new test execution.
