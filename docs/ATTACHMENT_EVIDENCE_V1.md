# Original attachment evidence v1

This is the PR #35 source contract, not a ChatGPT response schema or a real-page
acceptance claim. `AttachmentObservationEnvelope` schema 4 adds independently
versioned facts. Schemas 1–3 remain readable; no historical operation is upgraded.

## Evidence produced by the current page

The exact original `File` is registered before the unique setter/change. Its
captured change, original SHA-256 and invocation must agree before any request
fact can be exported. Only a fetch body or XHR body that is this same object is
observed. Copied Blob, FormData, Request, stream, cached functions and workers are
not silently treated as covered. No URLs, headers, request/response bodies, chat
text or preview bytes are persisted in these facts.

Fetch preserves the original return value without attaching Promise handlers:
only call entry and synchronous throw are known. XHR observes its own terminal
events; it does not attach upload listeners that could change CORS preflight.
Loss of hooks, duplicate send, invalid events and document retirement close the
observer. Closed observation is **not** network cancellation. A request error or
HTTP 2xx is **not** platform finalization, irreversible retirement or task isolation.

Existing exact completion now emits `AttachmentCompletionEvidence`: the original
operation/asset/attempt/hash/target/invocation/attachment binding plus either equal
original/observed byte count and SHA-256, or equal full-resolution sRGB RGBA8
dimensions and pixel SHA-256. There is no pixel tolerance or resampling. The
original 8 MiB / 16,777,216-pixel limits remain. A new state advertises proof
protocol 1; capture installs it alongside preserved older states. An old pin
cannot start a new input under an incompatible observer. Old operations remain
read-only and cannot acquire a fabricated new proof.

## Platform contracts and consumers

The following internal contracts are implemented and tested with explicitly
synthetic protocol fixtures. **No current ChatGPT decoder produces them.**

| Contract | Required semantics | Consumer |
| --- | --- | --- |
| `platformFinalizedOriginal` | Original byte request, stable platform task and attachment reference, independently final processing result | Bound COMPLETE, separately admitted platform capability |
| `irreversibleRetirementNoAutomaticRetry` | Original task permanently retired with a durable identity; no residual automatic completion/retry | Original attachment retained in failure receipt; separate retry and termination policies |
| `independentTaskSurvivesSubsequentInput` | Platform ownership independent of the shared composer input; original call settled and original START | Continuation v2, original live append only; no reconcile/restart promotion |

These enum values and IDs are normalized claims, not invented response fields.
They require an independently reviewed source decoder and matching native policy.
The page cannot choose a profile. Completion retains the original receipt profile
so a later correlated failure can still refer to that same operation. Structural
validity alone grants no admission or task ownership.

Core binds each new proof to the original durable dispatch invocation. An admitted
platform task gets an immutable checkpoint that survives proof-less UNKNOWN and
restart; subsequent task/attachment/request aliases are rejected across pins in
the same draft. Unadmitted observations remain journal candidates and cannot
reserve task ownership. Termination only makes a later **new click/new operation**
eligible; it never replays an input. Continuation cannot retrofit the first START,
restore a coordinator's expired owner, or free legacy/unproved UNKNOWN.

## Remaining platform facts

Resized-preview COMPLETE still needs a real, verified mapping from the original
byte request to a stable platform attachment and a separately final processing
state. Safe retry additionally needs an irreversible task-retirement fact;
multi-attachment continuation needs the platform's actual task-isolation behavior.
Neither a filename, exact File reference, final card, 100% progress, aborted XHR,
nor absence of an observed retry supplies those missing facts. Their production
profiles remain empty. Browser access restrictions were not bypassed.
