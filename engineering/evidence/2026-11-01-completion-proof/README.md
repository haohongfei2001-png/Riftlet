# Bounded completion proof correction

Base: actual main `307335f6f1511fc49d57275ab19cf9c55496ba5a`.
This is a partial completion-proof repair, **not** a resolution of every large
screenshot or a new production admission. No live browser, original screenshot,
queue, UNKNOWN, media, or audit was mutated in this increment.

## Real failure and strict boundary

The preserved S record in acceptance commit
`e04c12eb4e41cec566ce53c5c78c8750497d5e4a` contains a 4,723,887-byte,
2400×2064 original and a 2048×1761 loaded PNG preview. Its Data URI has
14,192,886 characters; the old proof guard allows at most 11,184,875. That
snapshot necessarily fails the guard. It does not record the first invocation
of that branch. The original input and upload start succeeded, but completion
was not proved and the durable operation is UNKNOWN. **Do not reinput or
retroactively admit S.** Even without the length rejection, dimensions differ.

Four separate claims must not be conflated:

1. Original input integrity: original private-file SHA, exact one File input,
   operation/asset/attempt/target correspondence.
2. Upload start: original attachment's independently admitted positive progress.
3. Product completion: unchanged strict same-card/image/load/progress-ended
   protocol plus exact bytes OR full original-size sRGB RGBA equality.
4. Server original-byte fidelity: **not established** by a local/UI preview.

The repository's existing network experiments do not bind a real large byte
request to an immutable platform file ID and independent finalization response.
Guessing file IDs, names, React flags or progress 100 cannot replace that missing
contract. A scaled image—even one produced by exact local resampling—cannot
prove the original pixels. That path stays UNKNOWN; no lossy matching is added.

## Product difference

Only `chatgpt-web-20261027.js` changes in production. The existing 8 MiB input
limit and 16,777,216-pixel limit are unchanged. A bounded byte-copy fast path is
still available. A larger already-loaded PNG preview no longer requires an
additional `atob` allocation: the existing exact sRGB comparison uses the image
already decoded by the browser. Encoded length is not input identity. There is
no new larger byte limit, fetch, network hook, resampling, tolerance or fallback
success. Dimension changes are rejected before allocating the preview canvas.

All async original card/image/source/final-load/target and error rechecks remain.
Old installed v13 observer closures remain unchanged when a new caller script is
injected. The new logic is used by newly installed observation states; do not
reset a registry, reopen old operations or refresh user pages to migrate them.
The old-closure regression explicitly demonstrates an existing unproved
operation does not gain proof or a second input.

Receipt decoding/normalization, independent admission profiles, QueueStore,
Coordinator, durable registration, UNKNOWN conflicts and compensation are
unchanged. An unproved/invalidated observation cannot become verifiedReady or
safe-to-retry. No ordinary, built-in, continuation or retry switch is opened.

## Executed validation

- Deterministic bundled page program: **PASS**, 123 cases. New coverage includes
  expanded encoding, single-channel mismatch, scaled/oversized/invalid dimensions,
  decode failure, same-name collision, source/repeated-load/late-error/draft
  changes, wrong process/attempt and retained old observers. These are simulated
  DOM/pixels, not browser or server evidence.
- Legacy read-only page observation: **PASS**, 61 cases; no new inputs or proofs
  granted to old operations.
- Real headless Chromium PNG/Canvas/DOM: **PASS**, four bounded offline controls;
  exact source hash, browser/driver versions and results in `headless-png.json`.
  An original 1,152,567-byte RGBA PNG and its same-size >8 MiB encoding reproduce
  the old missing-proof guard and pass the new strict comparison. A one-channel
  change and smaller preview fail. Actual File/crypto/decoder/canvas/load are
  exercised; platform progress and React ancestry are synthetic. All requests
  are intercepted; no account, live ChatGPT, desktop focus or upload is used.
- Local Swift test execution: **BLOCKED** by this host's CommandLineTools missing
  XCTest module. This is not a passing native run; formal ARM64/Intel/Feedback
  and exact source admission must be read from the actual PR merge checks.
- Real ChatGPT with changed App: **NOT_RUN**. Large resized-preview completion:
  **unresolved**, preserved S remains UNKNOWN. Physical/natural cold click:
  **NOT_RUN** in this increment. Production remains **NO-GO**.

Reproduce offline browser test with Playwright 1.62.1 installed outside checkout:
`NODE_PATH=/path/to/deps/node_modules node scripts/verify-completion-preview.cjs`.
Use headless Chromium; the script never opens the user's browser profile.

## Integration and remaining evidence

Use a reviewed source checkpoint G, then the admission-only H and actual PR merge
CI per `docs/MAINLINE_GOVERNANCE.md`. No historical gate/workflow/evidence is
rewritten. The only runtime file to integrate is the page program; tests and this
record accompany it. Exact G/H, independent report and final CI/artifacts belong
to the PR handoff, not an invented self-referential source SHA in this document.

A future solution for scaled previews requires independently observed binding
from original input/actual payload to original attachment business ID and a
reliable completed/finalized response (plus bounded original-file retrieval/hash
if claiming byte fidelity). This increment does not implement that unverified
contract. A new, independently authorized operation is required for any future
real acceptance; existing UNKNOWN cannot be used as a test retry.
