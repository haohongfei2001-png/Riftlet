# Independent Web integration review — 2026-10-28

Reviewer: `/root/review_web`, a non-author AI reviewer. Read-only repository review; no tracked files, refs, browser, real input, private databases or private evidence were modified or accessed.

## Decision

**No integration-blocking defect found in the reviewed Web delta.** This is a source/regression review, not human GitHub approval, post-fix real-system SC-COMPLETE, or production admission. Final combined macOS CI remains the lead's separate verification gate.

- Reviewed handoff: `f2ae645451044649fbe73326952efbe084353869`.
- Reviewed whole tree: `33494e55f3e067782fa2b5f97d61450776f88286`.
- Compared official baseline: `4b7228a07a23381d3de467a44dd8490d73e26e7e`.
- Final source commit: `48574df19f34e5681ee98815750e279540e9eb9b`.
- Verified `Sources`, `Tests`, `Package.swift`, `.github`, `scripts`, `Resources` are unchanged between `48574df` and `f2ae645`.
- Verified frozen LegacyWeb fixtures and `legacy-web-observe.js` are unchanged from the official baseline.

## v9/v10/v12/v13 compatibility

The actual new runtime allowance is the additional `9` in the owner allowlist at `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js:208`. It preserves the one-owner rule, immutable old-registry descriptor checks, bounded original-state chain, original head/tail/count consistency, data-property-only introspection, exact frozen function bodies for intact/bind/stop/get/set, and owner diagnostics requirements (lines 182–234). No historical input implementation is installed by this path.

The borrower retains owner registry/map/monitor/diagnostics/function/descriptor identities and rechecks them; lost, stopped or replaced owners permanently revoke the borrowed monitor (247–260). Private group tokens keep the new v13 checks separate from old-generation checks and invalidators. New checker exceptions are caught locally. Borrower stop cannot stop or restore the owner; its own stopped wrapper remains a tombstone (261–294).

The frozen v9, v10 and v12 root monitor, thread identity reader and full structural binding predicate match exactly, as asserted by the added protocol regression (`Tests/WebPageProgram/acceptance-program.test.cjs:1300`). The parameterized fresh-input/proof/late-error regression now runs for all three historical owners (1230 onward). The new old-v9-UNKNOWN test retains the original operations object, inputCount=1, null proof and descriptor even after previous v11/v13 capture failures, then rejects old-target begin/chunk/commit under v13 (1313 onward).

Old requests cannot acquire a new v13 lease: v13 matches the full frozen target and operation identity; non-observe commands require its live tail generation (718–752). One-shot commit is written before asynchronous hashing and input (787–813). The legacy program accepts only `observe`, uses original closures and proof, and never installs or repairs a registry (`legacy-web-observe.js:8, 23–49, 67–77`). Existing old stopped/invalidated operations do not inherit newly computed completion or retry authority.

The existing documented limitation remains: same-MAIN-world function-source checks are compatibility guards, not authentication against malicious registry substitution. The existing cross-root tampering counterexample is deliberately retained in the test suite (1282 onward). This delta does not claim to close that pre-existing boundary.

## Exact sRGB content verification

The actual pixel-path change removes only `willReadFrequently: true`, retaining explicit `{colorSpace: 'srgb'}` (448–459). Completion still requires either exact preview byte length plus original-file SHA-256, or equal width and height plus an exact SHA-256 of every sRGB RGBA byte (475–482). There is no numeric tolerance, similarity score, approximate matching, or broader completion profile.

Async proof remains attached to the original operation, original card and image nodes, original source string and final-load sequence. Current membership, absence of errors and upload completion are rechecked after asynchronous decoding/hashing; mismatch invalidates rather than passing (483–493). The emitted attached observation further checks full identity, load/progress order, file hash, inputCount=1 and the proof's original nodes/source/load sequence (842–847). This preserves true attachment-content checks rather than accepting a placeholder or arbitrary image.

The sanitized stage-two source evidence explicitly distinguishes the actual upload runtime `867d93f` from the later `48574df` patch. Its same-original/preview color comparison supports the small rendering-option change, but there was no post-patch new-input run. I read the public evidence only; I did not inspect its private image, database or original trace. **SC-INPUT and SC-START remain scoped inherited PASS; original-runtime SC-COMPLETE is FAIL and patched end-to-end SC-COMPLETE remains NOT_RUN.**

## Admission and preservation

`Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift:10–14` keeps all three candidate maps empty. Neither Web delta edits ordinary-mode composition, receipt policy, SQLite schema or legacy observer code. Existing UNKNOWNs retain their original identities and remain observe-only. No completion or retry is granted merely because the new pixel path may match a newly created operation.

Current-facing `docs/SYSTEM_SCREENSHOT_WEB_CANDIDATE.md` still describes v10/v12 compatibility and all three SC rows as NOT_RUN. The lead was notified to refresh those current-facing facts in the integration handoff while retaining the original historical evidence. This is a documentation update needed for a clear handoff, not a source blocker.

## Executed review checks

Environment: Node `v24.22.1`, Linux; deterministic synthetic DOM/VM only.

| Check | Result |
| --- | --- |
| Repository current page suite | 86 passed, 0 failed, 0 skipped |
| Repository legacy observe suite | 61 passed, 0 failed, 0 skipped |
| Independent focused probes | 3 passed; ran with the original 86 tests, total 89 passed, 0 failed, 0 skipped |

The three temporary review probes exercise a one-channel/one-level pixel mismatch (must invalidate), equal pixel data with different dimensions (must invalidate), and both decode contexts receiving exactly ordinary explicit sRGB options without a read-frequency hint (matching case attaches once). These probes live only in `/tmp/riftlet-web-review-probes.cjs`; they do not modify repository tests or pretend to measure browser color behavior. They are not additional macOS CI tests and must not be added to the repository's 86 count.

Logs and SHA-256:

- `/tmp/riftlet-review-web-current.log`: `ca7c9ac41d0d6ea0cbfca5b6ec12c83e640748cbdc0ece03050861c08b4a1fe4`.
- `/tmp/riftlet-review-web-legacy.log`: `fb0d35b7fb0cb27803e2d591a4b51d3018e8124f129d0a9f94ddc448b5db4fc4`.
- `/tmp/riftlet-web-review-probes.log`: `f13d0813691ab299d37dc7b42841825847e044bdf0387aed2639c85188af5551`.

Remaining real-evidence boundaries include post-fix new-system-PNG completion, nonempty preexisting-attachment preservation in this stage, physical mouse/GUI, no-ACK cold click and production/safe-retry admission. No existing FAIL or NOT_RUN was promoted by this review.
