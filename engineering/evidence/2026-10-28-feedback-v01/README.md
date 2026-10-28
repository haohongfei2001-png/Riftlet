# Feedback v0.1 · permanent implementation evidence

Tested/reviewed source: **969463da21a89e128fd24cb973423d4a252d4b21**. Baseline: **4b7228a07a23381d3de467a44dd8490d73e26e7e**. Draft [PR #7](https://github.com/haohongfei2001-png/Riftlet/pull/7) targets the engineering branch; it is not merged. Any subsequent documentation-only checkpoint preserves the tested source. [Chinese implementation handoff](../../../docs/FEEDBACK_V01_HANDOFF.md).

## Actual final verification

| Check | Result and exact scope |
| --- | --- |
| [Native foundation 40658659540](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40658659540) | completed/success; 17 steps. **472 unique native tests**: Core135, Adapters137, Capture65, UI56, App47, Feedback25, FeedbackUI7. Current/legacy page VM **83/61**; SQLite v1/v2→v3, UNKNOWN/compensation/permission/original-selection regressions; 12 packaging tests; Release/bundle/ad-hoc/five self-checks. |
| [Feedback 40658659566](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40658659566) | completed/success. **32 feedback-native tests** (the same subset of472), **18 real SQLite/mock HTTP service cases**, three additional repetitions of2 close/reopen tests (not new unique cases), packaged offline demo. |
| Local Linux | Same final feedback module subset:25 XCTest cases with Swift6.2.1 Linux;18 Node22 SQLite/mock HTTP cases. Not macOS/Keychain/GUI/cloud evidence. |
| Non-author review | [GitHub Codex receipt](https://github.com/haohongfei2001-png/Riftlet/pull/7#issuecomment-6464592025), 2026-10-28T08:45:12Z, exact source969463d: no major issues found; summary completed with no findings/unresolved findings. Not human approval, deployed-service security audit or GUI acceptance. |

Both actual workflow checkouts use `636e40d6c3c0b2cd51dede448a3f57c9f08f3f36`, a temporary merge into the unchanged engineering base. GitHub compare to969463d returns **zero changed files**, not just matching filenames. The Feedback source archive was compared with28 locally tested matching source files: zero byte mismatches.

Artifacts were downloaded and their SHA256 recomputed locally:

- [Native App/helper/logs12803615227](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40658659540/artifacts/12803615227): `e1e076d34c415e9fe5206a2bda6ed40c5256a235f95330c32eb54e942e6ab868`; expires2026-11-11T08:44:44Z.
- [Feedback demo/source/logs12803058771](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40658659566/artifacts/12803058771): `e64aa6bbbc8f2d9fe6d4542702031041c5ae10617a4c8d3774bccc349f898881`; expires2026-11-11T08:53:57Z.
- Inner Riftlet App ZIP: `aaf7321b4588654d6a685198c2b43a7d161c114eb7b53fdc1ffdf1874127773f`.
- Inner offline-demo ZIP: `240fdb7c6e2f297f2194710e897ceb3c742dbcd664860f48203c7a4da27da183`.

Feedback detailed log:32 executed,0 failures; seven software AppKit tests include typed-text/consent/draft save, failure freeze, reopening and termination. Close repeat totals are2/2/2 with0 failures. No test was skipped or its timeout extended to hide the original failure.

## Failures and fixes retained

The earlier abdc70c native run40652246927 compiled but failed a close fixture that called the close delegate twice without reopening the window; the final fixture really reopens/shows the same NSWindow, uses AppKit performClose, observes willClose and checks the latest durable text/revision after both closes. The implementation's close/quit edit-freeze protections remain.

Commit5fc1e7f added explicit credential removal but missed the standalone offline-only demo provider's conformance. Run40656801971 failed compilation; no native PASS claimed. Commit2f9c16e fixed the provider and both full-native40657132274 and Feedback40657132286 passed. Those prior runs do not replace the969463d final runs.

Non-author findings led to real fixes and deterministic tests: status-refresh/deletion wakeup; edits during close/quit; expiry deletion with no possible Issue; demo last-window lifecycle; resolved tombstone TTL; Keychain cleanup paired with local forgetting; DELETE before original POST commit; orphan credentials after failed/overlapping enqueue. See review.json for thread identifiers and source mapping.

## Explicit NOT_RUN / not admitted

Live Cloudflare Workers/D1/private GitHub Issues round-trip, native HTTPS against that deployment, actual Keychain authorization/restart, physical input/IME/VoiceOver/Finder/Gatekeeper, screenshot/click latency with feedback, cloud backup restore and owner deletion operation. The service tests execute real SQLite through a D1-shaped fixture and mocked GitHub; not a live D1 deployment. The old screenshot self-checks keep CHROME_NOT_RUN / SYSTEM_SCREENSHOT_NOT_RUN / PERMISSIONS_NOT_REQUESTED / GUI_NOT_RUN. The offline demo is synthetic, with no real server.

No resources/private destination/secrets were provisioned, and neither App endpoint nor server accept/delivery switches were enabled. Screenshot production/start/completion/retry policies, SQLite v3, original media and UNKNOWN are unchanged. Only the isolated feedback branch was written.
