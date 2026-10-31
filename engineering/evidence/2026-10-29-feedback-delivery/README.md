# Feedback v0.1 delivery continuation — 2026-10-29

## Actual starting state

Live GitHub inspection found PR #7 already merged at `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`. PR #1 was Draft at `1920e0562db893a3292af89a89270a26ddb46a5f`; main was `eba1a4fc77648a665e1d5c1f2609df1314c3b079`. The continuation uses an isolated worktree and branch `codex/feedback-delivery-20261029`, preserving that complete history. Main, screenshot data and the active Mac worktrees were not edited. Feedback is not merged a second time.

## Concrete repairs

- Release a firing retry timer's own handle before `pump()` invalidates timers; generation and stop guards remain. New tests wait for the real short timer without a second manual pump, for submission and deletion.
- Allow local cancellation only when durable attempts is zero and the record is still in a local queue/blocked state. Missing Keychain credentials never create a new identity; attempts greater than zero preserve cloud deletion obligations.
- Explicit `secure_delete=ON` in the existing independent DELETE-journal feedback database. Verify forgotten text disappears from the live file while other feedback remains. No claim about backups, snapshots or physical SSD erasure.
- Extend repeated window close/reopen coverage to diagnostics off/on/off; add software AppKit marked-text protection; explicitly identify the private feedback destination in the existing privacy sentence.
- Resolve deletion encountered by the unique GitHub claim holder before any POST. Deletes after the possible POST boundary still require remote deletion verification.
- Bound one cron invocation's GitHub requests to the free-tier limit, including private-repository verification; deferred records remain eligible on the next tick.

Only Feedback implementation/tests and necessary audit/configuration/packaging text change. Main, FeedbackHost, Package, Core, Capture, Adapters/Web, screenshot UI and their regression sources remain exact. `scripts/verify-internal-beta-integration.py` pins each reviewed changed Feedback blob individually while retaining every unmodified Feedback object and all original screenshot/UX/evidence anchors. Four new real-Git regressions reject unauthorized neighboring or approved-object changes.

## Verification and independent review

Three actual parallel agents performed native fixes, service fixes and non-author review, with the root as sole shared-code/ref integrator. Non-author review approved the concrete source/test changes and exact-file audit implementation. Details: [review.md](review.md).

Local execution: 20 real-SQLite/mock-HTTP service tests, 14 updated integration-isolation tests, four original Feedback isolation tests and seven package tests passed. The two added service regressions were first run against the old implementation and failed as expected (permanent deletion_pending and 101 external requests). The exact 14-file pure Feedback subset at `2d517411` additionally passed 30 tests on official Swift 6.2.1 / Linux; the log, source-object manifest, command and scope are in [linux-logic-verification/](linux-logic-verification/). This does not cover AppKit or real Keychain. New macOS results still await actual CI at this source checkpoint. The final exact SHA, source/checkout relationship, new CI runs, unique counts and downloaded unified Beta verification are fixed in the continuation PR and [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1), not inferred from older CI.

The original eight PR #7 review findings were individually verified already fixed and all eight threads were resolved. [Closure evidence](https://github.com/haohongfei2001-png/Riftlet/pull/7#issuecomment-6475173610). The new timer and cancellation fixes are separate findings, not retroactively attributed to the old passing tests.

## Real external state and acceptance boundary

The authorized continuation actually created the independent private repository `haohongfei2001-png/Riftlet-Feedback`, ID `1437354611`; GitHub API independently confirmed `visibility=private`. GitHub Actions was disabled and the UI returned `Actions policy updated`. Its private README records untrusted-content handling and owner deletion obligations. No test Issues or user feedback were created. The config names that exact destination but delivery stays disabled. The [text-only provisioning record](private-destination-verification.json) replaces the raw Settings screenshot after GitHub review. The prior `2d517411` commit retains the historical image; this change does not claim to purge Git history. The image contained account/repository metadata and the Actions policy, not credentials or submitted feedback.

Cloudflare's connected-browser dashboard returned **Sign in to Cloudflare**. No Cloudflare connector/token was available, and no account ID, D1 or Worker deployment was verified. The registered remote Mac returned **Offline**. These are access/environment blockers, not a request to reapprove ordinary engineering choices.

