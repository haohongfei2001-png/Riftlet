# Round-six bounded transport comparison

In one real generated-PNG run per version, increasing the chunk capacity from 64 KiB to 256 KiB reduced the accepted selection→AppKit panel-close interval from **5,510.218 ms to 3,668.704 ms**, a **1,841.513 ms (33.42%)** reduction. The chunk-transfer span fell from **2,770.876 ms to 893.438 ms**. Both runs recorded one original File input, positive upload start and independent final image proof. This is a limited real performance comparison, not production admission or whole-product completion.

## Exact source and scope

The v12 repository source is `7878de3138d1c140369c3cfbe69a28dd2770294c`. The runtime build at `/tmp/riftlet-round6-runtime-build` applies the same two documented round-five acceptance overlays: synthetic start-policy admission and AppKit/store diagnostics. It is not an unmodified production binary. Its executable SHA-256 was read directly as `6119a6fb872f7e5cd380d1d234955d2e14e6e8f48d80bbaaeda35afcd5ea91ee`.

Both operations used a 3,147,775-byte purely generated PNG with SHA-256 `494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`:

| Run | Original operation | Original asset | Attempt |
|---|---|---|---:|
| Round five, v11 / 64 KiB | `D53F7E0E-871B-4118-84DB-FB00772E1FE7` | `A69D72AA-1616-4D12-BC70-8FA5A77B8AE0` | 1 |
| Round six, v12 / 256 KiB | `134D2BC3-19D5-4E87-BAFC-EE8D23195C13` | `D1871E45-5FB8-4F8E-9BAD-920C4EE8E8A2` | 1 |

Inputs are `/tmp/riftlet-round5-final.jsonl`, `/tmp/riftlet-round5-final-page.json`, `/tmp/riftlet-round6-valid-cold.jsonl` and `/tmp/riftlet-round6-perf-page.json`. Private target identities, page URLs, content and raw receipts are not reproduced here. The round-six calculation selects the accepted boundary for asset `D1871E45…`; it excludes the earlier rejected cold selection and the later separate asset's selection. Neither is reclassified as a successful transfer by this report.

## Native-command and presentation intervals

All table durations use one host monotonic clock within their respective run. Chunk commands are selected between this operation's begin and single commit, not by combining unrelated later observations.

| Segment | v11, 64 KiB | v12, 256 KiB | Interpretation |
|---|---:|---:|---|
| Selection→validation return | 48.808 ms | 55.145 ms | Includes selection-to-command dispatch; validation execution alone was 45.589 / 49.866 ms. |
| Begin execution | 48.052 ms | 49.168 ms | Original-operation buffer initialization and ACK. |
| Chunk count | 49 | 13 | 48 ×64 KiB or 12 ×256 KiB, plus the same 2,047-byte final chunk. |
| Chunk span, first execution start→last return | 2,770.876 ms | 893.438 ms | **1,877.439 ms shorter (67.76%)**. |
| Sum of chunk execution durations | 2,405.594 ms | 700.396 ms | **1,705.198 ms shorter (70.88%)**. Native checks, encoding, submission and receipt reading are not individually timed. |
| Sum of chunk queue delays | 304.676 ms | 168.013 ms | Includes each command's own queue delay; first chunk's queue precedes the span. |
| Remaining gaps inside chunk span | 60.630 ms | 25.045 ms | Span − execution sum − queue sum + first-chunk queue delay. |
| Median individual chunk execution | 49.582 ms | 53.374 ms | Larger chunks cost slightly more individually; fewer commands dominate the aggregate saving. |
| Individual chunk execution range | 41.853–58.031 ms | 49.006–60.175 ms | Observed samples only, not latency percentiles for general use. |
| Single commit execution | 133.798 ms | 87.032 ms | Command return is not an exact timestamp for async File input. |
| Selection→commit return | 3,007.470 ms | 1,102.414 ms | **1,905.056 ms shorter**. |
| Selection→observed persisted hidden state | 5,257.115 ms | 3,417.839 ms | Upper-bound observation of the transaction result, not exact SQLite COMMIT. |
| Observed hidden state→panel-close code path | 253.102 ms | 250.866 ms | Nearly unchanged. |
| Animation-start code path→panel-close code path | 252.682 ms | 250.614 ms | Configured animation duration was 240 ms in both runs. |
| Selection→panel-close code path | **5,510.218 ms** | **3,668.704 ms** | **1,841.513 ms shorter (33.42%)**; not rendered-pixel timing. |

