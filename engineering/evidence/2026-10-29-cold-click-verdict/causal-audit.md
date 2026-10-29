# Cold-click causal audit: what existed before the original event

Audit date: 2026-10-29. Read-only source/evidence review of handoff `b4590f4fee8ab43e0ad30d23c980abebe324d20c`, product source `c308d46c1412a56e90d665972c0bc8f6ad1511a3`. This audit does not execute Chrome, select a thumbnail, inspect a database, or claim a new live acceptance result. The earlier empty-lease recovery, permission-publication fix, and durable-capture wake are inherited, not reimplemented here.

**Result:** each of the three usable ordinary-conversation cold failures occurred before complete native target validation. None demonstrates an already completely verified target that missed the original event solely because App publication was delayed. Round 6 had received a page reply before the event, but the required native return-selection check was incomplete. Rounds 7 and 9 had not even received that reply. The bounded post-native interval was less than 0.9 ms in all three cases; eliminating it cannot authorize those original events.

This is a concrete boundary of the inspected implementation and evidence, not a claim that every possible browser integration is incapable of earlier observation. It also does not mean there were no partial clues at the event: frontmost process, an in-flight capture, or an arrived JSON reply are distinguishable from a complete usable target acknowledgement.

## Evidence and join rules

The private raw traces were reread locally; their byte counts and SHA-256 values still match the retained evidence. Only allowlisted host timestamps and closed diagnostic labels were extracted. No raw trace, private path, browser/session identifiers, URL, chat text, screenshot, or database is included here.

| Sample | Tested source | Raw trace bytes / SHA-256 | Existing public evidence |
| --- | --- | --- | --- |
| R6 ordinary `cold-early` | `7878de3138d1c140369c3cfbe69a28dd2770294c`, with the two recorded round-5 acceptance overlays | 709,718 / `36e3abe367ecd794ec5693d0faebf22f4413aecb0af975370db8f3e545dd0896` | [cold-click-evidence.json](../2026-10-27-real-mac-round6/cold-click-evidence.json) |
| R7 Chrome-frontmost cold | `f6417c6faaf8aa21ac587b07f25ea2a159af021f` | 122,848 / `ec9a73346df26bb6338c2f8044b3bf0c0db96d2bc2f16006fc5f19521f9529ae` | [cold-analysis.md](../2026-10-27-real-mac-round7/cold-analysis.md) |
| R9 retained-monitor cold | `fcb052bfe6fad09af5de3c90d5954259e000a8ef` | 26,401 / `4790e1284a76ee18217fce53b8875c411d54d96fd442fd6364b442d15cf6bcf4` | [cold-and-monitor.json](../2026-10-28-real-mac-round9/cold-and-monitor.json) |

Each selected event is joined to its own `inFlightCaptureRequestID`, arm-attempt ID and host epoch, then to that invocation's `capture_ack`, `native_bridge`, permission and `arm_completion` records. A matching target digest or nearby time alone is not a join. All three inputs were software `AXPress`, not physical mouse input. Their `originalEventUptime` is the native accessibility invocation timestamp. It is not a reconstructed hardware mouse timestamp.

The other R6 unsupported-surface refusals are not ordinary-chat cold tests. The R6 `cold-boundary` case had an effective ACK 3.355250 ms before its event and really uploaded once: it is a prebound success, not a no-ACK success. R7's earlier Finder-frontmost sample is also excluded from the ordinary Chrome table; its invalid foreground cannot be repaired by a later Chrome ACK. These classifications remain unchanged.

## Same-host causal timeline

Every numeric cell below is milliseconds relative to that sample's original native AX event. Negative means before the event; positive means after. `NOT_MEASURED` means the necessary boundary was not recorded, not zero delay. The host-uptime anchors are R6 **462957.0128939167 s**, R7 **467597.3994803334 s**, R9 **478922.0360605 s**. Subtraction stays within one run and one host uptime domain.

