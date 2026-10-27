# Round 3 GUI log review — automated/unattributed input only

Reviewed 2026-10-27, read-only input: `/tmp/riftlet-round3-physical-gui.jsonl`. The filename is not evidence of physical input. No GUI/Chrome actions, App launch, build or commit were performed by this reviewer.

## Previous review fixes

All requested changes are present in current source:

- AX application and focused-window objects each receive a 0.05-second messaging timeout; no global timeout is changed. Existing trust is checked with AXIsProcessTrusted(), without a prompt request.
- AX callback verifies its source observer. Remote window refresh is coalesced in a cancellable Task after Task.yield(); stop invalidates the generation and cancels that task. No synchronous focused-window refresh remains on the AX callback stack. Initial bind still performs several bounded synchronous AX calls; 0.05 seconds is per call, not a total startup deadline.
- App acceptance JSON now writes data plus newline together, matching transport trace's whole-line write.
- Envelope reads the exception message once and admits only a closed code enum. Native decode still validates nonce, CFBoolean, exact key set and closed rejection label.

## Actual observations

74 JSONL records parsed successfully. There are 15 mouse-down and 15 mouse-up records, 10 thumbnail_press and 10 thumbnail_selected records. Every accepted press says `source=mouse`, every selected asset is fixture `00000000-0000-4000-8000-000000000001`. There are no accessibility-source presses in this file.

All 15 mouse-down coordinates lie inside the first row's image rectangle in the preceding stable actual-geometry snapshots. Lines 15 and 20 hit the narrow IMAGE named target; other points are still inside the image even though `namedTargets=[]`. No mouse-down lands on CLEAR, GAP, OUTER, NUMBER or HOLD. In particular, CLEAR's point is (-78.5, 880); none of the actual downs are there.

Five down events have clickCount 2 or 3 (lines 39, 51, 53, 70, 72); they produce no additional accepted press or selection. This supports scoped AppKit repeat-click suppression on a stationary row. No replacement/reflow occurred, so it does not cover double-clicking a replacement row.

All ten selections occur while helperActive=false, with another foreground PID. That supports a scoped nonactivation observation for those AppKit events. There are zero key_down/probe_text_changed events, so continued delivery to the intended text field was not measured. `probeEditorFocused=true` is only the helper's retained responder state; it can remain true while Chrome owns focus.

There are zero underlying_probe_down records and zero hold/reorder records. N05 pass-through and N07 held replacement were not exercised. The control window eventually has occlusionVisible=true, isOnActiveSpace=true and isMiniaturized=false; this shows visible-window flags in this run, not the cause of the previous Stage Manager failure.

**Classification:** AppKit mouse route observed; physical-human provenance unverified. The file alone does not distinguish physical mouse from CUA/CGEvent/native automation. Given the current user direction to perform actions ourselves, future automated trials must be labeled automated. Physical N1/N04/N05/N07 remain NOT_RUN. No ChatGPT or transfer success is measured by this synthetic helper.

## Transparent-corner finding and smallest next action

Every stable snapshot predicts the CLEAR point will hit row window 47313. This is a legitimate warning: the row remains a rectangular non-ignoring input window, and its mouseDown handler does not reject clear padding. But this file has no actual CLEAR click. Therefore it does not prove the row actually selected on a transparent corner, and it does not prove cross-window pass-through failed at that point.

Most snapshots predict GAP/OUTER/LINE would hit a different application window (45836), rather than the helper's control/probe window (47310). Under those conditions a missing helper probe event cannot diagnose interception; the probe was not the intended top underlying recipient. Before a N05 automated batch, the integration lead should explicitly present the helper once and verify the intended underlying probe using its actual current geometry. No focus polling or event forwarding is needed.

Minimal sequence: collect actual current row/target geometry; ensure the helper probe is directly beneath; send one authorized automated native click to CLEAR and one control click to GAP; inspect original NSEvent route, actual probe down and selection delta. Label automated. If CLEAR reaches the row and selects, the code-level trigger is whole-bounds acceptance, not the visual alpha. A small image/number-region rejection can prevent an unintended selection but still does NOT prove forwarding to the underlying window. True rectangular holes would require separate tightly bounded input windows around the approved hit regions; that is a separately reviewed geometry change, not justified by this log alone. No private API, event reposting, pointer polling, hitTest(nil)-as-proof, or speculative split-window rewrite is proposed now.

## Only helper diagnostics changed during this review

`Sources/RiftletGUIAcceptance/AcceptanceMain.swift` adds:

- `rowRegion` and `rowAssetID` from actual row geometry, with explicit transition flag, so an empty narrow-target match is not misread as an unknown location. Region means rectangle, not pixel-alpha classification.
- `probeKeyInputEligible`, which requires the active helper, key control window and actual editor responder; existing responder-only field remains for compatibility.
- `predictedUnderlyingWindow` and `underlyingProbePredicted` per marker. These remain predictions, not PASS evidence.

No Core/App/adapter/UI behavior, geometry, transparency, forwarding or focus control changed. `git diff --check` passes. Build and live validation remain with the lead; this reviewer did not repeat either.
