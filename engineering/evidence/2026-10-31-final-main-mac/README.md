# Exact final main: bounded Mac acceptance

## Verdict

**Production NO_GO.** This run executes the original final ARM64 App and adds
real local startup/recovery evidence. It does **not** close natural cold-first-click
or selection preservation. Their historical failures remain unresolved; this
version's attachment reproduction is **BLOCKED** by the lack of a confirmed
exclusive, foreground, authorized test draft. No upload was attempted.

No production/UI source was changed. No prior upload, CI, or integration was
repeated. This is an evidence-only branch from actual main, not another product
candidate or permission to merge main.

## Exact product and environment

- Source/checkout/main: `60eaaef64848fc5535580e4fcb65e45f3f41e814`; remote read back twice.
- Native original artifact: `13040592417`, run `41196282486`.
- Original inner `Riftlet-Internal-Beta.zip`: 2,148,600 bytes;
  SHA256 `280a700e35e2431518ca7f053e87a30414059dad7f4634f873828ebb03baf721`.
- Executable SHA256: `f3988e978555b172fc004f42d0e54f7d1ce95e7c61eda791ec30a70ecece3158`.
- All six build-info file digests verified; original ZIP CRC and App deep/strict
  code-signature verification passed. Mach-O arm64; development signature, not
  a notarized public release.
- Actual host: macOS 27.0 (26A428), arm64. Two currently connected displays:
  1920x1080 and 800x1280 logical points, both scale 2; second has negative X/Y.
  Enumeration alone does not prove interaction or mixed-scale acceptance.
- Passive AX, event-posting, screen-recording and each known Chrome PID's AE
  checks returned available. No permission prompt, setting or account was changed.
- Read the committed `docs/R21_UI_FREEZE_AND_MAC_ACCEPTANCE.md` and original
  package instructions/build-info. The separately named
  `Riftlet-60eaaef64848-Codex-acceptance.md` was not available as a local file;
  its recorded Library link timed out in one hidden-browser attempt. It was not
  silently represented as read. That unknown-outcome attempt was not repeated.

The original package's README contains historical PR/Draft/main statements; the
actual user instruction and verified current main govern this run. Original
package bytes were retained unchanged.

## Results

| Case | Status | Executed scope / limit |
|---|---|---|
| Exact original ARM64 package and executable | MAC_PASS | Hash, build identity, architecture and signature checked on this Mac. |
| Ordinary original-App startup | MAC_PASS | Actual normal capture mode, native microimage/number windows, independent camera, page arrow and native menu exposed by AX/WindowServer. No helper substituted. |
| Ordinary disabled upload configuration | MAC_PASS | Original executable's `--ordinary-build-info`: input/start/completion/continuation/safeRetry all false. No input operation appeared. |
| Existing screenshot catch-up | MAC_PASS | 17 existing source files naturally imported; each original byte count/hash matches its private asset. Not 17 new captures or upload attempts. |
| Same-root second instance | MAC_PASS | Second original executable exited with ownership refusal before services; first remained alive. |
| Normal quit and restart | MAC_PASS | Exact owned process quit normally, restarted from original executable and presented native windows. |
| Controlled local crash/recovery | MAC_PASS | SIGKILL of this task's verified exact ordinary-App process, restart, 33 asset rows and zero operation/start/compensation rows exact, SQLite integrity/foreign keys valid. Not an in-flight-upload crash test. |
| Protected data and UNKNOWN preservation | MAC_PASS | Both acceptance roots were not launched: all old database rows, media and journals remained exact. Ordinary old identity/media preserved; expected idle archiving disclosed below. |
| Final-main Native/Feedback/Pages runs | CLOUD_PASS | Existing completed/success runs read back at exact main; no rerun, deployment or claim of new native-to-cloud Feedback delivery. |
| Natural cold first click | BLOCKED | Old owned tab IDs absent; known authorized persistent route absent from bounded metadata-only lookup. Shared foreground changed externally. Zero click/input attempts. Historical failure not closed. |
| Selection preservation/native attachment comparison | BLOCKED | Same prerequisite. No qualified new input; no new collapse root cause, no focus/Range patch. Historical FAIL remains unresolved. |
| New system-shortcut capture -> attach -> start -> swallow -> completion | BLOCKED | No qualified exclusive Chrome draft. Existing accepted evidence is not relabeled as final-main acceptance. |
| Home/local and consecutive uploads/late receipts | NOT_RUN | No Web-mode App or new input launched; existing admission boundaries retained. |
| Real R2.1 appearance, pointer preview, CLEAR/GAP, hold/refill/double-click | NOT_RUN | AX/window presence is not appearance, event-routing or preview-timing proof. |
| New region/window/full-screen capture and cancel | NOT_RUN | Shared foreground was not occupied for screenshot selection; existing imported files are separate evidence. |
| Native Feedback -> D1 -> private Issue | NOT_RUN | No report sent; independent same-deployment observation/cleanup prerequisites not established for this run. |
| Physical mouse/keyboard, VoiceOver, Spaces/full screen, disconnect/reconnect/mixed scales | NOT_RUN | No artificial events or display metadata substituted for these cases. |