| Boundary | R6 | R7 | R9 |
| --- | ---: | ---: | ---: |
| Actual system Screenshot completion, T0 | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED |
| Complete original file first available, T1 | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED |
| Local interrupted-operation recovery / original-ID snapshot complete | NOT_MEASURED | −93.308667 | −274.780833 |
| `arming_started` | NOT_MEASURED | −79.597833 | −242.221375 |
| This arm's `startedUptime` | −126.877042 | −61.690042 | −241.721958 |
| Arm task entered | NOT_MEASURED | NOT_MEASURED | −234.260708 |
| This arm's actual passive permission check starts | NOT_MEASURED | −58.318500 | −234.032625 |
| This arm's permission check ends, granted | NOT_MEASURED | −28.486208 | −167.014750 |
| Native capture enqueued | −125.903833 | −21.126750 | −165.328125 |
| Native serial worker starts | −125.881125 | −21.105208 | −149.567458 |
| MAIN page capture itself completes | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED |
| Decodable nonce reply received by host | −20.422958 | +21.402708 | +192.470208 |
| Complete native validation, including return selection | +6.364750 | +26.323250 | +208.686750 |
| Executor returns after MainActor foreground check | +6.710333 | +26.501083 | +208.970625 |
| Adapter validates target/scope | +6.932875 | +26.600750 | +209.093958 |
| Effective `ArmedTarget.acknowledgedUptime` stored | +7.246000 | +26.742000 | +209.411208 |
| Later App publication diagnostic | +7.247250 | +26.752458 | +209.412000 |
| Original-event callback diagnostic | +0.047208 | +0.043458 | +0.052958 |

| Measured component, ms | R6 | R7 | R9 |
| --- | ---: | ---: | ---: |
| Target-arm passive permission span | NOT_MEASURED | 29.832292 | 67.017875 |
| Native serial queue wait | 0.022708 | 0.021542 | 15.760667 |
| Complete native bridge execution | 132.332417 | 47.475042 | 358.326542 |
| Receipt → complete native validation | 26.787708 | 4.920542 | 16.216542 |
| Complete native validation → effective App ACK | 0.881250 | 0.418750 | 0.724458 |
| Complete native validation → publication diagnostic | 0.882500 | 0.429208 | 0.725250 |

The receipt-to-native interval is not pure MainActor scheduling: it includes reply decoding/digest and the native return-selection read. The R6 historical path did not independently time all of those substages. R7's fixed-ID return-selection read was 4.549792 ms; R9's was 15.937292 ms. R9's initial fixed-ID read was 86.740792 ms and Swift compilation overlapped the run, so it cannot be compared with R7 as an idle-host performance regression or a controlled optimization result.

R7's local recovery preceded arming, and original **remote** recovery began only after the first effective ACK, 0.073958 ms later. The remote old-operation observations therefore did not cause this sample's lack of pre-event proof. Its older source still registered AX hints synchronously before the first capture; `arming_started` to arm-start was 17.907792 ms, but the trace does not isolate that entire span as AX registration. R9/current source already defers that hint binding until after capture completion. That existing change is not new work in this audit.

R9 separately verifies compatible v13 borrowing from retained v10 monitoring without replacing the old descriptor/registry or deleting its operation. The selected event still preceded the later valid v13 ACK. This distinguishes the repaired monitor-installation problem from the remaining no-pre-event-proof boundary. R9's `foregroundSessionMatches=false` at the event is derived from `armedTarget == nil`; it does not independently prove that Chrome was in the background.

All three selected events remained refused with no new input for the selected asset. R6/R7 nonempty-draft evidence and R9 empty-text/collapsed-selection/zero-old-card limitations retain their original scopes; this audit does not upgrade them to a new retention or physical-input PASS.

## What cannot be derived from these timestamps

1. **Screenshot → prebinding start:** these were cold-start/foreground experiments using already available test assets. Actual system screenshot completion and first complete-file availability were not measured in their capture chains. The current `CaptureService.onImported` path requests `captureDurable` before arrival-preview work and `refresh`; that order is inspectable code, not a measured new T0/T1 speedup. `captureDurableObserved.uptime` is `ScreenshotSourceObservation.readyUptime`, sampled after import returns, rather than the MainActor callback-entry time. Its `firstSeenWallTime` is a separate wall clock. Neither is a substitute for T0.
2. **Page observation completion → host receipt:** the envelope writes its nonce receipt after the synchronous page function returns, but these traces do not log an independently calibrated page-completion timestamp. Native bridge start and host receipt bound aggregate remote work; they do not separate Chrome event dispatch, JavaScript execution, receipt availability, poll wait and reply delivery. A successful URL-set Apple Event does not timestamp completion of the MAIN function.
3. **Native complete → App publication:** this interval is directly measured above. `native_validated` is diagnostic only: the executor's later MainActor foreground check, adapter target/scope checks, scheduler epoch check and actual App publication still follow. Calling receipt arrival or native validation the final App ACK would change authority, not merely improve logging.
4. **Wall clock / renderer clock / separate runs:** `Date`, file metadata dates and process `launchDate` cannot be subtracted from host `systemUptime`. `performance.now()` has a document-specific origin and `Date.now()` a renderer wall-clock basis; neither may be subtracted from these host event values without an explicit clock mapping and uncertainty bound. Uptime anchors from separate runs are not a controlled speedup measurement. Hardware click latency, animation presentation and network byte timing are not measured here.

