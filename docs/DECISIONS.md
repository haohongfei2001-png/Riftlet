# Riftlet — decision register (2026-10-26)

**Read statuses literally:** USER means the user specified it; CANDIDATE means researched, not approved; OPEN means unresolved; NOT_TESTED means no real-platform success evidence.

| ID | Status | Statement |
| --- | --- | --- |
| P01 | USER | Normal interaction = macOS screenshot once + click screenshot once. No extra shortcut, drag/drop, paste, picker or confirmation. |
| P02 | USER | Extremely small vertical screen-edge spatial rift; coin-scale aspect-ratio-preserved thumb, picture + minimal number. |
| P03 | USER | Earliest capture on top; later captures below; successful item's removal makes lower images move upward. |
| P04 | USER | Confirmed successful upload → swallowed. Explicit failure → reborn. **Never automatically send a message.** |
| P05 | USER | Usually 2–3 screenshots; >10 uncommon, so avoid complex infinite-shelf behavior. |
| P06 | USER | Maximize appropriate code/technology reuse rather than rebuilding known modules. |
| P07 | USER | **Do not begin product development yet.** Design, discuss and evaluate first; previous prototype/development instructions were withdrawn. |
| P08 | USER | The public repo is **Riftlet**. |
| T01 | CANDIDATE | Swift/AppKit native macOS app as primary body. |
| T02 | CANDIDATE | Chrome extension + Native Messaging web adapter; compare native Chrome AppleScript/Javascript if useful. |
| T03 | CANDIDATE | NSPasteboard + Accessibility desktop attachment adapter; exact ready status not proven. |
| T04 | CANDIDATE | Selectively reuse Sukurini, Screenshoss, Tendedero, Oracle and Maccy components, licenses preserved. |
| D01 | OPEN | Physical scale, reveal/occlusion, line material, click hitbox, number location and numbering semantics. |
| D02 | OPEN | Tooltip/hover, in-flight/unknown visual language, 10+ items, fullscreen and multi-display behavior. |
| D03 | OPEN | Whether consumed screenshots remain in archive; hide-queue vs delete semantics. |
| D04 | OPEN | Optional management window and its essential capabilities. |
| E01 | NOT_TESTED | Exact web draft image attachment + positive per-image READY evidence. |
| E02 | NOT_TESTED | New / Classic Mac desktop per-image READY evidence. |
| E03 | NOT_TESTED | End-to-end screenshot capture-to-rift latency and screen capture exclusion on real Mac. |

**Pro's numeric suggestions (48 pt thumb, 1 pt line, >90% exposed) are design starting points, not a user's final choice.**


## 2026-10-27 — formal engineering authorization (append-only phase change)

P07 records the earlier explicit research-only decision. **P09 below now supersedes its phase restriction; P07 remains historical evidence.** No visual approval or upload proof is implied.

| ID | Status | Statement |
| --- | --- | --- |
| P09 | USER | Start formal engineering now: executable plan, native foundations, tests, independent branch and Draft PR. Do not wait for unrelated upload anomaly verification. Do not merge unreviewed changes or modify other projects. |
| P10 | USER | R2 01 «直截» may be the initial adjustable implementation baseline; not final Approved. Rejected round-1 B/C remain excluded; independent logo work does not block engineering. |
| P11 | USER | Separate destination/input/identity/completion/queue boundaries. Unvalidated ATTACHED conditions may not automatically swallow real screenshots. |
| E04 | USER_REPORTED | Chrome Apple Events JavaScript added a synthetic image to actual ChatGPT and produced INPUT/target/image association; ATTACHED candidate exists. Raw current anomaly/READY evidence is not delivered to this branch. |
| E05 | OPEN | Strict READY, real failure, abnormal switching/concurrency and newer Mac client admission remain unproven. The technical ZIP is an earlier research snapshot, not contradictory fresh runtime evidence. |
| I01 | IMPLEMENTATION | SwiftPM/AppKit/Foundation/ImageIO/system SQLite; no external runtime package. Engineering plan and verification record govern this foundation branch. |
| I02 | IMPLEMENTATION | Production completion and retry-safe profile registries are empty. Simulation uses an isolated database and only synthetic assets. |

See [engineering plan](ENGINEERING_PLAN.md) and [adapter contract](ADAPTER_CONTRACT.md).
