# Decisions

- Preserve accepted Beta `personal-beta.1+004741f`; engineering builds remain separate and uninstalled.
- Preserve v1 prototype and all failed evidence; revision 2 has its own files, hashes and runs. No visual AppKit integration until design approval.
- Share one main-based engineering worktree with exclusive path ownership. Root owns integration, shared source/Package/CI and refs; contributors do not commit concurrently.
- Storage backup must prove quiescence/consistency; a live filesystem copy is not a verified backup. Restore only to a separate empty destination.
- Release preparation may be tested offline, but Developer ID, notarization and Gatekeeper acceptance require actual credentials/artifacts and remain separate.
- No automatic data deletion, remote upload, auto-update feed or new attachment permission gates.

- Native tests on this Mac cannot import XCTest; preserve both failures and execute complete suite in existing CI. Actual Core/Capture and ownership code are independently compiled into isolated CLI probes; no test replacement or changed passing criteria.
- Full Chrome headless is required for cross-tab focus fixtures; headless-shell failure is preserved and differentiated from product behavior.
- Performance labels were independently reviewed: corrected batch measurement begins before generation/start; old shorter settle measurements remain explicit. CPU uses process cumulative samples and only interval differences for derived usage.
- Consumer support text now acknowledges accepted Beta scope and actual image-format fallback without changing input code. Historical README is preserved byte-for-byte.

- Appearance uses its strict versioned app-owned file and prepare → atomic save → apply sequence; a failed save preserves the effective choice and exact retry target. System mode clears only the App's override. No startup write or system-theme change.
- Launch-at-login status comes only from SMAppService.mainApp. Explicit commands read status before/after a single register or awaited unregister; requiresApproval is separate from enabled. No local enabled Bool, LaunchAgent, automatic retry or system-setting mutation in tests.
- Settings state/adapters and the two App owners are deliberately unconnected to existing Main/views. This is testable nonvisual implementation, not the final native visual design. Existing owners retain their actual asynchronous persistence and capture behavior.
- Final exact G/H review, five formal CI checks and artifact verification are one integration lane; source records must not claim later CI results. The Draft PR delivery record binds those post-commit outcomes.
