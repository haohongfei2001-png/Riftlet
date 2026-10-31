# R2 integration boundary

Independent Draft PR: https://github.com/haohongfei2001-png/Riftlet/pull/23

Base: 2bddb61a19114167b7485c392600c4b91dc62725. Production source is the cumulative difference through 057a0071791d654ecfe2b7840cf86904dd600df8. Commits17ea015,01580d8,69d7dc5,057a007 form one reviewed increment; later fixes are required, not optional patches.

Only the formal integrator should combine this with any successor reliability work. Review Main's small configuration/original-preview hooks against concurrent edits; do not overwrite Main with this branch. Keep the protected Core, Capture, Adapters and Feedback trees and existing admission registries. This increment does not choose upload targets or produce receipts.

## Product edits

- UI configuration, six-position/display intent and session fallback; persisted old absolute geometry remains legacy until explicit choice.
- Native layout, actual input islands, vertical paging, UUID/revision-safe pending updates and refill, independent camera placement.
- History verified original preview and geometry-stable footer/scroll canvas; separate context-menu/AX original action.
- Left/right motion plan and actual layer mask. Arrival preferences and upload-start swallow remain separate.
- App hooks persist explicit preferences and route verified original records; capture import does not auto-page or rewrite queue layout.

The GUI helper, new capture script and the branch-specific eight-line CI capture step are acceptance tooling. They need not be wholesale imported into product wiring. Tests accompanying the source are necessary to retain the new boundary checks.

## Composition and release

The existing fixed formal source gate intentionally rejects new R2 paths/objects. It still executes immutable inherited audits. Do not remove the gate or relabel its failure as success: the formal owner must independently review the exact combined tree and update the reviewed source manifest using the repository's normal process. Run final combined ARM/Intel and Feedback CI after integration.

The local development App is ad-hoc signed and not notarized. No installer, public release, first-launch permission mutation or live upload admission is performed here. Final real-Mac/Chrome P0 evidence remains a separate requirement.

## Native acceptance boundaries

Automated coverage uses actual Swift/AppKit control/view/window code with isolated synthetic records. Geometry matrices, persisted migration, callbacks, press identity, original loader and animation cancellation are not claims of human physical input. CI-owned WindowServer PNGs/movies are actual native renders, not the HTML design prototype.

NOT_RUN in this increment: human physical mouse/keyboard, VoiceOver spoken navigation, real multi-display disconnect/reconnect/mixed Retina topology, actual Spaces/fullscreen transitions, and final combined-App screenshot-to-ChatGPT. The shared local desktop, browser, old UNKNOWN and user data were not used. Sole formal lead coordinates these remaining environment checks after integration; founder Beta participation was not requested.
