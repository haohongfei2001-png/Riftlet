# Round 8 cold-start evidence

Both samples ran source `85250a869f06d99e3d3ab046116f560bac572fd9`. Both used one accessibility press, not a physical mouse press. Both refused the original event with `noPublishedTarget`, with **zero new inputs and zero new operations**. Neither establishes a cold-first-click product PASS. The subsequent rejection-code diagnostic change was not present in either runtime.

The companion `cold-timing.json` contains bounded, sanitized measurements and hashes of private source logs. It exports no URL, conversation identity, chat text, original target or browser credentials. Durations use the same host monotonic clock; page and host clocks are not subtracted.

## Sample 1: retained document with an older root monitor

The foreground Chrome process remained stable across the AX press. Preparation reported a unique composer, document focus and an unfocused editor. Five captures failed at native bridge `phase=receipt`; all eight permission checks were granted without prompting. No `capture_return_selection` or complete capture ACK was reached.

After the run, the read-only probe proved the current thread binding and one form/editor/file input. The React root's `current` property was an accessor. The v10 registry retained a monitor for that exact root (11,271 commits; not stopped or restored); v11 and v12 had no monitor and no lease generations. This state satisfies the existing `UNOBSERVED_ROOT_DESCRIPTOR` rejection gate: v12 refuses to instrument an accessor owned by another monitor. The original envelope omitted that fixed error from its whitelist and therefore reduced it to `invalidReply`. The precise original exception was not retained; the post-run structural observation and source gate establish this explanation without replaying capture or restoring the root.

No registry was deleted, monitor stopped, descriptor restored or old operation replayed. An older document must not be “repaired” by discarding its observation identity merely to obtain a new input lease.

| First attempt phase | Duration |
| --- | ---: |
| Local recovery complete → arming started | 20.762 ms |
| Startup permission check (within that interval) | 19.638 ms |
| Arm request → task entered | 4.483 ms |
| Original-session permission check | 40.545 ms |
| Permission returned → native request queued | 12.125 ms |
| Native request queue | 0.019 ms |
| Native execution, including active identity and failed receipt | 42.475 ms |
| Native returned → arm failure published | 0.701 ms |
| Entire first arm attempt | 100.507 ms |
| Subsequent AX observer binding | 22.981 ms |

AX binding now occurred **after** capture completion, including failed capture, as intended by the scheduling change. The first failure preceded the press by 27.438 ms; AX binding ended 4.408 ms before it. This sample therefore does not show AX binding delaying a usable ACK past the click. It shows that the first attempt runs before binding, but never obtains an ACK. The 22.981 ms cannot be claimed as measured end-to-end savings. Binding remains synchronous on MainActor and may delay event delivery in other timing arrangements.

## Sample 2: independent fresh document

The lead opened a new document for the same existing thread while preserving the v10 document. A separate original AX press was performed. The initial editor was automatically focused, so this sample does not test unfocused-editor acceptance.

The first three captures returned the explicit `composerUnavailable` rejection. The first complete native-validated ACK arrived 1,938.115 ms after the original event; publication followed at 1,938.904 ms. The refusal was retained and the late ACK did not backfill or replay the earlier event. AX binding again followed the first failed capture, taking 22.824 ms.

This is a different failure class from the retained monitor conflict. Later read-only inspection found a valid v12 monitor and two generations, after the tab had moved into the background. That later focus state is not evidence of document focus at the original click. The capture logs establish changing availability, but do not identify which composer-availability subcondition failed at each earlier attempt. No controlled, continuously usable composer cold-latency improvement is claimed.

## Diagnostic-only follow-up and remaining boundary

The follow-up adds `UNOBSERVED_ROOT_DESCRIPTOR` and `UNPROVEN_MONITORED_BINDING` to the existing closed rejection enum. It changes error reporting only; no monitor, lease, permission, focus, upload, completion or retry rule changes. Tests exercise the actual JavaScriptCore envelope, both exact failure codes, one-shot receipt consumption, and rejection of altered codes or extra private fields. The Adapter target builds and an independent standalone JavaScriptCore check passes; the newly added XCTest case was NOT_RUN in final hosted CI because no runner was allocated (see `ci-infrastructure.json`); the local Command Line Tools lack XCTest. These local checks are not live browser acceptance.

The earlier source change removes AX setup from the path to the first capture attempt, and these logs verify that ordering. They do not prove a successful cold first click, eliminate the need for a complete pre-event ACK, or authorize clicks with no prior proof. The remaining product gap is explicit: a foreground click made before usable target evidence is published still refuses. This round performs no further upload clicks.

## Final diagnostic confirmation

The packaged final source `ee1d960adf67432be627e86e7aa9350e5d85d9c0` was then run once against the retained v10 document without any click/input action. Its first capture returned `pageRejected(unobservedRootDescriptor)` explicitly. `diagnostic-confirmation.json` records the exact first attempt and private-log hash. This confirms the previously inferred refusal class without stopping the old monitor or changing its descriptor. It is a diagnostic PASS, not a cold-click product PASS.

## A / B / C interpretation for integration

| Boundary | This round's evidence | Consequence |
| --- | --- | --- |
| A: useful work can run earlier | Real first capture finishes before the 22.98 ms AX hint registration; permission is still fresh. | Keep the scheduling patch, but do not translate relocated duration into a demonstrated successful-click speedup. |
| B: complete native validation exists, App publication follows | Fresh-document first native validation → App effective ACK is about 0.789 ms. | No evidence here of a large publication backlog; no replacement of effective ACK with earlier diagnostic timestamps. |
| C: original click has no trustworthy target proof | Both original AX events have no published target; the fresh first complete ACK is about 1.938 seconds later. | Preserve the original refusal, do not queue it for a future target. Fresh sample's early composer availability was not continuously controlled. |

The older round-seven continuously foreground sample remains separate historical evidence of a roughly 26.7 ms late ACK. It is not re-labelled as a round-eight measured latency or as fixed by the new source.
