# Feedback cloud continuation — 2026-10-29

## Current checkpoint — 14:17 UTC

**The business Receiver is deployed and 36 scoped real HTTPS checks passed. Two original reports have independently observed D1 records. Delivery has not been created, Host remains nil, private-Issue delivery/permanent deletion and native-window end-to-end acceptance remain NOT_RUN.** The user is logged in to the correct account. A prepared Codex Mac handoff is not an assigned or scheduled executor.

This increment descends from the actual unified PR #15 source `c15fd4b4a27659946ef49280131e875f4d5ab9d1`. It preserves Main, Package, native Feedback behavior, Capture, Core, Adapters, SQLite v3, screenshot admission and old UNKNOWN. The source admission and final new macOS workflows still need to bind the completed increment; previous c15 CI must not be relabeled as new-source CI.

## Actual Receiver deployment and remaining version check

- Receiver: `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`. The business bundle version prefix `07497aa3` was observed active. Secret/flag changes followed; the final full active version is still pending a fresh platform read, so that prefix is not presented as the final immutable deployment ID.
- Account: `b10365c5c641bd88cb1b9f35a4172d37`; dedicated D1: `riftlet-feedback`, ID `4167f4a2-5dfd-422d-86ca-077176fc8600`. The schema, trigger and reviewed indexes are initialized; observed limits are 100/day and 20/hour/IP bucket.
- Actual saved Receiver settings: correct `DB` binding; Logs, Traces and Issues OFF; `ACCEPT_ENABLED=true`; a random 32-byte `IP_HMAC_KEY` installed as a server Secret. Its value is never included in this evidence.
- Actual route/config: public workers.dev and compatibility date `2026-10-29`. The Receiver Wrangler declaration is now aligned to these actual values. Delivery remains an undeployed disabled declaration dated `2026-10-28`; the final active Receiver version still needs a platform read.
- Delivery does not yet exist. Its cron, D1 binding, external delivery, retention execution and final version are NOT_RUN/unconfigured.
- A fine-grained GitHub credential was created for only `haohongfei2001-png/Riftlet-Feedback`, with Metadata read and Issues write, expiring `2026-11-28`. It exists only in the authorized browser session and is not installed in Delivery. Creation and permission metadata do not prove installation or Issue delivery.

Since approximately 14:04 UTC, browser-control calls repeatedly returned MCP timeouts. At 14:12 the latest result is **`No connected browser was found`**. Control-plane reads/deployment are BLOCKED by the absent connected browser, not the already functioning HTTPS receiver or user authorization. Restore the same authorized connection and first read the saved state; do not duplicate the D1/Receiver or ask for account permission already granted.

## Real HTTPS and independent D1 evidence

The public [HTTP event snapshot](live-http/events.jsonl), [identity/digest map](live-http/identities.json) and [scope/count summary](live-http/summary.json) preserve **39 events: 36 completed HTTP checks and three separately recorded drop attempts**. The 36 checks comprise five send/duplicate checks, eighteen validation/identity checks, four deletion-response checks, one separately authorized read-only lost-receipt status GET, three cleanup DELETEs and five final read-only status GETs; all passed their stated HTTP/schema expectations. Expected 4xx rejections are successful validation checks, not accepted reports. These are service-script checks with synthetic diagnostics, not real native-window or real-business-event diagnostic acceptance.

[The original D1 Console record](d1-first-receipts.json), observed at **14:00:19.183Z**, independently confirms:

| Synthetic case | Original feedback ID | Observed D1 state | Payload SHA256 |
| --- | --- | --- | --- |
| plain | `6b8a8849-6ffc-4805-ae4e-e37cfa00f342` | pending; no Issue; payload present | `359fc12aea66375f9e30ec979e4cc1195805d21800301801531600483237f01b` |
| diagnostic | `0fa0a07f-76d3-4815-bee3-22f60dcdbdcb` | pending; no Issue; payload present | `72b7d9f0acb1b5b5d9a34c8397f4c84e9980bec9f8e051c93d239636dfbf7e4e` |

