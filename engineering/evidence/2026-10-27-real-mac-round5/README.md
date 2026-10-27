# Round five — uploadStarted implementation, real admission pending

Checkpoint date: 2026-10-27. **The real fast-swallow product goal is not yet passed.** The new generated-image input has not occurred at this checkpoint. A single physical click was requested because computer-use exposes only the first independent micro-window (the preserved UNKNOWN); scrolling did not select the second new image. Do not mark preparation, build, or synthetic DOM tests as real upload start.

## Source and integration

- Branch: `codex/riftlet-real-mac-round5-20261027`.
- Exact tested source: `1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a`.
- Started from formal SQLite v3 `b84892071d7711177bb856051251a337f2c2c4f5`, inherited only the two round-four adapter commits, then merged the newer formal Pro integration `e89d49f763036781c90618422da256e03cbca2ac` when it became available. Original branches/worktrees remain intact.
- Core/UI/App match that newer formal baseline exactly. Pro capture request/publication diagnostics and persisted logical identity recognition are retained. No v2 Core/App was brought back.
- New source `e72e413ae3a43a9a7079ba15a5bd22d1d5a69974` supplies v9/schema2 and v8 read-only compatibility; the subsequent merge includes formal host diagnostics without dropping uploadStarted early return.

## Implemented

The v9 original-operation observer binds one actual input File hash to the exact original asset/operation/attempt/full target and unique attachment. It requires two numeric progress samples on the same original progress node, with `0 <= previous < current < 100`, the exact original upload label, original membership, no error, one input, and strictly ordered input/start times. A placeholder, change event, files alone or uploading boolean cannot grant start. Invalid/regressing/replaced progress, including intermediate changes coalesced into one Mutation batch, permanently cancels start eligibility without fabricating failure. Final image proof remains independent; internal final-proof time is diagnostic only.

Strict schema2 decoding rejects extra fields, incomplete evidence and permissions supplied by the page. Native code maps the candidate ID `chatgpt-web-zh-progress-start-development-20261027-v1`; Core policy still decides admission. `append` returns a valid start receipt early; later reconcile observes only the original operation. Old v6/v7/v8 operations return schema1 and cannot borrow start proof. No begin/commit replay, new target capture during reconcile, or retry grant was added.

The formal App synthetic start registry is still empty. [Acceptance overlay proposal](app-integration-proposal.md) and [minimal patch](app-acceptance-overlay.patch) are **unapplied** and independently reviewed. They add only synthetic-mode registration plus AppKit code-path diagnostics, not a new state machine. Apply only in a separate reviewed acceptance build after actual start evidence is independently assessed. UI timestamps are not rendered-pixel or exact SQLite COMMIT measurements.

## Verification

| Item | Result | Scope |
|---|---|---|
| Exact-source full macOS CI | PASS | [40487032921](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40487032921): 312 native tests, 61 page tests, 25 legacy tests; 13 lifecycle detailed passes; Release/signature/self-checks. |
| Local Release package | PASS | macOS 27.0 (26A428), arm64, Swift 6.4. |
| Independent implementation review | PASS | Strict decoding, native mapping/early return, read-only legacy route and limited overlay; no live admission. |
| v2→v3 existing Web store preservation | PASS | All 11 original assets/media hashes, 17 original operation identities and 3 compensation audits preserved; quick_check OK. See [migration evidence](migration-preservation.json). |
| Default registry rejects start visibility; explicit synthetic registry accepts | PASS | Native tests only; first audit retained through UNKNOWN and READY, wrong attachment rejected. |
| Early return then final observation with exactly one commit | PASS | Adapter fake bridge regression only. |
| Real Chrome v9 preflight | PASS, limited | Ordinary existing conversation; page focused, editor unfocused, one valid form/editor/file input, no blocking modal. No new input. |
| Real uploadStarted / start-before-final chronology | NOT_RUN | New generated asset still pending; minimum physical click requested. |
| Actual AppKit rapid swallow / READY without repeated animation | NOT_RUN | Await real start evidence and separately admitted synthetic composition. |
| Real start→network UNKNOWN / safe terminal rebirth | NOT_RUN | No new network or retirement proof. Safe retry remains disabled. |
| MID byte request interruption | NOT_EXERCISED | No new real request interception. |
| Cold click without ACK, business ABA, nonempty draft/selection preservation, physical pass-through | NOT_RUN | Round-four limited prebound success is not promoted. |

No system screenshot was uploaded; no ChatGPT message was sent. Existing UNKNOWN, media and audits remain. Migration legitimately hides old compensated assets using the formal v3 legacy rule; it does not create upload-start facts (zero upload_starts before the new input).

## Resume the concrete prepared test

Actual App runs the exact source above with `--web-acceptance --acceptance-trace`, default **unadmitted** start policy. The new asset is `029C66A3-178B-4184-8A0E-3060AA8C83C7`, a private copy of the prior purely generated 3,147,775-byte noise PNG, SHA-256 `494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`. This is a new asset/operation, not replay of an old UNKNOWN. The upper visible micro-window is old UNKNOWN; the second lower noise image is the new item. Do not click/re-input old UNKNOWN.

After the requested single click, inspect only this original operation: native raw selection/ACK chain, inputCount, actual increasing progress/start evidence, final proof timestamp, private SQLite receipt, and whether default policy retained visibility. Never infer a missed early receipt from eventual final success. Then review actual start evidence before creating a separate build with the limited synthetic overlay. Only a subsequent new generated asset may exercise admitted start→visual exit→background result. Keep first-start audit and independent final timing. No automatic retry.

Private local run files are `/tmp/riftlet-round5-no-grant.jsonl`, `/tmp/riftlet-round5-no-grant-store-private.jsonl`, `/tmp/riftlet-round5-result.js`; raw database receipts/full target identities must stay private. The bounded store monitor captures observed state transitions, not exact commit timestamps. The diagnostic logs are bounded; absence after their cap is not proof that an event did not happen. Retain existing root monitors and original browser operations; do not stop a monitor to manufacture new binding continuity.

Same-draft consecutive different images remain locked while the first operation is unresolved under the formal Core contract. The overlay does not relax this. A new target or timeout token must not be used to bypass the lock; Pro owns any separate change to that contract.
