# Continuous-click input pipeline — 2026-11-03

Base: `7a4a3b4a44629975afacd94efcf55702f41d4c18` (PR #35 already merged).
Scope: remove the reproduced second-click wait for another independent draft's
START. No new transport, page producer, UI, permission, source admission, retry,
continuation or historic-data behavior is introduced. Exact product source blobs
and tested derived App hash are in `runtime-summary.json`; the source checkpoint
and subsequent review/admission identity are in the short PR's G/H record.

## Result

**MAC_PASS, bounded localhost complete-App scheduling scope.** Independent B's
selection FIFO wait fell from the prior 628.47 ms to 0.331–0.611 ms across the
independent cases (B-only range 0.425–0.611 ms). B's actual page `change` occurred
about 212–254 ms after the original AppKit mouseDown. This uses page/native clock
calibration intervals, not the assumption that a commit return means input.
Five independent B samples: midpoint p50 227.887 ms, empirical nearest-rank p95
and max 237.781 ms; the largest upper calibration bound is 253.444 ms. This small
sample is not a population tail-latency claim. No failed click is omitted.

| Controlled full-App case | A click → input bounds | B click → input bounds | Result |
|---|---:|---:|---|
| Initial nominal START 1000 ms | 210.420–233.389 ms | 215.152–240.622 ms | Unique inputs and COMPLETE PASS; A START NOT_EXERCISED (fixture timer coalescing) |
| Chained nominal START 1000 ms | 222.597–245.169 ms | 213.231–242.542 ms | PASS |
| Chained nominal START 100 ms | 224.374–248.640 ms | 222.118–253.444 ms | PASS |
| Chained nominal START 3000 ms | 214.774–240.391 ms | 212.340–241.472 ms | PASS |
| Different Chrome windows, then other app | 203.287–226.712 ms | 211.580–245.765 ms | PASS |
| Same draft, separate original clicks | 186.658–208.985 ms | 6200.532–6230.768 ms | PASS: B remains queued until A's admitted COMPLETE; continuation remains disabled |

Actual background timer delivery can exceed the configured synthetic delay.
The first fixture scheduled independent timers that Chrome coalesced while A
was hidden; intermediate progress was not independently observable. A therefore
completed through the existing exact COMPLETE path without an admitted START.
That sample and all originals remain retained. The fixture alone was changed to
chain progress tasks; the product algorithm/proof criteria were unchanged.
The deterministic tests separately exercise exact 100/1000/3000 ms deadlines.

Across all six pairs: **12 clicks, 12 begin, 12 commit, 12 unique changed files,
12 distinct source hashes, 11 independent synthetic START records, 12 final
succeeded/used records**, no send, no wrong-target file and no re-input.
All selected-page noncollapsed 8..15 selections, baseline text and existing
attachments remained unchanged. Unselected pages received zero changes. Recorded
page focus events show no reacquisition after input; this is sampled software
routing evidence, not a claim that every possible focus transient was measured.
Same-root restart retained all 12 original operations/media and made no new
begin/chunk/commit. It did not replay any prior successful or UNKNOWN asset.

MainActor synchronous pin: n=12, p50 30.506 ms, max/empirical p95 36.300 ms.
Native input-command queue wait: n=60, p50 0.019 ms, empirical p95 4.525 ms,
max 9.640 ms. The fix addresses selection/observation coupling, not a claim of
one-frame main-thread handling or elimination of browser/network delay.

## Minimal product fix

The App selection FIFO and Core ticket order remain intact. Previously they
awaited `WebAttachmentAdapter.append`, whose input lock extended through START
polling. An optional, exact-operation input-phase callback now releases that wait
only after the original normalized **positive inputTriggered/START** fact.
A bare commit return is insufficient: the page still hashes bytes asynchronously
before setting files and dispatching change.

The SAME original append continues bounded live observation, including its
strict pre-input retirement handling, receipt application and actual
`recordAppendReturned`. Phase notification writes no START/visibility/return
checkpoint. Different recognized business IDs in different tabs/documents with
the same observed Chrome session/profile may use the input lane. Same draft,
legacy/unknown identity, cross-tab same business, mixed local/persisted profile
and reused document remain conservative. QueueStore's atomic original-target,
visibility, ownership and conflict checks are unchanged. Live append ownership
prevents a periodic/recovery observer from duplicating its original observation.
Per-operation adapter release prevents late A cleanup from unlocking B.

Independent early review found a post-intent local-read error-path regression in
the first patch. The final code restores UNKNOWN retention on that path; a real
SQLite trigger reproduces the exact failure without adding a product test hook.

## Verification and reproducibility

- **LOCAL_PASS:** current full product and derived fixture App compile/package
  on ARM64; ad-hoc binary/resource verification passes.
- **LOCAL_PASS:** 10 new Core/real-SQLite test bodies and 7 adapter test bodies
  executed using temporary lightweight native assertion runners linked to the
  actual modules. This is not formal XCTest and not AppKit acceptance.
- **Formal XCTest/ARM64/Intel/Feedback/source CI:** exact G/H and actual-merge
  run results are recorded in the PR handoff after the formal workflows. The
  local machine has Command Line Tools, not an XCTest-equipped Xcode install;
  that environment limit is not labelled a test pass.
- Regressions cover delayed file input, 100/1000/3000 ms START, wrong or repeated
  callback, ownership release, same-draft and ambiguous identities, commit reply
  loss, late A failure versus B success, pre-input retirement, duplicate selection,
  pending B removal/cancel/permission loss, post-intent SQLite decode failure and
  recovery without input. Existing tests and expectations are retained.

The fixture reuses the prior full-App driver/page/server. Only the exact
localhost origin predicate and isolated data namespace differ from the ordinary
product App. No alternate adapter or pending-click compiler experiment is used.
Fresh native built-in region captures supply new PNGs; AXPress selects the
capture mode, CGEvent drives the region and microimage clicks. This is **not** a
new macOS system-shortcut or physical-mouse acceptance claim. Source files,
private images, SQLite, raw logs, target identities and derived source stay in a
private evidence directory; only sanitized measurements/hashes are committed.

## Remaining boundary

Real ChatGPT, physical mouse, truly unobserved cold first click and actual network
failure are **NOT_RUN / PLATFORM_BLOCKED** here. Synthetic START/COMPLETE are not
real platform facts. Same-draft post-START continuation, safe retry and scaled
preview completion protections are unchanged. Existing ordinary compiled
capabilities stay exactly as base; public-production GO is not granted by this
performance change. No old user database, UNKNOWN, screenshot or media was opened
or changed. Draft PR only; no main merge or release is authorized in this task.
