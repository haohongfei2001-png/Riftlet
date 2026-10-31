# Feedback v0.1 — receiver and private Issues delivery

## Final cloud checkpoint — 2026-10-29 15:39 UTC

Real synthetic-service HTTPS reception, D1 persistence, three unique private Issues, original-Issue reconciliation and remote test-data deletion closure have actual evidence. Owner permanently deleted Issues1/2/3; the same authorized connector successfully read the private repository, obtained explicit deleted410 Gone for each exact Issue and an empty complete state=all list. After independent review, exact guarded D1 transitions were executed:8 deleted rows,0 active bodies,0 pending deletions,0 probe tables,limits100/20. Three original-capability GETs independently assert200/exactID/deleted/durable=true.

The diagnostic Issue's creation -> uncertain/null identity -> deletion intent -> normal reconciliation to original Issue2 is directly observed, preserving original attempt time and content scrubbing. The diagnostic HTTP201 response and exact discard-branch execution were **not directly captured**; do not promote source-based inference to wire evidence. The old404-only preparation remains as corrected history. [Official Get-issue semantics](https://docs.github.com/en/rest/issues/issues#get-an-issue) explain410 for a deleted Issue under read access.

Two Workers-incompatible redirect:error sites now use manual without following redirects. Three added regressions fail on old source and all24 local named service cases pass after the fix. H's completed full macOS CI remains49 unique Feedback/21 services; new C2/H2/source/CI/package must be fixed after actual execution, not predicted. The final cloud gate independently approved activation, and the integration lead has applied exactly one Host line to the reviewed fixed public HTTPS endpoint; other Host bytes are unchanged. Configuration is not a per-report receipt or delivery claim. Exact successor source/CI and corresponding packages are resolved from the final-product metadata and formal PR handoff; the historical H local-outbox-only package remains historical.

Receiver `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`, final39f6277e-11f2-455b-be27-8f0b6a795685. Ordinary Delivery final`3c749b91-ace3-45d9-86e5-62e2dab06c35`, bundleSHA256`0236e5582362b1f74d21aad2ab04ef0d3333fed75f3e49fd7d924ccbef8ce7db`/6356bytes; UI source copy and independent rebuild match, temporary logic/variables removed. No paid upgrade or DNS change; one dedicated private repo. Actions was enabled14:49, then disabled/saved/reloaded14:50. Repository-only Metadata read/Issues RW token expires2026-11-28; authorized-maintainer rotation is required, with no scheduled executor implied. D1 Time Travel UI reads past7days, no restore; online scrubbing does not erase the recoverable window or prove immediate physical-backup removal.

