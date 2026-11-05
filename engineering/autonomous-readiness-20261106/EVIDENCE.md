# Evidence index

## Baseline inspection

Actual main/API: `b61fc46cf931bdbd14deec1b47d077e92db61e16`. Existing open PRs are historical; no competing current implementation was observed. Main checkout initially clean.

Installed executable SHA-256: `c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4`; matches accepted Beta manifest, reviewed runtime source `004741fe25cbdd59b72bf3c04ec061c7a1e2c0d5`, admission `59043edb2c2485167a61111c5a1255bae7bee1c8`. Main inherits that runtime source. This inspection is not a new live upload test.

## WP01

Design branch `design/settings-control-center-20261106`, preserved start `6372bcf3fbeb71cb7ad2d930cad18528e2d54796`. V1 SHA-256 `aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf`; v2 final `c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58`.

Final headless browser runs: original 82 PASS, supplemental 21 PASS, 18 additional raw visual scenes. Full case results and screenshots live on the design branch under `design/settings-center-20261106/revision-2/evidence/`. Original 69 PASS / 13 FAIL and unsuccessful intermediate guard run remain intact. Native UI not implemented/tested by this prototype result.

Further package results will be appended after execution, with scope and source identity.
