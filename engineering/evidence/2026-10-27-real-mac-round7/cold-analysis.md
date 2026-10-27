# Round 7 cold-click boundary: earlier prebinding, measured ACK gap, and refusal

Analysis date: 2026-10-27. Candidate App source: `f6417c6faaf8aa21ac587b07f25ea2a159af021f`. The coordinator identified the separately packaged, no-overlay baseline as `336ecce`; it must not be labelled as the candidate source. This analysis reads existing local evidence only and performs no browser actions or new selections.

**Neither cold press establishes cold-first-click product PASS.** The initial observed press is not a valid-foreground Chrome test. The helper recorded foreground PID 730 before and after AXPress; the runtime owner identified that process as Finder. The App had no published target at the original event. The next complete native validation happened 105.490 ms after that event. The result demonstrates refusal without pre-event proof, not successful attachment to an intended foreground Chrome draft. A separate later Chrome-frontmost sample is documented below; it also refuses because complete proof arrives after the click. Both runtimes use f6417c6, before the subsequent diagnostic-only trace deduplication patch.

## Evidence and clock scope

Private inputs are `/tmp/riftlet-round7-cold.jsonl`, `/tmp/riftlet-round7-cold-press.json`, and `/tmp/riftlet-round7-baseline-live.jsonl`. They remain local; this report does not publish page URLs, complete targets, conversation identifiers, private content, or raw browser descriptors. Hashes of the snapshots read for this analysis:

| Input | SHA-256 |
| --- | --- |
| cold.jsonl | `389faae1e3b848e71e1bcfb5d392c0ea2d60464cf82dc926705334583d89a28d` |
| cold-press.json | `61a9b50ac45c13db010a7a045de8ddbd35d7a6c51b3fa05b68e6385b42046222` |
| baseline-live.jsonl | `47f0a48c669fc812ca2cf80e5c56f83797282127094b5b349d30a434b0c142a0` |

All durations below subtract host `systemUptime` values from the same run. They are software timestamps, not physical mouse latency, renderer timestamps, pixel presentation, or network timing. The candidate's first full chain joins capture request `316AD316-435C-4790-913F-A10CDA96BDCF`, arm attempt `2D83CF55-500A-40E9-AD9E-DADE8DA696F4`, and one host epoch. The baseline uses its own distinct request `F4FAD3F2-0A98-4B4E-B91D-DD4F24301C6A`. Matching hashes or nearby timestamps are not used to join different requests.

## A. Earlier prebinding: implemented order and observed order

The candidate performs local interrupted-operation recovery and snapshots original unresolved IDs and successful IDs before arming. After a fresh passive permission check, the first arm attempt completes before `recoverOriginalObservations(operationIDs:)` begins. That API observes only the original-ID snapshot; it does not repeat `recoverInterruptedOperations()` or reset a newly prepared click. The first-use path and each arm still perform actual permission checks. No earlier permission result becomes a cached grant.

| Candidate boundary | Host uptime (s) |
| --- | ---: |
| Local recovery and original-ID snapshots complete | 466878.688728042 |
| Arming starts | 466878.898445417 |
| First effective App ACK stored | 466878.993148333 |
| Original remote recovery starts, snapshot count 6 | 466878.993215667 |
| Original remote recovery finishes | 466879.095101417 |

The first effective ACK precedes original remote recovery by **0.067333 ms**. The remote recovery span is **101.885750 ms**, including its fresh permission check, asynchronous scheduling and observations. This proves the intended ordering in this run; it does not prove that every component of that span was formerly avoidable capture delay.

In the baseline, six logged `observe` transport phases occur before first arming: the first queues at 466768.982106917, the last ends at 466769.073954000, and the first arm starts at 466769.098537917. Their first-queue-to-last-end span is **91.847083 ms**. These are six transport phases, not necessarily six separate operations. The two runs have different foreground and permission histories, so their startup-to-ACK totals are not a controlled before/after speedup measurement.

