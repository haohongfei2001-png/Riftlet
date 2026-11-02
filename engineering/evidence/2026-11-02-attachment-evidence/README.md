# PR #35 attachment proof implementation

Base main: `a4463cddd3bce637dbe0a33c90713bc42370ed8f`.
This continues source `461e6455` / admission `0212247` on the same Draft PR.
The exact source G and admission-only H are recorded by the successor
`engineering/mainline/source-admission.json`; source review and CI are not real
ChatGPT acceptance. No user database, media, UNKNOWN, main ref or release changed.

## Implemented

- Versioned COMPLETE produced by the actual page's existing exact-byte/exact-sRGB
  proof, bound through native normalization and SQLite to the original dispatch
  invocation, full target, asset, attempt and attachment. Ordinary product profiles
  require it; historical observations are not retroactively upgraded.
- Exact original-File fetch/XHR call facts, with no URL/body/header capture and no
  guessed Blob/FormData/worker lineage. Fetch never observes its Promise. XHR
  never touches `upload`, avoiding an additional CORS preflight trigger. These
  request facts do not grant START, COMPLETE, termination or continuation.
- Versioned platform finalization, irreversible retirement and independent-task
  contracts wired through native consumers. Separately admitted task ownership
  survives UNKNOWN/restart; unadmitted candidates cannot reserve aliases or poison
  later valid evidence. Cross-pin request/task/reference aliasing is rejected.
- Continuation v2 is original-live-append only and cannot be admitted later by
  replaying a START or widening policy. Retirement permits only a new user click.
- Existing G3 observers upgrade on a fresh capture without replacing their old
  operation records. New code rejects staged old-protocol chunk/commit, while an
  already-entered original asynchronous commit is not canceled or replayed.

## Actually executed before source freeze

| Check | Result | Scope |
| --- | --- | --- |
| Current page VM | PASS, 151 cases | Deterministic source execution, no live site |
| Legacy page VM | PASS, 61 cases | Archived observe-only compatibility |
| Headless Chromium | PASS, 7 cases | Real File/XHR/fetch/PNG/canvas APIs, all URLs intercepted; [exact results](headless.json) |
| Local full Swift build | PASS | ARM64 CLT build; no App/UI/Chrome launch |
| Added Core + adapter contract tests | Await formal macOS CI | 18 Core + 7 adapter cases, plus journal and App policy regression; parsed locally |

Review findings were fixed before freeze: Promise rejection-observation side
effects, XHR upload-listener preflight side effects, old-observer upgrade, staged
old-protocol input, unadmitted task ownership and later START promotion. No old
assertion was weakened, no test was skipped and no source admission was bypassed.

## Exact remaining gaps

**These three requested platform capabilities are not yet complete.** The existing
public-safe real evidence proves an original File/XHR body correlation, not a
stable platform attachment ID plus finalized original. No authorized current
ChatGPT response/schema proves irreversible task retirement or independence from
a subsequent composer input. This increment does not invent those facts.

Resized previews remain UNKNOWN under the unchanged exact comparison. Post-input
safe retry and Web continuation remain closed. The original byte and pixel limits
are unchanged; no extension, page-access bypass, real upload or historical replay
was performed. Platform-finalization/termination profile maps are empty. The new
platform contracts have only explicitly synthetic protocol fixtures, not a real
producer or real network acceptance.

See [the implementation contract](../../../docs/ATTACHMENT_EVIDENCE_V1.md).
The next required fact is a permitted, exact original-file→platform-attachment→
final-processing association; terminal retirement and independent-task semantics
need their own evidence. CI success cannot supply it. Do not merge or release this
as the completed product.