For reproducibility, the accepted host selection and panel-close timestamps were `456677.60366983333 → 456683.11388733337` in round five and `462710.7825737917 → 462714.45127791667` in round six.

The serial Apple Events queue also served two captures (142.495 ms total execution) and thirteen observes (175.814 ms) during the v11 chunk span, versus one capture (71.712 ms) and ten observes (114.934 ms) during the v12 span. Observation traces omit per-operation identities, so they cannot all be assigned to this upload. Queue loads therefore differ between these single runs; the aggregate reduction cannot be attributed exclusively to chunk size. No recovery or target check was disabled for this comparison.

## Page-input, start and final-proof intervals

These differences use the same document's `performance.now()` directly and do not depend on host/page clock alignment.

| Segment | v11 | v12 | Difference |
|---|---:|---:|---:|
| Original File input→positive start | 2,177.900 ms | 2,235.400 ms | v12 +57.500 ms |
| Positive start→final proof | 5,467.800 ms | 5,726.600 ms | v12 +258.800 ms |
| Original File input→final proof | 7,645.700 ms | 7,962.000 ms | v12 +316.300 ms |

The v12 original input/start/proof timestamps are `100073.80000001192 / 102309.19999998808 / 108035.80000001192` ms. Its recorded start pair is `4.084106969654981 → 4.9916862962449775`, with one input, verified original hash and retained final proof. The positive start is about 5.727 seconds before final proof. These values support an earlier transport/input boundary; they do **not** show faster page-side uploading. The later `startDisqualified=true` after progress removal does not erase the original start audit or substitute for final proof.

The page snapshots report preserved draft text, prior cards and selection, and one observed file-change event for each original operation. They do not establish other targets, retries, physical-click behavior or a broad privacy guarantee. The actual File event is synthetic as designed; the accepted App click was automation through the accessibility selection boundary.

## Clock alignment and measurement limits

The later read brackets page `nowMS` with host before/after times. Those brackets are **263.431 ms** wide for v11 and **264.446 ms** for v12. Assuming the same document clock and no intervening clock discontinuity, they give the following conservative host-aligned ranges:

| Interval from accepted selection | v11 | v12 |
|---|---:|---:|
| Original page input | 2.757–3.021 s | 0.895–1.160 s |
| Positive page start | 4.935–5.199 s | 3.131–3.395 s |
| Final page proof | 10.403–10.667 s | 8.857–9.122 s |

A midpoint estimate is not an exact timestamp. Command-return time is not the native input instant; hidden-state observation is not SQLite COMMIT; AppKit callback/close timing is not a rendered-pixel or physical-pointer measurement. Page proof is also distinct from a later persisted `succeeded` audit; this report does not derive that transaction timestamp from page proof. One run per version provides no variance estimate, warm/cold distribution or general speed guarantee. The runs use separate original operations and browser targets, with different interleaved queue work. The earlier rejected cold click, subsequent targetBusy case, MID/retirement and other open product requirements remain outside this comparison.

## Safety-preserving implementation and verification

The separate v12 registry accepts bounded 256 KiB chunks. `WebPageProgram.maximumChunkBytes` remains code-owned and defaults to 64 KiB for generic/older programs; only the reviewed current loader specifies 256 KiB. Historical observation routing retains its own version and cannot acquire a new input lease. Native and page total bounds remain 8 MiB. The page checks both encoded Base64 length and decoded size, including the +1-byte decoded overflow that can share the exact-limit Base64 length.

Each chunk retains the frozen original identity and ordered index, and native validates its ACK before sending the next. The no-follow descriptor, pre-transfer full hash, transfer-time full hash/stat verification and single commit remain. Wrong/lost ACK never causes a smaller-chunk fallback or replay; uncertain commit permits only original-operation observation. No new capture during transfer, parallel sends, cached executable protocol or relaxed target check was added.

All 72 current-page tests passed locally, including the 13-ACK fixture and existing start/final/ABA/NodeList regressions; the coordinator's complete page/legacy/helper set reports **126 passed**. Adapter compilation passed locally. Local `swift test` was blocked by Command Line Tools lacking XCTest, so it was not reported as a native-test pass. The subsequent full macOS [CI run 40510840772](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40510840772) passed for the reported source. Four targeted Swift methods cover exact larger-chunk bytes/identity, wrong ACK, lost chunk or commit replies followed only by observation, and invalid capacity/8 MiB bounds.

The real v12 run demonstrates that this fixture's 256 KiB commands are accepted by the tested Chrome/Apple Events path and complete with one input and independent proof. It does not establish universal payload compatibility or production admission. No additional browser action or upload was performed for this calculation.