That query predates later tests. It is not a final total-row count or proof of those later cases. The earlier 13:25 observation of zero rows remains historical.

### Dropped original response: preserve all three outcomes

All attempts use original ID `083ca5ca-d1f4-44f6-9a3e-1c32f8850cc9` and payload hash `5ba81029befc2af2c5dd7384ceba150b1a4a7d856e3d1691bcc092f1e2be4b9e`.

| Attempt UTC | Actual local result | Remote conclusion at 14:12 |
| --- | --- | --- |
| 13:53:13.088343 | `gaierror`; request bytes were not written; no receipt read | This is a failed transport attempt, not a persisted request with a lost receipt. |
| 14:01:17.074152 | Bytes written, connection closed immediately, no receipt read | [Independent Console observation](d1-immediate-close-no-row.json) found no row. Do not call it D1 success. |
| 14:06:45.889277 | Bytes written, fixed 3,000ms hold completed, no origin receipt read | At 14:11:33 a separate authorized GET returned 200/received/durable=true. Independent D1 hash/count remains pending; local bytes alone did not prove receipt. |

No original-feedback retry has been executed at this checkpoint. The 14:11:33 read-only GET is new received-status evidence for the original identity, not a retry and not a replacement for direct D1 hash/count. Never manufacture a new identity or overwrite the earlier failed/no-row observations.

### Four actual deletion-response checks, separate from deletion completion

At 14:07:51, `delete_before_submit` ID `bd84bc6b-905b-4835-8a2e-277896131723` received HTTP202/deleted for authorized DELETE, and again deleted for the late original POST. At 14:08:02, `pending_delete` ID `35bc1586-1b37-41ed-b6e5-87221bd6a3d2` received HTTP202/received and then HTTP202/deleted. These are real Receiver responses. Direct D1 proof of one content-free authorized tombstone/null payload and permanent private-Issue deletion has not been obtained; **no complete deletion CLOUD PASS is claimed**.

## Authorized cleanup and remaining independent verification

| Case | Original ID | Obligation at this checkpoint |
| --- | --- | --- |
| plain | `6b8a8849-6ffc-4805-ae4e-e37cfa00f342` | Cleanup DELETE202/deleted; final GET200/deleted. Direct D1 null payload/flags/tombstone verification BLOCKED. |
| diagnostic | `0fa0a07f-76d3-4815-bee3-22f60dcdbdcb` | Cleanup DELETE202/deleted; final GET200/deleted. Direct D1 verification BLOCKED; diagnostics were synthetic. |
| lost_receipt | `083ca5ca-d1f4-44f6-9a3e-1c32f8850cc9` | Earlier GET received, then cleanup DELETE202/deleted and final GET200/deleted. No retry-dropped. Direct D1 final verification BLOCKED. |
| delete_before_submit | `bd84bc6b-905b-4835-8a2e-277896131723` | Final GET200/deleted. Independently verify D1 null payload/delete_requested/unique tombstone/no Issue; retain normal tombstone policy. |
| pending_delete | `35bc1586-1b37-41ed-b6e5-87221bd6a3d2` | Final GET200/deleted. Independently verify active payload NULL and original deletion state; do not infer backup erasure. |

At 14:16:42–43 the original plain, diagnostic and lost_receipt IDs each received DELETE202/deleted; at 14:16:54–55 all five original IDs received GET200/deleted. No new POST, retry-dropped, identity or Issue was created. HTTP cleanup is complete within that explicit scope; final direct D1 payload-null/flags/unique-tombstone verification remains BLOCKED by the disconnected browser. Do not replay these deleted identities or reset their tombstones for a later Delivery test. Original per-feedback credentials remain temporarily in private 0700/0600 state, as requested for final verification/cleanup; no credential value or private state is part of the public snapshot. Root must remove only that exact temporary state when it is no longer required, without claiming secure physical-media erasure. No native SQLite/Keychain cleanup, GitHub permanent deletion or D1 backup/Time Travel erasure is claimed.

