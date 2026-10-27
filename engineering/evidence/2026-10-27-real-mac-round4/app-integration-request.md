# Pro integration request: native ACK → MainActor publication → original input

Status: **interface/review request, not implemented admission or a GUI PASS**. Baseline `a441c70f3c4071069bd594513ecf16600bbb0ab8`. This local round owns adapter and acceptance-helper changes only. Core/App/product UI remain Pro-owned. No mailbox, delayed-click replay, timestamp backfill or product input change is authorized by this document.

## Immediate objective: measure the actual gap

Current capture has multiple completion boundaries:

1. App starts a scheduler attempt in a host epoch.
2. Native serial transport obtains the complete nonce-bound reply and rechecks active native selection.
3. Executor resumes on MainActor and checks foreground PID/launch again.
4. WebAttachmentAdapter decodes/checks the target on its actor.
5. App completes the attempt, checks epoch/session and publishes ArmedTarget on MainActor.
6. The accepted original NSEvent supplies its own timestamp to freezePress.

Baseline `native_bridge.transportSucceeded` did not certify steps 3–5. A native transport log timestamp must not be substituted for `ArmedTarget.acknowledgedUptime`. The current conservative freeze rejects an ACK published after the original input event even when some native work finished earlier. Whether publication delay actually explains a failed first click must be demonstrated with correlated trace.

The adapter increment in this round will add complete typed capture validation and **diagnostic-only** native receipt/native validation/executor-main-return timestamps, plus a request ID and opaque target digest. It will not change App freeze behavior or backdate authority. Pro should review the completed adapter implementation and source SHA before integrating these diagnostics.

## Required correlated fields and semantics

All times below are finite host uptime seconds. Do not compare page performance.now(), wall time, or independently converted browser timestamps with NSEvent.timestamp. Sleep/wake and process replacement remain host-epoch invalidations.

| Field | Meaning / producer |
|---|---|
| `captureRequestID` | Unique per capture invocation; must survive native transport, adapter completion and App publication. Not a durable upload operation ID |
| `armAttemptID`, `hostEpoch` | Existing scheduler attempt/epoch, attached by Pro's App before invoking the adapter |
| `targetDigest` | Opaque correlation of the complete lease using a defined stable encoding. Not a substitute for full-lease equality or target validation |
| `nativeReceivedUptime` | Native queue has the complete response bytes. Does not alone imply a decoded, valid target |
| `nativeValidatedUptime` | Nonce, exact response shape/typed lease, expected adapter/surface/native context and required native return-time checks have succeeded |
| `executorMainReturnedUptime` | Executor resumes on MainActor and passes its existing foreground/lifetime check; this is not App publication |
| `adapterValidatedUptime` | If any mandatory validation remains after executor return, record that later boundary rather than calling earlier work the full ACK |
| `mainPublishedUptime` | App actually accepts the scheduler attempt/epoch and stores the target |
| `originalEventUptime` | Original accepted mouseDown NSEvent.timestamp; AX retains its explicitly separate invocation time/source |
| `selectionHandlerUptime` | MainActor handles the selection; never replaces the original event timestamp |
| `freezeResult`, `refusalReason` | Closed code-owned labels, not page/native localized exception text |

Keep the existing time for an already armed exactly equal lease if that remains the intended policy, but log **both** this attempt's actual publication/validation boundaries and the effective armed ACK time. Otherwise a repeated capture can falsely appear to prove the first ACK's delivery. Explicitly distinguish `reusedExistingArmedTarget` from new publication.

Do not infer an exact request match solely from a repeated target digest: two captures of the same lease can have different completion times. If the current adapter-only trace cannot carry the request ID through the existing `captureTarget() -> TargetLease` API, state that limitation and use the following integration seam for a later Pro-owned change rather than claiming causality from neighboring log lines.

## Proposed minimal integration seam for Pro review

This is a proposal, not a requirement to build a new Core abstraction now. Preserve the existing AttachmentAdapter and WebBridgeExecutor APIs for their ordinary callers. An optional specialized API in RiftletAdapters can return typed diagnostic metadata with the same captured target:

