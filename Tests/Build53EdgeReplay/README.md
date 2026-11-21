# Build 53 Edge preview replay

On 2026-11-20, Edge 157.0.4341.60 ran the frozen build 53 page program against the digest-matched system PNG from the earlier Edge QA operation. The fixture uses the named composer attachment surface already covered by the native page-program tests. It renders the card after the one file-input change and calls the original operation's read-only observer. Each scenario gets a fresh document in the same disposable headless Edge instance.

| Preview | Dimensions | Product canvas encodes | Result measured from commit |
| --- | --- | ---: | --- |
| Original file bytes | 2104 × 1652 | 0 | START observed at 43 ms |
| Edge canvas PNG, distinct digest | 2104 × 1652 | 1 | START observed at 202 ms |
| Edge canvas PNG, half-size | 1052 × 826 | 0 | Still inputTriggered at 2,233 ms |

The first two results show that the original QA image can complete both supported content-comparison paths in this fixture. The scaled counterexample demonstrates rejection under the same ownership-shaped DOM. The earlier logged-in page still lacks evidence of its card shape, ownership, preview representation and timing. Its G2 and G4 status remains independent of this development test.

To reproduce on macOS with local Edge and the already-authorized private fixture, set `RIFTLET_EDGE_QA_PNG` to its path and run `node Tests/Build53EdgeReplay/run.cjs`. The runner checks the exact PNG and product resource digests before starting, disables external name resolution and uses a rejecting loopback proxy, a nonce-protected loopback origin, a same-origin page network policy and Edge's native sandbox. It closes its own process group and removes its profile. The exported receipt contains only operation counts, public case/state names, measurements, booleans and SHA-256 digests. The source image remains local.