## Resource and event evidence

There was no running Riftlet and no other active Riftlet acceptance task when
checked. A separate active task was using its own authorized Chrome test surface.
No coordination message was sent, consistent with the user's standing choice.
We did not close/reload/activate its tab or install page observers there.

One read-only probe of the formerly owned fixed persistent target returned AE
`-1728` in about 111 ms. A bounded ID inventory then confirmed both formerly owned
tabs absent. One subsequent metadata-only route comparison (no foreign page DOM
or body read; excluded the other task's known tab) found no relocated copy of the
previously authorized persistent chat. No repeated missing-tab queries or
ambiguous window creation followed. Tab inventories changed and the frontmost
Chrome PID changed between observations without this task activating Chrome.
This proves resource instability, not attribution to a particular actor.

Ordinary App lifecycle samples retained the existing frontmost Chrome PID at
observed checkpoints. This is **not** a continuous focus/selection-preservation
measurement. Native monotonic observations are retained privately; no unobserved
capture T0, first-click T2 or ACK time was filled in.

## Data preservation and observed lifecycle changes

Read-only SQLite backups plus file-hash inventories preceded execution. No old
queue was reset, restored over, unlocked, or edited by a test script.

- Ordinary root: assets 16 -> 33, operations 0 -> 0, starts 0 -> 0.
  Exactly nine old visible records became archived via the existing
  `automaticArchive` lifecycle (revision 0 -> 1). Only visibility/revision/reason
  changed. Their IDs, image identities, status, files and journals were retained.
  This is not a claim that the entire old database was byte-for-byte unchanged.
- Restricted candidate: assets 18, operations 7, starts 3, all original rows exact.
- Ordinary internal acceptance: assets 6, operations 5, starts 3, all original rows exact.
- All 57 current asset media files match their recorded size/hash. All pre-existing
  media/journal/configuration files remained present and hash-identical. No raw
  original screenshot was changed or removed.
- Feedback sidecars: original draft rows exact; zero report/submission rows in all
  three roots before and after. No Feedback content was sent.
- The controlled crash occurred **after** the catch-up/archive pass; all 33 asset
  rows were exact across that restart. All stores passed SQLite quick/foreign-key checks.
- This task's final App instance exited normally. No Riftlet process was left running.

## Evidence and minimal resumption

Raw AX/window records, process IDs, private paths, source media identities, original
databases, full snapshots and private source hashes remain local. Only aggregate
results and public artifact hashes are committed. `results.json` is the compact
public receipt; `private-evidence-digests.json` binds the bounded raw records without
publishing their contents.

Resume with the same verified original package after an authorized persistent
chat is available in an unoccupied foreground resource. Reuse the existing
selection-causality observer and original native executor; create a **new** system
PNG and operation, preserve a true keyboard selection and stable old attachment,
and choose click timing from visible user conditions rather than waiting for ACK.
For no-pre-event-ACK outcomes, retain safe refusal and the image. For collapse,
record the first event and native-attachment control before changing code.

Do not launch restricted Web observation against another task's frontmost page.
Do not manufacture a new clean root to evade old UNKNOWN. The original default
App stays closed; Home/local requires its separately approved internal build path
and cannot be labeled as this original package's restricted persisted-chat result.

No new product defect has been causally reproduced in this run. There is no
justification for a focus/Range repair or production admission change. Final
ordinary input/start/completion, built-in upload, safe retry and Web continuation
remain closed. First general-product experience/release is **not cleared**.

## Independent review

Non-author `final_acceptance_review` performed a read-only review of the original
artifact, private evidence, preservation differences and all three public files.
Result: **APPROVED for this evidence-only handoff**, no blocking findings. The
review explicitly confirmed 17 catch-up imports/9 automatic archives, privacy
redaction, unresolved cold/selection failures and NO_GO. It is neither a new
product-source approval nor an attachment/production-admission approval.