## Next already-authorized work

1. Reconnect the authorized browser control; read final Receiver active version and saved configuration. Reuse existing resources.
2. Independently query all five deleted original test IDs in D1 without raw credential/body dumps; confirm final payload NULL, deletion flags, unique tombstones and no Issue identity. Preserve every earlier observation and do not retry/reset these deleted identities.
3. Create/reuse only the dedicated cron-only Delivery Worker, install the existing minimal repository credential as a server Secret, keep logging off, verify private destination and exact cron/settings, then execute the actual private-Issue delivery and unknown-result/deletion tests.
4. For any later newly authorized independent delivery tests, record their own Issue number/node ID and cleanup evidence. This completed HTTP cleanup created no Issue; never resurrect its five deleted identities, reset attempting/uncertain to pending, or treat Issue closure as permanent deletion.
5. Only reviewed same-deployment Receiver/D1/private-Issue evidence permits applying the separately reviewed one-line actual Host URL candidate. Commit the full source, obtain exact non-author review, update only the established final source pin/metadata, and run the complete existing macOS workflows and unified Beta packaging.
6. Keep [the Codex real Mac handoff](CODEX_REAL_MAC_E2E.md) prepared. No executor has been scheduled, and the true native-window E2E remains NOT_RUN.

[deployment-checkpoint.json](deployment-checkpoint.json) contains the exact current values and preserved old checkpoint. [Minimum operations](MINIMUM_OPERATIONS.md) and [deployment reconciliation](DEPLOYMENT_RECONCILIATION_CHECKLIST.md) separate saved configuration, declarations and unexecuted work. Existing 21 service / 13 packaging local tests and source reviews remain valid only for their recorded software scope.

## Historical provisioning narrative — superseded by the 14:17 checkpoint

The following original narrative preserves the earlier bootstrap/zero-row/unsaved-settings state and associated failures. Its descriptions of “current”, “not deployed”, “no secret” or “remaining” apply only to that earlier checkpoint, not to the live Receiver documented above.

### Current acceptance boundary

**IMPLEMENTED / local regression PASS; cloud provisioning PARTIAL; real cloud pipeline BLOCKED; physical Mac NOT_RUN.** The user is logged in and explicitly delegated the Mac connection/GUI acceptance to Codex. This checkpoint does not declare native-to-cloud delivery complete.

This isolated increment descends from the actual current unified PR #15 source `c15fd4b4a27659946ef49280131e875f4d5ab9d1`; it does not replace Main, Package, native Feedback, Capture, Core, Adapters, screenshot SQLite v3 or any upload admission. PR #1 remains Draft at `0e7ea8be148e1124b387e799fd886a7830e96559`, and main remains `eba1a4fc77648a665e1d5c1f2609df1314c3b079`. Final reviewed source/head and exact new CI are pinned in this increment's PR and the existing final-product source-admission records.

### Actual code repair and independent review

Non-author reviewer `/root/deployment_review` reproduced a previously untested starvation defect: nine older uncertain reports can alternate within the fixed GitHub budget forever, leaving the ninth report and a new pending report untouched at real five-minute tick intervals. Delivery now orders by `checked_at,created,id`. Unknown outcomes remain observation-only; there is no second automatic POST. The new regression fails on the original ordering, passes on the actual repaired source, visits all nine uncertain rows and posts the new report exactly once by tick 2, while every invocation uses at most 42 requests in this fixture.

Three indexes bound expiry/quota/tombstone cleanup as retained rows accumulate. They do not change retention or deletion semantics. The independent combined service execution passed **21/21**, with exact reviewed blob hashes and original failure/pass logs preserved here. These tests use real SQLite plus mock GitHub; they are not CLOUD PASS.

The package manifest now derives the feedback configuration from the committed Host source at `sourceHeadSHA` and checks it against the package's original build-input objects. It distinguishes `local-outbox-only` from `https-receiver-configured`; neither label asserts receipt, delivery or processing. Wrong domains, unsafe URLs, coerced booleans and invented success claims are rejected. The four packaging files received non-author review and **13/13** regression PASS. The proposed Host placeholder was deliberately not applied: actual Host stays `nil`.

