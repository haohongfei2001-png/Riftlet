# Round 8: native transparent padding and cold-click boundary

Branch: `codex/riftlet-real-mac-round8-20261028`. Final source: **`ee1d960adf67432be627e86e7aa9350e5d85d9c0`**. Functional UI/App live source: **`85250a869f06d99e3d3ab046116f560bac572fd9`**. The final source adds only two closed diagnostic rejection labels and their tests; it has the identical UI/App/Core implementation. Final packaged App also received a real no-input diagnostic run.

Formal `e3175f3` plus round-seven `3b089b2` were merged with ancestry retained. During execution the formal branch advanced to `595142d0345adc0d06f54371f50406879310610d`; it was merged before final live tests, including its original permission-recipient protection. No formal branch, PR #1, main, website or brand was modified. Existing worktrees, databases and previous evidence remain intact.

## Actual product outcome

| Item | Result | Scope |
| --- | --- | --- |
| CLEAR native click-through | **PASS — software events** | Real WindowServer-routed CGEvent down/up reached the underlying control window. No repost/forward/AX substitution. Final default portrait four-case batch passes IMAGE, NUMBER, CLEAR, GAP. Large portrait CLEAR also passes. |
| Press/hold and deferred compaction | **PASS — software events** | Original second image stays in place during a 1.5-second synthetic removal request for the first; original release selects exactly the original image once, then compacts. |
| Genuine cold first-click product goal | **FAIL / still open** | Both bounded original AX clicks had no pre-event ACK and produced no input. Moving AX hint registration later improves order, but does not prove cold success or a measured latency saving. |
| Cross-version live root conflict diagnosis | **PASS diagnostic; compatibility still open** | Retained v10 root accessor prevents v12 instrumentation. Final App explicitly reports `unobservedRootDescriptor`; no monitor/operation was cleared or replaced. |
| Minimal extension / Native Messaging | **PASS transport laboratory only** | Real isolated headless Chrome for Testing published two distinct browser document identities through a native host. No ChatGPT adapter, input authority, foreground-click proof or production admission. |
| Build and non-author reviews | **PASS** | Exact source packaged with ad-hoc signature, self-checks and scoped independent source reviews. CI exact source results are in `verification.json`. |
| Final diagnostic-source CI | **NOT_RUN — infrastructure** | Run 40546396233 failed to acquire a hosted macOS ARM64 runner; zero steps executed. Functional source 85250a8 passed complete run 40544274635. No automatic retry loop or paid-plan change. |
| Private data retention | **PASS** | 25 Web assets / 27 operations / 3 compensation audits / 6 upload-start receipts unchanged in count; all original operation identities and six unresolved phases retained; 25 media hashes and 14 other private files unchanged. |
| Physical mouse, cross-application mouse focus, real replacement double-click, 1× backing scale, fullscreen/Spaces | **NOT_RUN** | Software/native callback or AX evidence does not substitute for these cases. |

The input fix keeps the original visual row and its unique accessibility button, makes that row window mouse-transparent, and adds two nonactivating native input windows bounded to the image and number rectangles. Visual parameters stay unchanged. All three windows move, hide, swallow and close together; original event time/window/asset and existing selection protections remain. The fix does not implement per-pixel transparency inside image/number rectangles (including image alpha or rounded corners). It fixes the measured outer CLEAR padding and preserves window-free GAP routing.

Some batches encountered unrelated untagged input or foreground changes. Every original result remains recorded; these are `INCONCLUSIVE` or `NOT_RUN`, not discarded failures or claimed passes. Compact landscape has only one verified IMAGE case; its full matrix remains incomplete. Both existing displays have backing scale 2; only the portrait screen's full matrix is closed. See [GUI evidence](gui-results.md) and [bounded event records](software-routing.json).

## Cold-click and architecture decision

AX registration formerly preceded the first capture attempt. The App now requests authoritative capture before installing synchronous AX hints, and invalidates the old host epoch before deferred binding on activation. It does not cache permission grants, backdate ACKs or replay an unproved click. Real binding took about 23 ms after failed capture; this is measured relocated work, not demonstrated end-to-end savings.

The first runtime found a proved ordinary thread binding but an existing v10 root monitor. The original envelope reduced its unlisted fixed rejection to `invalidReply`. The final diagnostic patch reports the exact safe code while preserving the rejection. A fresh document was tested separately without deleting the old document: early captures rejected composer availability; the first complete native ACK arrived about 1.938 seconds after the AX click. The page's later availability cannot authorize that earlier event. No successful cold-first-click claim is made. Details and exact causal joins: [cold analysis](cold-analysis.md), [timing](cold-timing.json), [final diagnostic confirmation](diagnostic-confirmation.json).

The runnable [extension laboratory](extension-lab/README.md) demonstrates that document-start push can reach a native process and distinguish a new browser document. It also retains the explicit undelivered-invalidation counterexample: stale cached metadata can still appear current before notification arrives. Chrome document identity is not ChatGPT business draft identity. **Decision: do not switch production transport or add shipping extension permissions on this evidence.** The next architecture increment needs original native-event/foreground binding, exact business-draft proof and target-side validation, including startup/channel-loss gaps; a push channel alone is not the cold-click solution.

## Integration and evidence

Pro can merge this branch; formal `595142d` and round-seven ancestry are already present. Do not re-cherry-pick rounds five through seven. Review the small UI/App and diagnostic additions rather than replacing formal Core or first-use files. No new Core change originates from round eight.

- Functional source commit: `4e2391bfb54b4a9f8a9ce9a8fac6b27b209efa10`.
- Formal protection inheritance / live UI source: `85250a869f06d99e3d3ab046116f560bac572fd9`.
- Final diagnostic + isolated laboratory: `ee1d960adf67432be627e86e7aa9350e5d85d9c0`.
- [Functional-source CI PASS](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40544274635); [final-source runner failure](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40546396233) ([exact infrastructure annotations](ci-infrastructure.json)). Resume only this CI check when capacity is available; do not repeat real uploads.
- [Build/CI provenance](verification.json), [non-author review](review.json), [data preservation](data-preservation.json).
- Raw private logs/SQLite backups/images remain local. Public evidence contains only synthetic fixture identities, scoped timing/geometry, counts and hashes; no chat text, URLs, authentication or real screenshots.

Private before/after SQLite snapshots preserve the original and refreshed observations. Read-only recovery changed five operation timestamps/reasons and two current observation receipts; all identities, attempts, phases, compensation audits and upload-start receipts stayed intact. This is not a claim that the database bytes never changed.

Production screenshot input, production upload-start profiles and safe retries remain disabled. This round sent no ChatGPT message and caused **zero new image inputs/operations**. The round-seven successful two-image FIFO was not repeated. A→B→A business identity, cross-version original-operation recovery, MID byte interruption, independently admitted failure rebirth, Screenshot.app self-inclusion, T0/T1/T2 and production screenshot end-to-end remain open; no prior FAIL is silently promoted.
