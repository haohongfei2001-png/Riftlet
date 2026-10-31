# Real Feedback cloud checks — operator notes

This is an acceptance harness for the existing service, not a second receiver.
It does not access the browser, Cloudflare credentials, GitHub credentials, Mac,
screenshots, or real user feedback. Root alone owns deployment and shared code.

`cloud_acceptance.py prepare --state-dir <new-private-directory> --endpoint <exact-https-/v1/feedback>` is offline. It creates five explicitly synthetic reports, each with a distinct random UUID and 32-byte capability, in a 0700 directory / 0600 file. Never commit that directory. `show` emits IDs and payload hashes only.

Once the real service is reviewed and enabled, each command below is explicit:

1. `send`: four overlapping real POSTs of the same plain report, then one opted synthetic-diagnostic report. This is not a native-window or real-business-diagnostic test.
2. `validate`: requires the owned plain report to exist first, then checks forbidden fields, diagnostic shape/count/length, text/envelope size, invalid ID, tampered original body, wrong credentials for all three methods, malformed credentials, wrong media type, content encoding, and query rejection. It finally checks the original report remains accessible. At most 18 requests; no new accepted report is intended.
3. `drop-response`: writes the original lost_receipt HTTPS request using the same standard HTTPS proxy/NO_PROXY and verified TLS policy as normal requests. After the complete request is written it keeps the connection open for a fixed three seconds without reading any origin response, then closes it. The result is deliberately UNKNOWN; neither bytes written nor the bounded wait proves persistence. Run `status --labels lost_receipt` and independently read D1 before `retry-dropped`; if the request did not persist, do not claim the durable-but-unacknowledged scenario passed. Exact retry never changes ID, bytes, or capability. Preserve failed and uncertain attempts in the evidence.
4. `delete-before-submit`: authenticated DELETE establishes the capability-bound tombstone, then the original POST must return `deleted` rather than resurrect content.
5. `pending-delete`: accepts a separate synthetic record then requests deletion. If the cron races, a `deletion_pending` result is honest and creates an Issue-cleanup obligation; it is not local cancellation.
6. `status --labels ...`: records actual authenticated GETs. No polling or autonomous retry is hidden in the script.
7. `d1-query`: emits read-only SQL restricted to the five exact test IDs. Run it against the verified dedicated remote database. Preserve actual query output, database identity and UTC capture time separately. Neither HTTP202 nor this query's generation proves persistence.
8. `verify-issues --repository-json <actual-repo-json> --issues-json <actual-issue-list-json> --evidence-source <actual-tool/capture-time> --complete-state-all-listing --labels plain diagnostic lost_receipt`: verifies repository1437354611 is Private and finds exactly one Issue per marker with exactly the expected untrusted-text/diagnostic body. The required completeness flag is an explicit operator assertion: use it only after fetching actual `state=all` pages through the final page and preserving evidence there is no next page. A selected Issue subset or search result cannot prove uniqueness. This checks supplied actual GitHub observations, not the delivery's original201 response.
9. `delete --labels ...`: only after receipt/D1/Issue observations are preserved, request removal. An Issue already created or possibly created must stay deletion_pending until the authorized owner permanently deletes it and the independent check proves removal. Close/edit is not deletion. Root must preserve the final D1 tombstone and document platform backup residuals.

Every network operation records a sanitized timestamp/status/duration/contract response in events.jsonl. It never prints the bearer value, submitted body, platform tokens, or arbitrary provider error messages. Redirects are rejected. Transport exceptions remain unknown outcomes. Checks are scoped to HTTP or supplied observations, never MAC PASS or full native E2E PASS.

## Required deployment evidence outside this script

- Exact account/database and deployed receiver/delivery version identity; receiver's awaited real D1 commit.
- Private repository and minimum-scope server credential; no receiver GitHub credential; logs disabled.
- Real scheduled dispatch; original HTTP201-bound delivery evidence and one matching private Issue.
- Quota rollback under a deliberately controlled dedicated test limit; restore the previous limits afterward.
- GitHub response loss must be injected at the actual outbound response/commit boundary. Manually rewriting an already-known delivered row to uncertain only tests reconciliation from a reconstructed state; it is not evidence of a lost response.
- A test-only delivery deployment can discard the real target report's201 before parsing/updating D1, then be replaced by the exact ordinary deployment before reconciliation. Use an exact single synthetic UUID selector, retain both version hashes, and remove the test instrumentation afterward. No public control endpoint or general bypass is required.

## Already checked locally

Python compilation succeeded. Offline preparation produced five unique payloads/capabilities; every payload passed the repository's actual contract.mjs validator and the state file was0600. No network request was made. Shared checkout remained clean at65c67804f0d049a25aa947c9104410b20e46c94e.

The saved `offline-selfcheck` identities are only a harness self-check. Prepare a new directory with the actual deployed endpoint for live execution; do not edit its endpoint or reuse it as fabricated cloud evidence.

## Reproducible offline transport boundary checks

`python3 -B -m unittest discover -s services/feedback/acceptance -p 'test_*.py' -v` executes four synthetic checks without opening a network connection. They cover the standard proxy/NO_PROXY behavior, CONNECT credential separation, fixed post-write linger with no origin-response read, and truthful failed-write flags. Real HTTP and direct D1 observations remain separate.