The candidate's local-recovery-to-arming interval is **209.717375 ms**, and local-recovery-to-effective-ACK is **304.420292 ms**. Startup permission initially returned `unavailable`; a later passive-resume check returned `granted`. Those facts prohibit claiming that moving recovery alone eliminates all cold-start delay. The source improves one queueing dependency; it cannot supply a target proof for an event that already occurred.

## B. Complete validation to App publication: the measured gap is small

`native_validated` includes decoding and native return-target validation but remains diagnostic: the executor MainActor foreground check, adapter validation and actual App publication still follow. It is not itself input authority. The only effective ACK in the frozen App lease is the original `ArmedTarget.acknowledgedUptime` stored after those checks. `mainPublishedUptime` is a slightly later diagnostic timestamp and is reported separately.

| Interval (ms) | Baseline 336ecce | Candidate f6417c6 |
| --- | ---: | ---: |
| Receipt received → native validated | 8.147125 | 6.129667 |
| Native validated → executor MainActor return | 0.201833 | 0.235250 |
| Executor MainActor return → adapter validated | 0.140542 | 0.122917 |
| Adapter validated → effective App ACK | 0.218875 | 0.161750 |
| Native validated → effective App ACK | **0.561250** | **0.519917** |
| Native validated → publication diagnostic | 0.574500 | 0.531250 |

Both first captures used the strict fixed-ID descriptor fast path. Candidate capture-selection and return-selection reads took 8.532250 ms and 5.880125 ms respectively. Its native capture queue wait was 0.019417 ms and execution was 46.623625 ms. These observations do not support a claim of a large MainActor publication backlog in this sample.

No mailbox or earlier-clock substitution was introduced. Eliminating the entire measured 0.519917 ms post-native interval would still leave the candidate's native validation more than 105 ms after the original selection. It cannot convert this press into a safe cold-first-click success.

## C. No pre-event proof: refusal, no backfill

The helper reports one software `AXPress`, `physical=false`, with AX status 0. That means the accessibility action returned successfully, not that attachment succeeded. The App records original event uptime **466878.887138458**, `freezeResult=refused`, `refusalReason=noPublishedTarget`, `armInFlight=false`, and no foreground-session match.

| Candidate boundary | Relative to original event (ms) |
| --- | ---: |
| Local recovery complete | −198.410417 |
| Arming starts | +11.306958 |
| Native receipt received | +99.360292 |
| Native validation completes | +105.489958 |
| Executor MainActor return | +105.725208 |
| Adapter validation completes | +105.848125 |
| Effective App ACK stored | +106.009875 |
| Publication diagnostic | +106.021208 |
| Original remote recovery starts | +106.077208 |

The nil-frozen-target path cannot capture a replacement. For an existing unresolved operation it may observe that original operation; for a new image it refuses input. A queued selection marker is not an accepted-target token or a prepared upload. The observed original press remained refused when the later ACK arrived. The analyzed trace contains one `selection_boundary` and no `begin`, `chunk`, or `commit` transport records. This report does not infer a durable operation count from that absence; durable database and original page evidence must be recorded separately by the runtime owner.

**Trace-cap limitation:** App `recordAcceptance` is bounded to 2,048 events. Repeated old-operation refresh diagnostics exhausted that budget after roughly a minute in this runtime, as reported by the coordinator. Native trace streams have separate logging boundaries. A later AX action with no new App selection trace cannot be classified from that silence. The later main-A action around uptime 467247 is outside this cold sample's usable App trace window; the coordinator separately observed page input 0 / operations 0 and no new database operation. Those later observations do not make this earlier Finder-frontmost sample a valid Chrome cold PASS. They also do not authorize retrying an unresolved operation.

## Additional C sample: Chrome foreground, proof still arrives after the event

