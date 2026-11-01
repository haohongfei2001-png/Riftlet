# Post-PR28 daily-use acceptance — 2026-11-01

Tested source: `d24241c4246415d4899b9ca27a8804a0d97a9eb3`.
No production source, admission, settings, permission or database repair changes.

## Exact package and scope

Original ARM64 artifact 13058407423 from existing successful Native run
41242945750, artifact SHA256
`814e506b8032ca5ab89b324e5f5bc131df33a3471d2aed79296e0fd950efe57c`.
The package checkoutSHA and all manifest file hashes matched; strict deep
codesign verification passed. Existing Feedback run 41242945716 succeeded.
Neither CI was rerun. The original binary ran with
`--system-screenshot-candidate --acceptance-trace`; ordinary production was not
opened. The exact owned process was normally terminated after this trial.

## Results

| Scenario | Result | Evidence and limit |
|---|---|---|
| Normal macOS region shortcut, software input | MAC_PASS, limited | CGEvent Command-Shift-4, fully released modifiers, down/drag/up in an owned synthetic Preview window produced a genuine system selection PNG. No CLI capture. |
| File immediately available within 15 s | FAIL | Initial bounded watcher saw no file. Subsequent file birth was about 61.33 s after mouseUp. This supersedes the initial conclusion that no screenshot was generated. |
| Capture-complete T0 / first-readable T1 | NOT_RUN | MouseUp and file birth metadata are known; neither exact capture-completion nor first readability was directly measured. Delay cause remains undetermined. |
| System window-mode control | NOT_RUN | Pointer did not match planned position, so guard refused before shortcut dispatch. No actor or cause attributed. |
| Private import | MAC_PASS, limited | Original/private SHA256 and byte count match; no prior candidate hash match; new asset pending with no active operation. App started after file birth, so this proves startup import, not live watcher latency. |
| New microimage presentation | MAC_PASS, limited | Existing Show Latest AX menu action revealed the final group. AX reported screenshot buttons 13/14; both disabled at observation. No screenshot button pressed. Does not prove first-click readiness. |
| New first click / upload start / completion | BLOCKED | No newly authorized persistent draft independent of preserved UNKNOWN was available. Old authorized draft is locked by its original unknown operation. No database/root workaround or input attempted. |
| Physical click / no-ACK natural first click | NOT_RUN | No physical input or attachment click in this trial. |
| Unfocused + text + noncollapsed selection + old attachment; continuous attachment | BLOCKED | Requires the independent authorized draft; previous success is not reused as this result. |
| Historical data | MAC_PASS, limited | All 13 operation identities/targets/attempts/phases preserved; all 31 old media hashes match. Four UNKNOWN remain UNKNOWN. Eight upload-start rows unchanged. |

## New screenshot identity and timing

PNG 702×494, 1,196,056 bytes, SHA256
`2203c472395612d56bb7cd126b3eb26ec0f4eb9ae37c03ff18ae120c28ef7f64`.
macOS metadata: isScreenCapture=1, type=selection; capture rectangle matches
this trial's controlled drag (inclusive endpoint adds one logical point).
Visual inspection found only newly generated colored noise, no private content.
System original and private copy are retained, not committed.

All event values below are same-boot system uptime seconds:

- Trial start: 870308.28684575; Riftlet was not running.
- mouseDown: 870309.192083541.
- Before release, the actual selection windows were observed: 870309.903554958.
- mouseUp: 870309.903757416.
- Initial watcher end: 870324.984296875; no complete PNG yet observed.
- File birth wall time: 2026-11-01T06:34:54.949401Z. A subsequent simultaneous
  wall/uptime pair estimates birth about 61.33 s after mouseUp; not an exact
  monotonic T1 observation.
- App committed-visible observation upper bound: 870600.3883909584;
  exactCommitMeasured=false. This is persistent state observation, not T2.
- WindowServer/AX read: 870999.3287212917 initially showed old first group.
  Explicit Show Latest navigated to final group; new arrivals did not auto-page.

The old driver required a very high screenshot layer before down/drag and could
cancel before the layer appeared. This private test driver instead guarded the
entire drag inside the exact owned safe window. It did not infer readiness from
touchshield layer 1498. The system high-layer selection window appeared during
the gesture. This is a bounded diagnostic improvement, not a product patch.

## Preservation and resumption

SQLite before/after: assets 31→34 (three backlog imports, only the identified new
noise screenshot inspected); operations 13→13; checkpoints 63→63;
upload_starts 8→8; compensation rows 0→0. Normal read-only reconciliation changed
four updated_at values and one receipt_json; the database is not byte-identical.
No old operation identity or phase changed, no new operation exists.
The old 2400×2064 scaled-preview sample remains UNKNOWN and was not reinput or
inferred complete. Other backlog screenshots were not inspected or uploaded.

Resume with one newly user-authorized dedicated persistent test chat; reuse this
pending new screenshot, not any historical image. No further screenshot is
needed. Recheck foreground ownership and full target identity; decide click
from visible conditions, not by waiting for armed=true. Record actual ACK
ordering and software/physical provenance. Stop on ambiguous input; no replay.

Production decision: **NO-GO**. System shortcut generation is now demonstrated
once through software routing, with a material unexplained save delay. First
natural attachment, physical input and combined draft preservation remain
unproved. Intel's historical first-run animation timeout remains an unresolved
risk; its later same-source passing run is not a diagnosed fix.

Independent non-author evidence review: PASS within the scope above. Private
review hash is recorded in private-evidence-hashes.json; this is not new
production admission or a substitute for the blocked attachment test.
