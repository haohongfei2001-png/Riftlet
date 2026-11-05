# Evidence index

## Baseline inspection

Actual main/API: `b61fc46cf931bdbd14deec1b47d077e92db61e16`. Existing open PRs are historical; no competing current implementation was observed. Main checkout initially clean.

Installed executable SHA-256: `c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4`; matches accepted Beta manifest, reviewed runtime source `004741fe25cbdd59b72bf3c04ec061c7a1e2c0d5`, admission `59043edb2c2485167a61111c5a1255bae7bee1c8`. Main inherits that runtime source. This inspection is not a new live upload test.

## WP01

Design branch `design/settings-control-center-20261106`, preserved start `6372bcf3fbeb71cb7ad2d930cad18528e2d54796`. V1 SHA-256 `aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf`; v2 final `c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58`.

Final headless browser runs: original 82 PASS, supplemental 21 PASS, 18 additional raw visual scenes. Full case results and screenshots live on the design branch under `design/settings-center-20261106/revision-2/evidence/`. Original 69 PASS / 13 FAIL and unsuccessful intermediate guard run remain intact. Native UI not implemented/tested by this prototype result.

Further package results will be appended after execution, with scope and source identity.

WP01 published design commit: `83b8ee478f13d3714697eda4cb3a7785576cb6e0`; existing branch pushed, v1 artifacts unchanged except README latest-candidate pointer.

WP02 development evidence: actual Chrome in headless/isolated-profile mode passes 31/31 test groups (43 controlled scenarios within 18 browser groups plus 13 cleanup tests). Full headless-shell attempt had 30/31 groups PASS and a cross-tab focus wait failure; retained log, not a product failure claim. Same failed group and then the complete suite pass in full Chrome without source/test change.

Local Swift XCTest is unavailable: CommandLineTools Swift 6.4 has no XCTest framework, both default and native build systems fail before tests. No tests skipped or represented as passing. Native storage probe compiles actual Core/Capture modules and passes a 160-image initial run; extended 1,200-image run in progress. Formal XCTest will execute in existing macOS CI.

## WP03 completed

`storage-recovery.py` implements health/backup/verify/restore with existing offline locks, byte-preserving SQLite/media/journal copies, logical checks on temporary copies, explicit incomplete receipts and new-directory-only restore. Independent root review and rerun: 25/25 PASS. See `evidence/WP03-review.json` and `evidence/storage-tests.log`. The running installed App's root returned `source-in-use` before any copying; that validates refusal, not production DB health. No production changes.

## WP02 completed local evidence

See `evidence/WP02-results.json` and `docs/RELIABILITY_BASELINE.md`. Page VM123/123, legacy61/61, complete Chrome31/31 groups including43 controlled scenarios/122native inputs/zero sends/zero application network requests. Native soak1200 captures/628.626seconds + separate160 collector burst captures, all originals/private bytes/UNKNOWN retained. Independent12child ownership lifecycle PASS. Installed App13sample one-minute observation RSS32864–32992KiB, maxCPU0.1%; activity uncontrolled, not idle certification.

Long-run stable-file→durable-asset P50=3.628ms/P95=5.780ms; visible-queue SQL P95=0.180ms; history40 P95=4.552ms. Probe RSS19,890,176–25,968,640bytes; CPU sampled-interval delta≈1.953% of one core. Generated64×40images only; no UI/network/permanent-lifetime claim. Old burst timing starts after generation/start and is retained only as residual settle time; corrected short run begins before first write.

Reanalysis of accepted final Beta cold-pair trace is metadata-only: click→START-report367.468/195.423ms, report→swallow-start11.545/4.629ms. No new ChatGPT operation; exact setter time and first animation close are unavailable.

All original local logs remain in ignored `test-results/readiness`; public log copies replace local home prefixes. WP02-results binds both original and public hashes.

## WP05/WP06 and independent WP02 review

`evidence/WP02-WP05-WP06-review.json` is frozen non-author review of probes, actual logs and consumer-source/documentation corrections. It found and resolved timing semantics, cumulative CPU labeling, process failure receipts/path redaction, restored feedback diagnostic preference and oversized derived-PNG fallback wording. No remaining reviewed-scope blocker. Native UI/permission execution and public-release certification are explicitly excluded. Three existing product Swift files change only presentation strings; attachment implementation unchanged.