## Current route and where authority enters

The inspected implementation retains this order:

`native hint / committed import` → scheduler request → actual permission inspection bound to original host epoch / foreground / receiver → original foreground Chrome process selected → shared native serial queue → exact process lifetime and foreground recheck → strict front-window/active-tab IDs → one MAIN command submission → nonce-only receipt reads → full target decode/native-context validation → same native active selection recheck → executor MainActor foreground validation → adapter scope validation → same scheduler epoch/foreground validation → actual App ACK publication.

At a real AppKit press, the image/number input window forwards **the original `NSEvent.timestamp`**, asset ID and event identity. `freezePress` synchronously uses only an already published `ArmedTarget`; `freeze` requires `acknowledgedUptime < eventUptime <= nowUptime` and original host/foreground session. Mouse release uses the frozen target. A nil frozen target is not repaired by a later ACK. AX uses its own invocation time and must remain labelled AX.

The current permission helper publishes only results belonging to the original context. A superseded check that never performed a page capture cannot globally invalidate a newer same-context ACK; a stale grant cannot authorize its caller. Actual capture failure, changed foreground and stale epochs still reject. This resolves a separate deterministic cancellation race; the three historical timing traces do not establish it as their failure cause. Every native permission check still runs; no permission grant is cached to reduce the measured spans.

Source anchors: [Main](../../../Sources/RiftletApp/RiftletMain.swift), [ArmedTarget](../../../Sources/RiftletCore/ArmedTarget.swift), [permission publication](../../../Sources/RiftletApp/AutomationPermissionPublication.swift), [Chrome executor](../../../Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift), [native capture proof](../../../Sources/RiftletAdapters/NativeCaptureProof.swift), [receipt reader](../../../Sources/RiftletAdapters/MainWorldCommandEnvelope.swift), [adapter validation](../../../Sources/RiftletAdapters/WebAttachmentAdapter.swift), [input islands](../../../Sources/RiftletUI/RiftPanelController.swift), [capture service](../../../Sources/RiftletCapture/CaptureService.swift).

## Synchronous API capability: current observation is not historical identity

The distinction below follows the actual code and public API contract. It does not claim an unmeasured API-latency bound.

| API / existing mechanism | What it can establish | What it does not establish for an earlier Riftlet press |
| --- | --- | --- |
| Original `NSEvent.timestamp`, `windowNumber`, position | Timestamp and recipient Riftlet input-island window of that event | Chrome window, tab, composer, draft generation, or whether an attachment entrance was valid. The clicked window belongs to Riftlet. Apple's [NSEvent documentation](https://developer.apple.com/documentation/appkit/nsevent) defines event time and its associated window. |
| Synchronous `NSWorkspace.frontmostApplication` + process/launch session checks | Which process currently receives key events; current process-lifetime binding | A prior event's foreground history, selected tab, business draft or DOM state. Apple's [frontmostApplication contract](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) is process-level. |
| AX focus/window notifications and a current focused-window read | A hint that focus/window state changed; a current AX window object when the remote request completes | An original-event timestamped ChatGPT business identity. The existing observer intentionally reads no chat text or accessibility subtree; its callback yields before refreshing and requesting an authoritative capture. |
| `CGWindowListCopyWindowInfo` / WindowServer geometry | Current window IDs, bounds and management information in the user's session | Selected browser tab or React composer/draft identity. The [Window Services contract](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29) provides window descriptions, not browser business history. |
| Chrome strict fixed-ID `get active tab of front window` | Native window/tab pair when Chrome executes the exact addressed Apple Event | The pair at an already elapsed mouse-down. Waiting synchronously for a reply does not rewind remote execution. Fallback still performs multiple reads and is not an atomic historical snapshot. |
| MAIN v13 capture + retained root-monitor continuity | Exact page document/composer/logical draft and usable surface when the page executes, plus the monitored continuity it actually observed | Unobserved transitions before monitor installation, or a trusted pre-event host acknowledgement when its full result arrives after the event. |
| TCC/Automation passive check | Whether the addressed native receiver can currently receive the relevant Apple Events | A selected page, valid composer or screenshot input authority. |

