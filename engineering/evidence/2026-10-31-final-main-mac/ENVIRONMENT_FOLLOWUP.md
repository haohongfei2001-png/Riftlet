# New-window environment follow-up (same final App, no rebuild)

This is new on-device resource evidence after the initial handoff, not another
query of the missing old tabs. Product source remains final main
`60eaaef64848fc5535580e4fcb65e45f3f41e814`. The original package/startup/CI results
were reused, not rerun. No App instance, screenshot input or upload was started.

## What actually changed

- Read-only task state showed the previous workspace-layer task **idle** and the
  separate job-application task **active**. The latter's Chrome main process has
  its own user-data directory and CDP connection; those were not operated by this
  task. Its active status alone was not treated as proof that normal Chrome was
  unavailable.
- A 30.012-second passive foreground observation found normal Chrome stable.
  Recent task execution was through the other configuration's CDP transport.
  These are bounded observations, **not a durable exclusive-frontmost lease**.
- With normal Chrome still foreground and its exact PID/launch identity and AE
  permission checked, one native AE `make window` was executed. Readback found
  exactly one new window and identified its active blank tab. Only that tab was
  navigated to ChatGPT Home. No existing window/tab was closed, reloaded or
  navigated, and no activation was issued to steal the frontmost application.
- The new window is recognizable as **Riftlet 最终真机验收 · 新建隔离草稿**.
  Its exact owned IDs and receiver identity are retained privately for resumption.
  No old tab ID or old conversation route is required.
- The new page has one empty visible-layout editor, a form, four file inputs,
  zero attachment images, Chinese locale and a valid signed-in session. A bounded
  same-origin session read confirmed the previously known account display-name
  match; only booleans and an account-ID fingerprint were retained privately.
  No credential/token or full account response was saved. No account login,
  profile creation, extension modification or permission change occurred.

## New causal boundary observed

Native uptime is the host boot's monotonic clock; these are observed checkpoints,
not inferred event timestamps:

| Host uptime | Observed fact |
|---|---|
| 806216.7017185 to +30.012 seconds | Normal Chrome foreground stable during passive sampling. |
| 806370.004702 | Exact normal Chrome foreground before the sole create operation. |
| 806370.2101265 | Native window-create reply succeeded. |
| 806370.5951791 | Exactly one new window; normal Chrome still foreground. |
| 806370.6482403 | Sole navigation of the new blank tab returned success. |
| 806442.2381899 | Frontmost process was the **ChatGPT native App**; owned window no longer first. |
| 806442.2610205 | Owned page returned `visibilityState=hidden`, `hasFocus=false`. Editor empty; no attachments. |
| 806474.6086460 | Normal Chrome frontmost again, but a different window was first; owned page remained hidden/unfocused. |

The first loss occurred between checkpoints; its exact instant and initiating
actor are **not observed**. Do not attribute it to the job task, CUA, Riftlet,
ChatGPT React or a mouse action without evidence. No raw mouse, keyboard, file
setter, change/input or transfer was issued after the loss. No focus was taken back.

A second independent gate was also confirmed: the fresh page is **Home**, not a
persisted conversation. In this original package, the restricted candidate calls
`SystemScreenshotWebCandidate.validateAdmittedTarget`, which requires the
recognized persisted-draft profile. The separate ordinary-current-draft internal
scope is not a runtime switch in this delivered original App. Rebuilding,
borrowing that scope, sending an initialization message, or bypassing its gate
would contradict this run's instructions. An editor and file input alone do not
satisfy the original package's full input admission.

## Results and unchanged boundaries

| Item | Result |
|---|---|
| New owned window creation and active-tab readback | MAC_PASS, exactly one new window; no old-target reuse; full tab count not measured |
| New page session/editor/attachment-entry structural check | MAC_PASS limited to read-only facts above; not a full target ACK |
| Exclusive foreground qualification | Not established; observed external foreground loss, no retry/steal |
| Original restricted package's target qualification | Not met: new Home draft; no persisted identity asserted |
| Natural cold-first-click retest | BLOCKED before click; zero input attempts |
| Noncollapsed-selection/upload comparison | BLOCKED before selection setup; no new blur/collapse root-cause claim |
| Historical cold/selection FAIL | Still unresolved, not relabeled as this run's outcome |
| Other foreground-dependent physical/visual/Feedback cases | NOT_RUN; prior results unchanged |

Both protected acceptance stores were read back without launching them: candidate
7 operations/3 starts/18 assets and ordinary-internal 5 operations/3 starts/6 assets,
all exact against retained originals. Old UNKNOWN, compensation and media were
not modified. Production admission, continuation and safe retry remain closed.
No product source, build, CI or existing user draft was changed.

## One remaining manual handoff

Provide **one empty, non-private, persisted test chat in the newly created window,
with a continuous exclusive foreground interval of about three minutes**. Because
this run forbids sending messages and the original package excludes Home, the
agent cannot create that persisted chat by sending an initialization message.
The owner can initialize this dedicated chat or supply a different authorized
empty persisted test chat, then leave that window foreground while other
foreground automation is paused. This is a test-resource handoff, not a daily
Riftlet usage requirement or a request to try an unfinished Beta.

After that handoff, reuse the existing executor/selection observer with fresh
system PNGs and original event timestamps. Do not wait for an internal armed flag,
replay a refused click, recover an old Range, or claim uploads from old evidence.
No further missing-tab queries or uncontrolled window creation is needed.

Non-author evidence review verified chronology, raw-file hashes, preserved database
rows and public privacy. Its one finding (unmeasured full new-window tab count)
was resolved by narrowing the claim above. This review does not approve upload
admission or claim a new cold-click/selection result.