```swift
struct CaptureInvocationContext: Sendable {
    let requestID: UUID
    let armAttemptID: UUID
    let hostEpoch: UUID
}

struct CapturedTargetDiagnostics: Sendable {
    let context: CaptureInvocationContext
    let target: TargetLease
    let targetDigest: String
    let nativeReceivedUptime: TimeInterval
    let nativeValidatedUptime: TimeInterval
    let executorMainReturnedUptime: TimeInterval
    // Include adapterValidatedUptime if required validation remains there.
}

// Optional specialized Web API; names are provisional.
func captureTargetWithDiagnostics(context: CaptureInvocationContext)
    async throws -> CapturedTargetDiagnostics
```

Pro's App generates/passes the existing attempt context, consumes the returned target as before, and emits `mainPublishedUptime` only after scheduler acceptance. Rejected/stale/stopped attempts log a rejection instead of publication. The local adapter may expose a non-authorizing diagnostic callback instead of this return type, provided request correlation is exact and neither callback nor observer can change target selection. Callbacks must not synchronously dispatch native queue → MainActor, hold a logging lock across transport, or block the main actor waiting for native work.

No Core/App source is changed by this local request. Product UI continues supplying original event metadata as it already does. Pro may choose a smaller equivalent seam after reviewing actual trace evidence.

## Full native ACK exists, but App publication has not run

There are two distinct cases:

- `nativeValidated < originalEvent < mainPublished`: a complete earlier ACK may exist, but current App cannot synchronously read it. This is the candidate publication-gap case to measure.
- `originalEvent <= nativeValidated` (including incomplete bytes, late validation, a still-pending capture or a genuinely uncaptured cold page): there is no proven complete pre-event ACK. This click must remain refused, even if the handler runs after the later response arrives.

**No change to current refusal behavior is requested in this round.** Only if actual correlated traces establish the first case should Pro consider a thread-safe immutable ready-ACK inbox. Such an inbox would require pre-event complete typed validation and exact native-context checks, request/epoch-bound publication, synchronous revocation on stop/wake/rebind, and a nonblocking snapshot getter that never starts or waits for capture. Original mouseDown could freeze only an already completed same-context record with strict `nativeValidatedUptime < event.timestamp`; it could not later read the newest target after a wait. The frozen lease still requires existing page identity/generation and commit guards. This design would need separate independent review and tests before adoption.

Do not implement a mailbox speculatively, retain cold rejected clicks for replay, start capture in mouseDown, use pointer arrival as identity proof, or accept an ACK that arrived after the event but before its handler. A final current-state native check also cannot prove every intervening same-tab business A→B→A transition.

## Minimal acceptance for any future publication-gap change

Use controlled scheduler/clock tests, then one correctly attributed live case:

1. Complete validation before event, deliberately delayed main publication: exact earlier ACK is the only candidate; no extra capture/input.
2. Event before complete validation, even with delayed handler: refusal, no replay.
3. Raw receipt before event but typed/context validation after event: refusal.
4. Equal, NaN, infinite or out-of-order times: refusal.
5. Stop/wake/rebind/old attempt or process replacement before publication: stale ACK cannot publish or freeze.
6. Target A before event, B afterward: never retroactively choose B; known revocation defeats A.
7. Lost/malformed receipt and unsupported surface: no ready record; existing UNKNOWN semantics remain unchanged.

Passing these tests would not by itself close the real cold-page, multiwindow or business-continuity matrix. Production screenshot input and safe retry stay disabled until their independent admission criteria are met.

## CUA CLEAR coordinate boundary and helper-only increment

The previous attempted CLEAR event named row window 47745 but reported converted screen coordinates `(3681.5, 722)`, outside its actual frame `(1840…1912, 878…922)`. The intended CLEAR was `(1841.5, 880)`. The requested point and delivered event do not agree, so CLEAR remains **NOT_RUN**, not hit-through PASS or FAIL. GAP event 4 correctly reached the underlying probe at `(1884, 873)`; that remains a single automated observation, not physical hardware evidence.

The helper now additionally records original NSEvent window-local coordinates, actual event-window frame/content coordinates, screen frame/backing scale, optional raw CGEvent location and bounds membership. These are separate coordinate-space facts, not a conversion heuristic. No event is modified, rescaled, redirected or synthesized; no product geometry or hit rule changes. Mouse-up outside a window can be legitimate after dragging, so bounds flags are observations rather than an automatic tool-failure verdict.

Use fresh native geometry and the current tool screenshot's documented coordinate space when repeating an authorized automated action. Never adapt product input to a tool scaling bug or substitute current pointer position for the original event. AppKit `.mouse` identifies dispatch path, not physical-human provenance.