A native mouse event tap could provide an earlier observation opportunity; by itself it still has no ChatGPT business identity. An extension/Native Messaging channel could push **already observed** page identity before the event and reduce remote round trips. It cannot manufacture proof for an event preceding both page observation and host receipt. This audit does not install or approve an extension or make it a default requirement.

## Reproducible counterexamples and classification

These are either existing deterministic regressions or explicit event schedules; none requires another real upload.

| Case | Concrete event order | Consequence / existing reproducibility |
| --- | --- | --- |
| A: normal prebound | ACK at host 9; original mouse-down 10; callback at 20 | The exact original target may freeze once. `testPreEventPublishedACKAuthorizesOriginalTargetOnce` exercises the actual AppKit input-island callbacks with software events. |
| B: verified but not App-published | A hypothetical complete proof before event 10, final required checks/publication after 10 | No R6/R7/R9 sample demonstrates this case. It needs its own evidence before considering a publication-path change; the native diagnostic alone is not final authority. |
| C1: arrived reply, unfinished validation | R6 receipt at −20.422958 ms; original event at 0; native return validation at +6.364750 ms | Real refusal is reproducible from the retained chain. Replacing effective ACK with receipt time skips the required native selection check. |
| C2: no reply before event | R7 receipt +21.402708 ms; R9 receipt +192.470208 ms | No optimization solely after receipt can make either original event prebound. |
| Delayed delivery | Original event 10; ACK published 10.026742; callback executes at 20 | `testACKAfterOriginalEventButBeforeCallbackNeverBackfillsDelayedMouseDown` rejects despite a target existing by callback delivery. Substituting handler time is demonstrably wrong. |
| ACK while held | Mouse-down 10 with no target; publish 10.05; release 10.1 | `testACKArrivingWhileHeldDoesNotRescueUnprovedOriginalPress` remains nil-frozen. Waiting for release is not evidence at press. |
| Later draft replacement | Freeze A at original down; publish B while held | `testLaterPublicationCannotReplaceAlreadyFrozenOriginalDraft` retains A, still subject to original-target validation. Never substitute B. |
| Post-event current-state query | Press while A is active; before Chrome processes the query, select B in the same process; query returns B's perfectly valid current IDs | A current synchronous query identifies B, not click-time A. Same PID or a valid B composer cannot repair the missing original proof. This is an explicit counterexample schedule, not an additional claimed live result. |
| A→B→A endpoints | No installed continuity observer; same process/window/tab is observed on each side, while business A→B→A occurs between them | Equal endpoint IDs cannot prove no intermediate business transition. Current v13 monitored continuity helps only for transitions actually observed; URL equality and native window identity alone cannot replace it. This is a proof-boundary counterexample, not a new live A→B→A PASS. |

The AppKit cases are existing tests in [ColdClickBoundaryTests.swift](../../../Tests/RiftletAppTests/ColdClickBoundaryTests.swift); their prior CI result is recorded by the [source handoff](../2026-10-29-cold-click-reliability/results.json). This audit does not rerun or relabel that prior CI. The tests use software-created NSEvents, not physical input or a live ChatGPT target.

## Bounded decision for the next implementation step

**A, earlier reliable prebinding:** retain the implemented foreground/wake/permission recovery, fixed native ID reads, deferred AX hint setup and durable-capture wake. They increase opportunities to obtain real proof before a normal click. More timer tuning is not justified by this audit. Any additional change should address an independently demonstrated dependency, cancellation or observation bug.

**B, publication-only gap:** presently unproven as the cause of the audited failures. Do not add an ACK mailbox, backdate ACKs or remove the remaining foreground/scope checks on the strength of these samples. The maximum observed complete-native-to-effective-publication interval here is 0.881250 ms, while the complete native proof itself is already late.

**C, no completed pre-event authority:** the present Apple Events route cannot safely authorize these original events using only later current-state reads. Keep the refusal light and retain the image. Do not retain a rejected click for a future target, borrow a new draft or relax UNKNOWN protection. An alternative transport warrants a bounded comparison only if it supplies real earlier identity and continuity; it must retain the same distinction between actual pre-event proof and a late reply.

New live original-event/system-screenshot/physical-input acceptance for this audit: **NOT_RUN**. Existing scoped safety refusals: **confirmed from retained evidence**. Ordinary no-ACK first-click product result in these samples: **FAIL**. No database, old UNKNOWN, media, native settings or browser state was modified.