`services/feedback/acceptance/cloud_acceptance.py` is the reviewed bounded real-HTTPS acceptance harness, not another feedback implementation. It preserves five independent synthetic report identities/capabilities privately and separates HTTP responses from independently observed D1/Issue evidence. No live feedback request was sent in this checkpoint.

### Actual external work

- Authenticated Cloudflare inventory showed no D1 databases and no Workers projects before provisioning; no pre-existing Feedback service was duplicated.
- Created the dedicated `riftlet-feedback` D1 database `4167f4a2-5dfd-422d-86ca-077176fc8600` in account `b10365c5c641bd88cb1b9f35a4172d37`. The actual free-tier inventory showed the free hard quotas; no paid upgrade was selected.
- Applied the existing schema and reviewed indexes to that dedicated database. Actual Console queries confirmed all three application tables, five indexes and the quota trigger. At **13:25:39 UTC**, limits were **100/day, 20/hour/IP bucket**, with **zero feedback rows**.
- Created `riftlet-feedback-receiver`. At **13:38:09 UTC**, a real unauthenticated HTTPS GET with the existing harness's honest `Riftlet-Cloud-Acceptance/0.1` User-Agent returned HTTP 200 and exactly **Hello World!**. This proves hostname reachability only; the business receiver is not deployed. The earlier default Python client returned 403/1010, which is retained in the checkpoint; no security protection was disabled to obtain the later result.
- The receiver Settings page contains a Logs-off / DB-binding draft. The attempted `ACCEPT_ENABLED=false` save and final persisted settings could not be confirmed because the Browser connector subsequently returned **MCP request timed out**, including on reconnection. This is a browser-control transport blocker after successful login, not evidence of missing platform permission.
- Re-read the existing GitHub destination: repository `1437354611`, `haohongfei2001-png/Riftlet-Feedback`, remains **private**. No new repository, feedback Issue, service token or accepted feedback was created in this continuation.

See [deployment-checkpoint.json](deployment-checkpoint.json) for exact observed values and uncertainty. Config files now contain the verified account/database IDs but remain fail-closed declarations; they do not assert the unfinished dashboard state is deployed. In particular the checked-in receiver still has `workers_dev=false`, while the bootstrap hostname currently exists. Resolve that actual route/config difference when deploying the reviewed business code.

### Remaining execution, already authorized

Restore the same browser-control connection, inspect saved state first, reuse the existing database/receiver, replace the bootstrap with exact reviewed receiver code, install only its HMAC secret, create/reuse the separate cron-only Delivery Worker, and install its repository-only Issues credential. Keep request/body logging disabled. Then run the existing real HTTP/D1/private-Issue/unknown-result/deletion checks, retain deployment versions, and clear each test record or explicitly preserve its deletion obligation. Only successful reviewed cloud evidence permits changing the App's exact HTTPS endpoint literal and rebuilding.

The short-lived, single-synthetic-ID GitHub 201 response-discard proposal was independently reviewed offline, but **not deployed**. It is not included in ordinary production code. Real acceptance must preserve the temporary and restored deployment identities and never reset uncertain rows to pending.

[Minimum operations](MINIMUM_OPERATIONS.md) and [deployment reconciliation](DEPLOYMENT_RECONCILIATION_CHECKLIST.md) describe this same service and its exact unfinished state. [Prepared Codex Mac acceptance](CODEX_REAL_MAC_E2E.md) covers the real unified native window, IME, Keychain, restart, diagnostic consent, deletion and screenshot isolation. No later automatic executor has been scheduled; the document is a handoff, not proof that Codex has run it.

The previous `c15fd4b` native workflows [40868965979](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40868965979) and [40868966041](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40868966041) were independently re-read as SUCCESS in this continuation. They cover that prior source, not this new increment. New exact-head CI and unified App artifacts must be recorded after source admission, without relabeling software AppKit as physical Mac acceptance.