| Capability | Current evidence scope |
| --- | --- |
| Unified native Feedback code | IMPLEMENTED / CI PASS at `7ef6cd4b`; exact final formal-branch identity and CI remain fixed in PR #1 |
| Private destination provisioned | Actual GitHub private repository and disabled Actions verified; not delivery PASS |
| Receiver HTTPS / cloud D1 | BLOCKED — Cloudflare sign-in/account access; no cloud receipt |
| Scheduled delivery / unique Issue | BLOCKED — Worker deployment and server-only credential installation absent |
| Actual native-window-to-cloud loop | BLOCKED — offline Mac plus undeployed service |
| Live network/restart/timeout/response-loss acceptance | NOT_RUN; automated local regressions are separately labeled |
| D1 + permanent GitHub deletion | NOT_RUN; no test feedback cleanup obligations created |
| Physical IME / VoiceOver / Keychain / screenshot latency | NOT_RUN — no accessible Mac in this session |

The native endpoint remains nil and both service switches remain false. This internal Beta can save local feedback and test its UI, but **cannot send real cloud feedback**. It is not a public-feedback-ready or end-to-end-complete release. Signing remains ad-hoc, without Developer ID or notarization.

Cloud retention is not physical deletion: live D1 body clearing, resolved tombstones, unresolved Issue-deletion obligations and provider backups are distinct. Before any restore, stop delivery and reconcile prior Issues and tombstones. No credentials are in public source or evidence; no website/DNS, paid plan, screenshot admission, old UNKNOWN or private screenshot data was changed.

## Build environment continuation

Both unchanged Worker/config snapshots from `14bfc1f8` passed actual local `wrangler 4.154.0 deploy --dry-run --outdir --metafile` execution under Node 24.22.1. [Raw output and exact source hashes](wrangler-build-preflight/) record Receiver 9.88 KiB / gzip 3.42 KiB and Delivery 8.86 KiB / gzip 3.27 KiB, exit 0. Tool telemetry/error reporting was disabled. The D1 placeholder and both disabled switches remained unchanged; no Cloudflare authentication, upload, resource or remote request acceptance was verified. This is LOCAL BUILD PASS only.

The original macOS 14 jobs were waiting for a hosted runner with no executed steps. The original `2d517411` pair was cancelled by normal workflow concurrency when the evidence correction arrived; the `14bfc1f8` pair also remained queued. GitHub's official [macOS 14 retirement notice](https://github.com/actions/runner-images/issues/13518) warns of longer queues during deprecation and retirement on 2026-11-02, and recommends macOS 15 as a migration target. No causal claim of a global outage or a scheduled brownout on this date is made.

Both existing workflows now change only `runs-on: macos-14` to the standard `macos-15` label. All triggers, permissions, pinned Actions, concurrency, 15-minute timeout, tests, assertions, package/self-check steps and artifact settings remain unchanged. The [official runner reference](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job) identifies this as a standard arm64 runner, free on public repositories. The product's macOS 13 deployment target and screenshot admission are unchanged. Results must identify the actual macOS 15/Swift environment, not claim a new macOS 14 or physical-Mac PASS.

## Completed source verification and installable package

The reviewed implementation at `7ef6cd4bfd6e22605b0d97db37e249a8d94797c1` passed both actual macOS 15 CI runs: [Native 40733901373](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40733901373) and [Feedback 40733901402](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40733901402). Native ran 501 unique tests; the 38 Feedback/AppKit tests are included, not added again. Service 20, isolation 4+14, fixed composition 42/42, packaging 12+7, release build, strict ad-hoc signing, packaged executable checks and complete unified Beta packaging passed. The original PR7-only conditional step was skipped; the current fixed composition audit executed and passed. Full decoded original job logs and source/checkout/package identities are preserved in [ci-source-verification/](ci-source-verification/).

The integration lead actually downloaded the [native artifact](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40733901373/artifacts/12837440740), verified both ZIP layers and inspected the complete arm64 Riftlet App, candidate launcher, README, resources, notices and manifest. The inner `build/Riftlet-Internal-Beta.zip` is 1,475,586 bytes with SHA-256 `eee6b1bd04ce7f7dead12ad45ef745f6dc9e07d14c609c3d192c24b5042c87d4`. All 14 build-input groups match source `7ef6cd4b` and checkout `05e5f5e5`; their entire trees are also identical in this PR13 run. The source package is usable for local Feedback UI/queue behavior, with the receiver still disabled.

The final documentation successor integrates this reviewed source into the existing engineering branch without changing any build/test input. Its precise final SHA, the new formal PR1 CI runs, final artifact and non-author checks are recorded in [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1). Those later results must be checked there; the source runs above are never relabelled as formal-branch runs. No main merge or public release is authorized or claimed. Real native-to-cloud delivery remains blocked by the separately stated account/device conditions.