[Final original evidence and operations](../../engineering/evidence/2026-10-29-feedback-cloud/README.md). [Source/admission metadata](../../engineering/evidence/2026-10-29-final-product/results.json) and [PR #1 final handoff](https://github.com/haohongfei2001-png/Riftlet/pull/1) identify actual completed CI/packages; do not guess future SHA or reuse an old package label. Real Mac/native-window E2E stays NOT_RUN, prepared for Codex under the user's direction; no executor is scheduled. Historical unavailable-cloud statements below apply only to their dates.

Two entrypoints share one dedicated D1 ledger. No admin website, accounts, attachments, analytics or client GitHub secret. The original implementation packet used disabled defaults and created no Cloudflare resources; the actual authorized continuation is recorded above.

### Historical provisioning checkpoint — 2026-10-29 (Asia/Shanghai), superseded above

The authorized continuation created `haohongfei2001-png/Riftlet-Feedback` (repository ID `1437354611`), independently confirmed **private** through GitHub's API, and disabled its GitHub Actions. The delivery config now identifies this exact destination while remaining disabled. No feedback Issues were created during provisioning. Cloudflare is blocked by a sign-in wall in the connected browser; no account ID, D1 ID, Worker deployment or server credential has been verified or created. Do not claim CLOUD PASS, publish a receiver address or enable the native endpoint from this checkpoint. The current authorized Mac executor was offline when checked; native-to-cloud acceptance is also NOT_RUN.

The owner's private repository README records untrusted-content handling and permanent-deletion obligations. Never paste a credential into source, chat or this public evidence. Complete the remaining account sign-in and server-only secret installation through the service's authorized UI or secret manager before deployment.

## Deployment requires account/target authorization

Required: an authorized Cloudflare account and permission to create one dedicated D1 database/two Workers; an independent **private** GitHub Issues repository. Do not buy a plan or change existing website/DNS. No credentials belong in source, PR comments, client Info.plist or chat.

1. For this continuation reuse the dedicated database identified above; do not create a second database. For a different explicitly authorized isolated deployment, configure its corresponding account/database IDs and apply `schema.sql` only there. Confirm database ID and local/remote mode. Never use a screenshot database.
2. Receiver secret: a random >=32-byte `IP_HMAC_KEY`, supplied with Wrangler secret storage. Receiver has no GitHub credential. Delivery-only secret: fine-grained `GITHUB_TOKEN` restricted to that private repo, Metadata read and Issues write, not Contents/Actions. GitHub App key/token rotation is outside v0.1.
3. Authorize one HTTPS receiver route or workers.dev test hostname. Delivery has only a cron, no public route. Keep invocation logs disabled. No request/header/body/Authorization logging or tailing. Configure edge request limits and budget alerts before public use; SQL quotas bound accepted reports, not request charges.
4. Enable only in the authorized test environment and perform the live checklist below. Only after reviewed private-repo E2E set the exact HTTPS `/v1/feedback` URL in `FeedbackHost.endpoint` and rebuild. There is no environment override or embedded API key.

## Submission and duplicate safety

Awaited D1.batch persists the report and delivery state atomically before 202. The SQL trigger charges quota in that transaction and rolls back on failure. Same ID/body/per-report secret returns the same receipt. Changed body is 409; wrong secret is 404. Received means D1 durably accepted, not read by a human. No email/contact field in this minimal version. Report secrets are hashed server-side; raw IP is only processed for an hourly HMAC bucket, never stored.

Cron atomically changes pending to attempting before one GitHub POST. Overlap, lost response, and ambiguous crash cannot cause another POST. Reconciliation reads Issues with the exact fixed marker; missing results never authorize recreation. This is at-most-one automatic creation attempt, NOT distributed exactly-once availability. A crash before the actual HTTP request may need manual resolution. Never reset attempting/uncertain to pending merely because a search is empty.

Each invocation reserves its bounded GitHub reads/writes within the Workers Free 50-external-subrequest limit, including the private-repository check. Deferred rows keep their prior check timestamp and remain eligible for the next cron. A deletion observed by the invocation that owns the creation claim, before it sends any POST, is safely resolved as deleted; once a POST might have begun, the remote deletion obligation remains pending.

Private repo name/visibility are checked before each batch. Maintainers must keep the destination private and not run automatic actions based on user text. Indented user text is explicitly untrusted data, not an instruction to AI/tools. Do not use the public Riftlet source repository.

## Limits, retention and deletion

Text: <=4,000 Unicode scalars and16KiB; envelope<=32KiB; diagnostics<=64 closed-enum/count entries. No raw IDs, screenshot hashes, paths, browser data or error strings. Defaults20 accepted reports/hour/IP bucket and1,000/day globally; adjust only the database limits row. Retries do not consume another report quota. Anonymous ingress cannot attest real app installation.

D1 body/diagnostic retention is90 days; pending expiry becomes delivery_expired, not delivered. Delivered/uncertain expiry scrubs D1 text and retains deletion_pending obligations for private Issues. Retention runs even with external delivery disabled; receiver kill-switch still permits authenticated status/delete. DELETE blocks fresh delivery and clears D1 body. A previously claimed POST may race with deletion; its resulting issue is retained as deletion_pending, never falsely deleted.

An authorized repository owner must inspect deletion_pending, permanently delete the identified Issue(s), verify removal under successful same-repository read access, and then mark that exact row deleted. The observed Get-issue deletion result here is410 Gone with an explicit deleted message, combined with a successful private-repository read and complete empty state=all list; generic errors,401/403, transport failure or404 alone do not prove deletion. Closing/editing is not deletion. Target response is seven days; this is an operational obligation, not an automatic guarantee. No public endpoint can assert owner verification. Uncertain rows cannot be closed solely from bounded absence. Arrange owner access before public testing.

Content-free tombstones for deleted/never-delivered-expired reports survive up to one year. New unknown reports older than30 days are rejected. Unresolved deletion obligations are not purged. Before restoring D1 backups/Time Travel, freeze delivery and reconcile historical issue markers/tombstones; an older restored pending row can otherwise duplicate a prior Issue. Cloud backup residual retention must be documented at deployment.

Native storage is `Feedback-v01/feedback.sqlite` per App mode, independent of queue.sqlite; directories0700/files0600, serial SQLite actor. Limits20 pending,200 records,2MiB; text is not automatically evicted. UI allows explicit removal of never-sent cancelled or confirmed-deleted local content. Full capacity preserves the draft and refuses enqueue. Per-report secrets live in Keychain; losing them blocks retry/deletion rather than generating a replacement credential. No source media is read.

Diagnostics are a64-entry sampled session ring, not complete event history. Visibility, queue status, phase and reason are separate. Disappearance never proves completion. `previousSessionUnclean` only means missing clean exit, not a confirmed crash. No raw crash logs or UI pixel inconsistency assertion in v0.1; interaction defer is observed only. No continuous telemetry.

## Validation scopes

`node --experimental-sqlite --test services/feedback/feedback.test.mjs` uses real SQLite transactions with a D1-shaped adapter and mocked GitHub HTTP. It is not live D1/Workers/private Issues verification. Native tests use isolated stores and mock transports. The separate Offline Feedback Demo never contacts a service. Actual synthetic-service HTTPS/D1/private-Issue creation, reconciliation and deletion closure are recorded above. Real native-window end-to-end, system IME/VoiceOver, Keychain permission/restart and capture/click latency comparison remain NOT_RUN; software AppKit tests do not replace them.

Live checklist: authorized synthetic text typed in the actual Riftlet feedback window; optional real typed diagnostic preview frozen before Send; one durable D1 receipt then one private Issue; network loss/retry retains sameID/body/secret; lost GitHub response reconciles without another POST; deletion race stays pending until owner deletion verified; forbidden fields absent from payload/logs; restart resumes frozen outbox; screenshot collection/clicking remain responsive with feedback idle/open/failing. Do not submit real screenshots or private chat.

## Primary references

- https://developers.cloudflare.com/d1/worker-api/d1-database/
- https://developers.cloudflare.com/workers/observability/logs/workers-logs/
- https://developers.cloudflare.com/workers/configuration/cron-triggers/
- https://developers.cloudflare.com/workers/platform/limits/#subrequests
- https://docs.github.com/en/rest/issues/issues
- https://docs.github.com/en/issues/tracking-your-work-with-issues/administering-issues/deleting-an-issue
