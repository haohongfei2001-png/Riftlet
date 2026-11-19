# Additional independent review: untagged mouse diagnostics

Reviewed 2026-11-15 by `/root/final_diag_review`; non-author, read-only source inspection. Result: **NO BLOCKING FINDINGS** in the three additional working files `RiftletMain.swift`, `RiftPanelController.swift` and `RiftInputIslandTests.swift`. Exact hashes and independent probe results are in `mouse-diagnostics-review.json`.

This review supplements `independent-review.md`: Main and panel are now changed only by this additional instrumentation patch. The earlier five-file snapshot remains historical and is not a claim that the expanded working tree leaves those files unchanged.

- The change removes the requirement for a positive custom tag before reporting App-level or row-level delivery. Missing, zero, negative and out-of-range tags remain absent; no fallback tag is assigned. Row identity still comes from the existing bound row closure, with actual NSEvent window/event values.
- The local monitor returns the same event, and the row observer does not select or deliver an event. `onDown`, selection gates, press/freeze behavior, release handling and `recordSelection` have no semantic changes. Independent byte comparison confirms the complete `onDown` and `recordSelection` blocks are unchanged.
- Opt-in remains the existing AcceptanceHitMap requirement: development or isolated-product-acceptance build plus both `--acceptance-trace` and `--acceptance-hit-map`. The panel defaults to `readsAcceptanceMouseTag == false`; an observer alone remains insufficient. No new global event monitor, system permission or production logging path is introduced.
- The existing bounded diagnostic sink still receives only scalar event metadata and digestible asset identities. There are no coordinates, key contents, draft contents or extra account data in these new records.
- The strict sender/product receipt matcher is byte-identical. Independent pure-Python probes show all six missing/invalid/wrong-tag cases are still refused; extra untagged diagnostic boundaries cannot supply or alter a valid tagged selection/refusal receipt.
- The modified test retains opt-in-off, geometry refusal and double-click gate assertions. The added AppKit test checks two distinct asset receipts through `NSWindow.sendEvent`, queue feedback and refresh, including nil tags, original window/event IDs and selection order. It is direct AppKit callback coverage, not WindowServer routing or physical click proof.

`git diff --check` passed. This reviewer did not run new XCTest or GUI/native delivery tests; source review and pure-Python probes do not substitute for those results. Final build and hosted XCTest checks remain the integration lead's responsibility.

This fixes a diagnostic visibility blind spot: previously a delivered untagged event could be omitted from the trace. It does **not** establish why any earlier external click lacked a matched receipt, and must not be reported as a repair or successful acceptance of the original second-thumbnail delivery failure. Complete source G SHA review is still pending.