The coordinator ran one separate startup sample after confirming a valid, nonempty ordinary draft with five existing cards and an unfocused editor. This is the same still-pending cold asset previously refused without an operation, not a retry of an UNKNOWN upload. The helper records Chrome PID 59763 both before and after its single software AXPress. Its original App event is **467597.399480333**. At that boundary the App records `noPublishedTarget` and an in-flight capture request `59262BEF-9254-44DD-B6BA-2EE2440710CD`, arm attempt `9262524D-B4F7-4322-A80F-DF8EAB6703BE`. That exact invocation subsequently validates and publishes with the same host epoch.

| Boundary | Relative to the new original event (ms) |
| --- | ---: |
| Native receipt received | +21.402708 |
| Complete native validation | +26.323250 |
| Executor MainActor return | +26.501083 |
| Adapter validation | +26.600750 |
| Effective App ACK | +26.742000 |
| Publication diagnostic | +26.752458 |
| Later activation-triggered arm, browser not frontmost | +723.576250 |

Native-validation-to-effective-App-ACK is **0.418750 ms**. The failure is absence of complete proof before the original event, not a later MainActor publication backlog that could safely be backdated. Startup ordering remains correct: the first effective ACK is at 467597.426222333, followed by original remote recovery at 467597.426296292, a **0.073958 ms** gap. Remote recovery does not precede or cause this cold press's incomplete proof.

The page result records `fileEvents=[]`, preserved text and old cards, and no operation for the selected cold asset. Its listed operations belong to earlier, different assets and must not be counted as new input for this press. The coordinator separately verified no new database operation for the cold asset. This trace contains one selection and no begin/chunk/commit transport action. The runtime was stopped after the bounded sample.

The later page result reports `pageFocused=false`. It was sampled after the logged activation change, approximately 724 ms after the original event, so it does **not** establish that the page lacked focus at the original click. Conversely, endpoint Chrome PIDs, a valid prelaunch draft, and the same in-flight capture's complete original-target ACK are not an atomic measurement of every DOM property at the event instant. They support the valid-foreground cold scenario and the precise no-pre-event-proof causal finding, with that explicit observational limit.

Result: **C safety refusal confirmed; C cold-first-click product requirement still FAIL.** No complete fresh ACK existed before this event, and no old click was replayed after the later ACK. This result does not invalidate the initial Finder sample's classification or establish that all cold cases have been fixed.

Additional private evidence hashes:

| Input | SHA-256 |
| --- | --- |
| foreground-cold.jsonl | `ec9a73346df26bb6338c2f8044b3bf0c0db96d2bc2f16006fc5f19521f9529ae` |
| foreground-cold-press.json | `d6f36ff54009aa92eb6630d5df5291d29d1b7e4e5b3db1b4c7e897bcff776fe0` |
| foreground-cold-result.json | `37ec4f1df96d2a11379f90bc5087a9513212e962495473743aa5bdc314ee55bb` |

## Acceptance-only helper alignment review

The independent dirty-patch review covered only `Sources/RiftletGUIAcceptance/AcceptanceMain.swift` and `SoftwarePointerProbe.swift`, separately from the f6417c6 App timing evidence. The patch identifies the actual row screen, fits the existing helper control/probe window to that screen, logs requested and actual geometry, and retains excluded candidate points with explicit reasons. It does not move product row panels, edit `RiftletUI`, change `RiftletApp` input authority, focus Chrome, or add production upload support.

Before the existing software event pair, the helper still requires fresh stable row geometry, its own foreground/key control window, synthetic assets, own-window routing, and the expected underlying helper window. It retains one batch per process and at most four down/up pairs, with no per-case retry. AppKit may constrain the requested frame; the later real geometry and coverage checks, rather than the requested frame alone, determine whether a case may run. Missing coverage stays `NOT_RUN`. An alignment log is not a routing pass. Successful tagged CGEvent routing remains `PASS_SOFTWARE_ROUTING`; physical mouse and cross-application focus remain separate, unperformed claims.

No blocking production-behavior change was found in that alignment diff. This is a source review, not a new execution or a claim that the patched helper has passed live routing.
