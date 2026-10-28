# Restricted system-screenshot admission integration · 2026-10-28

This packet records the prospective internal-candidate admission of the real F evidence, not another real screenshot upload or a production release.

## Inputs and ancestry

- Official baseline: `871d825a43a759bb6dd8ded9cdc99a340d8e0e64`.
- F evidence handoff: `493d1d8b898d18e34709463d2dceca8c85ad4014`, parent `f2ae645451044649fbe73326952efbe084353869`.
- Actual F runtime: `48574df19f34e5681ee98815750e279540e9eb9b`; original source CI `40656871851`, completed/success.
- The evidence handoff is a sibling of the official integration documentation. Both parents are retained in the integration commit. Existing stage-one/two, wake recovery, monitor compatibility and sRGB fix history are neither cherry-picked again nor flattened.
- Feedback `codex/feedback-v01-20261028` and Draft PR #7 remain independent. This packet changes no feedback files or refs; the shared Main diff consists of three accurate candidate/self-check strings only.

## Separate evidence decisions

- [Start evidence review](start-evidence-review.md): a non-author reviewed the public original identity assertions, unique input, strict same-node progress and source predicates. Supports only scoped prospective start admission.
- [Completion evidence review](completion-evidence-review.md): a different non-author independently reviewed final original attachment proof, exact sRGB equality and preservation evidence. Supports separate scoped prospective completion admission.
- [Safety design review](safety-design-review.md): identifies the historical-profile promotion hazard and requires durable new-operation registration, strict scope and no legacy unlock/replay.

The public F packet is retained byte-for-byte under `../2026-10-28-system-screenshot-complete/`. These reviews did not newly access private PNGs, full target identities or raw SQLite. Their private-data provenance is the original handed-off non-author private evidence review; no report here claims otherwise.

## Implemented boundary

The original v1 screenshot profiles remain unadmitted. New independent v2 start/completion profiles can be selected only for a registered new dispatch intent, bound to full operation/asset/attempt/hash/target, the production candidate store and active asset. First registration is transactional and nonce-distinguished; repeated append, stale actual state and corrupt/foreign markers refuse. Recovery and reconcile never register or input.

Scope is the existing reviewed v13 Chrome zh ordinary persisted-thread structure and original single-frame RGBA8 PNG; the implementation conservatively also requires noninterlaced PNG, with the existing 8 MiB/16,777,216-pixel bounds. The actual fully hashed upload descriptor supplies the verified header, in addition to early local preflight. No conversion or new transport occurs.

The existing Core/UI lifecycle persists real start and swallows quickly, then persists independently proved completion in the background without a second animation. The small Core addition only atomically guards first checkpoint registration; schema v3, migrations, state machine, receipt policy and UI animation are unchanged. Safe failure/retry and ordinary production remain closed.

The JS resource remains byte-identical to48574df, SHA-256 `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`. There is no relaxation of exact full-content proof or v9/v10/v12/v13 legacy observation.

## Verification and accurate continuation

Actual source/final CI and implementation review records will be added after the full macOS run; final accurate SHA and artifact are fixed by the PR #1 handoff. Do not substitute the old source CI for the new implementation.

Generated-fixture tests exercise new start→swallowed→read-only restart→independent succeeded, independent policy maps, legacy F-style valid attached/start remaining UNKNOWN and locked, malformed/foreign registration, full identity mismatch, concurrent first enrollment, duplicate append rejection, scope refusal and private-file integrity. The packaged software self-check retains explicit CHROME_NOT_RUN / SYSTEM_SCREENSHOT_NOT_RUN / GUI_NOT_RUN labels.

The new candidate App still needs one actual Mac experience with **another new system screenshot**. F and all older UNKNOWN are never re-input, cleared or unlocked. Old read-only observations may update their last receipt/reason; immutable identity, attempt, UNKNOWN status, visibility and dispatch lock are preserved by the admission boundary. See [the precise local Codex entry](../../../docs/SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md).

PR #1 stays Draft. No main merge, public release, extension requirement or ordinary-production admission is included.
