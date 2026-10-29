# Feedback v0.1 — receiver and private Issues delivery

### Actual cloud checkpoint — 2026-10-29 14:17 UTC

The business Receiver is running at `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`. Business bundle version prefix `07497aa3` was observed active; the final active version after later Secret/flag changes still needs a fresh platform read. The dedicated `DB` binding is saved, Logs/Traces/Issues are off, `ACCEPT_ENABLED=true`, and a random 32-byte `IP_HMAC_KEY` is installed as a server Secret. Actual routing is public workers.dev, with compatibility date `2026-10-29`. The Receiver Wrangler declaration is now aligned to these live values; Delivery remains an undeployed disabled declaration with compatibility date `2026-10-28`. The final active Receiver version still requires reconciliation before claiming immutable deployment identity.

D1 `4167f4a2-5dfd-422d-86ca-077176fc8600` is initialized, with observed limits 100/day and 20/hour/IP bucket. An independent Console query at `14:00:19.183Z` confirms the original plain-text and synthetic-diagnostic IDs/payload hashes as two pending records, both without Issue identity. Real HTTPS checks passed **36/36 HTTP PASS**: the prior 28 checks, then three authorized cleanup DELETEs and five read-only final status GETs. At 14:16:42–43 the original plain/diagnostic/lost identities each returned 202/deleted, and at 14:16:54–55 all five original identities returned 200/deleted. These HTTP observations do not independently prove D1 payload-null/flags/tombstones or backup erasure; the required direct Console verification is BLOCKED by browser disconnection. Three drop-response attempts are preserved separately: DNS failure before write; immediate close after write with no D1 row subsequently observed; three-second post-write hold without reading the original receipt. At 14:11:33, a separately authorized GET for that original identity returned 200/received/durable=true; direct D1 hash/count verification remains pending. No dropped-request retry has run.

Delivery has not been created. A repository-only fine-grained GitHub credential with Metadata read / Issues write and expiry `2026-11-28` was created, remains only in the authorized browser session, and has not been installed in Delivery. No secret value belongs in source, chat or public evidence. After repeated MCP timeouts since 14:04, the latest 14:12 browser-control result is `No connected browser was found`. Control-plane work is BLOCKED by the absent browser connection after successful login, not missing account authorization.

The native Host remains nil. Private Issue delivery, permanent Issue deletion and native-window end-to-end acceptance are **NOT_RUN**, not CLOUD/MAC PASS. No retry-dropped, new identity or Issue creation occurred during cleanup. Preserve these five identities as deleted; do not replay them or reset tombstones. Their remaining obligation is independent D1 verification and appropriately scoped local private-state cleanup, not an unperformed HTTP deletion. Private test state remains 0700/0600 temporarily as requested; it is never committed. See [exact checkpoint, original HTTP events and operations](../../engineering/evidence/2026-10-29-feedback-cloud/README.md). Earlier HelloWorld, zero-row and unsaved-settings observations below are historical, not the current service state.


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

An authorized repository owner must inspect deletion_pending, permanently delete the identified Issue(s), verify removal, and then mark that exact row deleted. Closing/editing is not deletion. Target response is seven days; this is an operational obligation, not an automatic guarantee. No public endpoint can assert owner verification. Uncertain rows cannot be closed solely from bounded absence. Arrange owner access before public testing.

Content-free tombstones for deleted/never-delivered-expired reports survive up to one year. New unknown reports older than30 days are rejected. Unresolved deletion obligations are not purged. Before restoring D1 backups/Time Travel, freeze delivery and reconcile historical issue markers/tombstones; an older restored pending row can otherwise duplicate a prior Issue. Cloud backup residual retention must be documented at deployment.

Native storage is `Feedback-v01/feedback.sqlite` per App mode, independent of queue.sqlite; directories0700/files0600, serial SQLite actor. Limits20 pending,200 records,2MiB; text is not automatically evicted. UI allows explicit removal of never-sent cancelled or confirmed-deleted local content. Full capacity preserves the draft and refuses enqueue. Per-report secrets live in Keychain; losing them blocks retry/deletion rather than generating a replacement credential. No source media is read.

Diagnostics are a64-entry sampled session ring, not complete event history. Visibility, queue status, phase and reason are separate. Disappearance never proves completion. `previousSessionUnclean` only means missing clean exit, not a confirmed crash. No raw crash logs or UI pixel inconsistency assertion in v0.1; interaction defer is observed only. No continuous telemetry.

## Validation scopes

`node --experimental-sqlite --test services/feedback/feedback.test.mjs` uses real SQLite transactions with a D1-shaped adapter and mocked GitHub HTTP. It is not live D1/Workers/private Issues verification. Native tests use isolated stores and mock transports. The separate Offline Feedback Demo never contacts a service. Physical AppKit/IME/VoiceOver, Keychain permission/restart, deployed HTTPS/D1/private-Issue E2E and capture/click latency comparison remain NOT_RUN until actually executed.

Live checklist: authorized synthetic text typed in the actual Riftlet feedback window; optional real typed diagnostic preview frozen before Send; one durable D1 receipt then one private Issue; network loss/retry retains sameID/body/secret; lost GitHub response reconciles without another POST; deletion race stays pending until owner deletion verified; forbidden fields absent from payload/logs; restart resumes frozen outbox; screenshot collection/clicking remain responsive with feedback idle/open/failing. Do not submit real screenshots or private chat.

## Primary references

- https://developers.cloudflare.com/d1/worker-api/d1-database/
- https://developers.cloudflare.com/workers/observability/logs/workers-logs/
- https://developers.cloudflare.com/workers/configuration/cron-triggers/
- https://developers.cloudflare.com/workers/platform/limits/#subrequests
- https://docs.github.com/en/rest/issues/issues
- https://docs.github.com/en/issues/tracking-your-work-with-issues/administering-issues/deleting-an-issue
