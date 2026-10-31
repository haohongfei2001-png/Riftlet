# Quiet Edge R2 independent native implementation

Baseline: formal Draft PR #1 `2bddb61a19114167b7485c392600c4b91dc62725`, read from GitHub. The design package's older edbdc7aa pin is historical. Independent branch codex/riftlet-quiet-edge-r2-20261031. No formal ref, main, website, admission or user data changed.

## Design and scope

The R2 JSON, 24-page PDF, prototype source and current boards were reviewed. DESIGN-SPEC.json is retained verbatim with hashes in design-provenance.json. Historical design-only scope is superseded by current implementation authorization. R1 is not implemented. HTML 46/33 results are not native tests.

Fresh defaults:25% occlusion,6pt inset,3 visible,primary left-middle. Capacity does not cap collection. Persisted legacy scalars and absolute position remain until an explicit six-position choice. UUID selection, session fallback and explicit reconnect restoration preserve user intent.

Native AppKit fields/sliders and six-position controls, capacity-based geometry, separate vertical arrow input panels, actual-image slit bounds, complete hover preview, guarded original-view fit/100%logical/200% zoom and side-aware magnet geometry are implemented. Image pixels are never mirrored.

Folded36pt camera and expanded132pt rail clamp independently and avoid image/number/arrow inputs without moving the queue. Entry initialization no longer rewrites queue preferences; capture import no longer calls showLatest. Fixed mode order/cancel semantics remain.

Identity-anchor pagination and press protection retain original UUID. Strict durable uploadStarted still triggers swallow. Empty slots compact only after pointer exit350ms, native double-click interval and no protected interaction. Old pending records cannot resurrect consumed items; later independent starts/removals still hide their own rows. Detail view protects archive/refill. Core/Adapters/Capture/Feedback transport/SQLite/admissions are unchanged.

## Verification

Local release product/UI builds, bundle/signature verification, helper self-check and36 native configuration roundtrips passed during development. Final exact-source CI results will be recorded separately. No local GUI/browser or user database was opened. Physical mouse, real VoiceOver, disconnect/reconnect/scaling, Spaces/fullscreen and screenshot-to-ChatGPT on the final combined App remain NOT_RUN.

Regression source covers range matrix, six positions, negative coordinates, capacity boundaries, legacy migration, UUID fallback, vertical paging, camera collisions, held configuration updates, independent upload starts during tombstones, hide/new-arrival/show, actual left magnet mask and original preview. Existing ARM/Intel CI runs XCTest and actual synthetic AppKit original-pixel captures on isolated runners. R2 captures reuse the existing helper. They do not certify physical/P0 acceptance.

Independent review identified and resolved folded-camera clamp coupling, stale pending geometry, pending-page resurrection, later start/removal suppression, hide snapshot rollback, actual left-layer mask and detail/archive fence issues. No production gate was weakened. The exact formal source gate must be independently repinned by the sole integrator; native job success alone does not authorize release.

## Integration

Take reviewed source changes on the latest formal branch. Main edits only wire configuration and original preview: preserve concurrent reliability changes rather than overwriting Main. This branch does not import other research branches or change ordinary upload/safe-retry/continuation admission. Formal PR1/PR15/main remain untouched. Draft PR, exact source/CI/artifact references follow in final handoff. No public release or founder Beta participation.
