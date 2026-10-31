# User-ready session and new system screenshot: bounded real-Mac attempt

Product source remains `60eaaef64848fc5535580e4fcb65e45f3f41e814`.
The original ARM64 package was retained; no rebuild, CI rerun or product edit.
This addendum supersedes the earlier Home-only environment blocker: the user did
provide a visible persisted test chat. It does not supersede historical FAILs.

## New verified facts

- At host uptime 808078.846925708, the exact bound normal Chrome receiver was
  foreground, with the authorized window first and test tab active. Page readback
  at 808078.861510250 confirmed visible/focused zh-CN, one empty editor, a form,
  four file inputs and zero attachment images; persisted route, not Home.
  This is structural qualification, **not a complete product ACK**. Existing
  candidate operations did not reference this new test route.
- Three bounded software system-capture controls produced no new file: area
  drag with delayed selection layer, readiness-gated area selection canceled
  before drag, and window-selection control refused before capture. Their raw
  CGEvent/WindowServer records are retained; no watcher defect is inferred.
- After the single requested hardware screenshot action and user reply, exactly
  one new system PNG was found. It is 1,195,991 bytes, 702 × 494, noninterlaced
  RGBA8. Actual macOS screenshot metadata is present. Local visual inspection
  found only the controlled colored test content. SHA-256:
  `414eb83b018cfe91c7645d93ea6eb10be0388c5f7c48de918847ef193203beb4`.
  Exact hardware T0 is unobserved. This original is preserved, never uploaded,
  and has not yet been imported into the candidate queue.

## First blocking stage after capture

The existing native executor was prepared to create a real keyboard selection,
launch the original candidate and click the new visible image once without an
ACK-based wait. None of those stages ran. Native activation and target recheck
failed **before keyboard input, observer installation or App launch**:

| Host uptime | Observed event |
|---|---|
| 808575.9146 | Foreground qualification refused before preparation. |
| 808702.5434237 | Window return did not retain Chrome foreground; guard refused. |
| 808777.0683983 | App activation, AE activation and AX frontmost returned success. |
| before 808777.569554708 | Exact original window reference returned AE -1728; private helper terminated before input. |
| 808824.3005 | Original Chrome receiver no longer existed; process identity check refused. |

Read-only peer-task review then confirmed a concurrent, separately authorized
normal quit of that same Chrome process, profile backup/extension update, and
launch of the same profile for the other task's acceptance. Process inventory
confirmed the replacement receiver. Thus the required stable exclusive test
resource was not available. The precise quit time relative to each activation
call is not recorded; this is not evidence of a Riftlet focus defect or Chrome
crash. No other task was messaged, interrupted, or taken over. The separate
job-application profile was not operated.

## Results

| Item | Status and scope |
|---|---|
| New real system PNG, format, metadata and safe content | MAC_PASS; hardware action requested and resulting file verified; exact T0 NOT_RUN |
| Authorized persisted page structural qualification | MAC_PASS at recorded checkpoint; no complete ACK claimed |
| Natural cold first-click / selection retention | BLOCKED before selection preparation and before first click by receiver lifecycle conflict |
| New input / uploadStarted / swallow / final completion | NOT_RUN, zero new operations |
| Physical thumbnail click | NOT_RUN |
| Historical selection and cold-click FAILs | Remain unresolved; not replaced by a new FAIL or PASS |
| Data preservation | MAC_PASS: all candidate tables exactly equal before/after; 18 assets, 7 operations, 3 starts; all 36 protected media/journal files hash-identical |
| Production admission | NO_GO unchanged; production, continuation and retry remain closed |

The one-shot trial sentinel, App PID file and original-click log do not exist;
no Riftlet process is running. The screenshot hash remains unchanged. No old
UNKNOWN, compensation, audit, attachment or draft was modified. No message was
sent. Public evidence contains no conversation URL, account identity, private
path, chat text, screenshot or raw session log.

## Exact resumption boundary

The screenshot already exists and must not be requested again. Resume only after
this shared profile's other acceptance finishes and a visible authorized persisted
test draft can be rebound under the **new** receiver/session/document identity.
Do not reuse the dead receiver's window IDs or treat its earlier qualification as
a current ACK. Reuse the existing bounded executor and selection observer, first
reconfirm no trial sentinel or input operation, then perform the sole new input.
Choose click timing from native visibility, never from internal ACK readiness.
No initialization message, account change, extension change, new architecture,
new CI or production patch is required by the evidence obtained here.

Non-author read-only review independently matched the PNG bytes/encoding/system
marker, native stop ordering, full database rows, all 36 protected hashes and
public evidence digests. Limited evidence review PASS; no approval of cold-click,
selection preservation or upload admission is implied.
