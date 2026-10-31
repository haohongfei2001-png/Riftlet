# Fourth-round Web + v3 lifecycle integration · 2026-10-27

## Exact source and preservation

- Formal starting point: `b84892071d7711177bb856051251a337f2c2c4f5`.
- Incoming original tested source: `c9c68a66c4b6ff55ffe8048cff6f1cf781600519`; complete handoff: `03a67cc41e542a7db6dc128b27da8f108efc9896`.
- Integration commit: `2ddd4069044e1407edfe57c38f071c4c5585d277`, with both b848920 and 03a67cc as parents. Both original source commits and evidence history remain ancestors.
- **Complete CI-tested source: `c85020b0ae250eaa37f7ed812c3c43587dca5a91`.** It fixes one missing parenthesis in the new test; no runtime source or policy changed after 2ddd406.
- The following documentation checkpoint has the same 12 source/test/build/replay Git objects. The exact final branch HEAD is pinned in the PR #1 handoff comment; these records do not relabel old CI as a new run.
- All **11 original evidence files (7 JSON +4 text)** match 03a67cc byte for byte. The manifest includes each file's Git blob and SHA-256. The Core SQLite/QueueStore/Coordinator/receipt-policy files, UI, Capture, research, website, design and notices remain their original b848920 objects, except the explicitly reviewed Models profile branch. No private live store was accessed here.

## Implemented increment

The v8 composer-availability/identity program, native context validation, helper coordinate diagnostics and observe-only v6/v7 router join the existing v3 visibility lifecycle. Legacy observation requires the original complete target, operation/asset/attempt/hash and surviving original closures/proofs; it never installs historical input code or recreates an old tab/proof.

The Core patch recognizes only the independent `chatgpt-composer-react-persisted-20261027-v1` + bare36-character UUID format. It preserves the original value and existing local-profile rule. Same UUID remains locked across case/rearm/window/document changes; different valid UUIDs narrow the conflict only within the same recognized profile. Cross-profile, nil/unknown/malformed identity, UNKNOWN and compensation retain conservative protection. Full receipt target equality is unchanged. Existing stored valid identities are recognized on reopen without a migration or JSON rewrite; the new tests verify that runtime change and byte preservation.

The optional `captureTargetWithDiagnostics(context:)` performs the same one capture and checks as the ordinary API. Host-only request/attempt/epoch never enters page JSON. Native received/validated/MainActor-return logs, the adapter-validated result and App publication share the exact request, while reused targets keep their original effective ACK/request. Selection records original event and handler times separately. Diagnostics do not authorize input, replace a target, backdate ACK, add a mailbox or replay a refused click. The pre/post assignment sampling interval alone cannot establish a publication race.

## Actual verification

[Run40484855920](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920) / job122123985228 completed successfully; run metadata recorded `2026-10-27T09:59:57Z` (**17:59:57 Beijing**). Root and a non-author reviewer independently fetched the actual logs and artifact metadata.

| Check | Actual result |
| --- | --- |
| Native unit/integration | **306 unique tests**: Core117, Adapters102, Capture48, UI39 |
| New integration regressions | 7 persisted identity/SQLite/lock +5 host capture diagnostics, all present in actual execution |
| Migration and recovery | Frozen v1→v2→v3/v2→v3, overall transaction rollback, future-version refusal, UNKNOWN, compensation, wrong receipts, cross-profile locks and M1 recovery |
| Detailed UI lifecycle | **13 passed /0 skipped**, including7 software panels; not counted twice in306 |
| Page / legacy VM | **48 /14 passed**, controlled DOM and original-code fixtures only |
| Network tools | 8 fault /12 read-only probe groups, offline; real MID remains NOT_RUN |
| Archive replay | 55files /19tests /89trace prefixes /2 explicitly SIMULATED late-error checks; zero browser actions/network requests |
| Build | Release and development ad-hoc signature PASS |
| Packaged self-checks | All three PASS; Web check explicitly CHROME_NOT_RUN/GUI_NOT_RUN; helper GUI_NOT_RUN |

Runner: macOS14.8.9/build23J631, ARM64, Apple Swift5.10. Actual temporary PR checkout is `8d0a1aa17b181951f2b45ea3a8f6e5a4e8ba0b3b`, with parents `eba1a4f…` and `c85020b…`; this is not a merge into main. Root fetched the actual Git object and compared all12 build inputs to formal source. The run's PR-base metadata separately reports5a3ab5d; that field is not used to infer actual test input.

[Development App/helper/full-log artifact12724099125](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920/artifacts/12724099125): 1,469,787bytes, GitHub SHA-256 `95d2aad5719216772f2925275354684cb14e9355e90f71cbb59edbceb124497b`, expires2026-11-10. This is an ad-hoc engineering build, not a notarized release. On an authorized Mac, `open build/Riftlet.app --args --simulate` shows the existing isolated quick-swallow/success/rebirth/UNKNOWN demo; Web acceptance remains separate.

### Real failure found and corrected

Initial run40484533371 / job122122896738 at2ddd406 passed its offline steps, then failed native test compilation at `PersistedLogicalDraftIdentityTests.swift:227` because an outer `target(...)` closing parenthesis was missing. Native tests did not execute; panel/Release/self-check steps were skipped. Static review missed this syntax error. Root added the single character, two non-author reviewers checked the correction, and c85020b reran the entire pipeline successfully. No assertion or runtime admission was relaxed. The failed log is preserved in its original run; selected failure lines are also retained here.

## Non-author review and limits

Actual concurrent work was root plus3 independent lanes: Web/legacy review, exclusive Core test implementation plus non-author Models review, and evidence/App review. Root authored the Core/App/diagnostic seam and formal integration. The new Core tests were cross-reviewed by root and the Web reviewer; root's code was reviewed independently. The detailed [review record](review.json) identifies authorship, findings, the syntax miss/correction and evidence-count correction. An initial verbal12/8 file count was corrected by exact Git enumeration to11/7; no source file was missing.

The incoming real evidence establishes one prebound user physical click in an ordinary persisted Chat draft with the editor unfocused, empty text and no old attachments. The valid ACK preceded that event by about8.36s. The3.40ms callback delay is not upload latency; commit queued about2.82s after the event. v6 direct read-only observation kept input count3→3 but returned invalidated/no exact proof. That does not validate full App restart recovery or livev7 observation.

Cold first click, actual business A→B→A/same-URL transitions, preservation of nonempty text/attachments/selection, real MID, physical GUI matrix and full capture latency remain unpassed. The unobservable same-DOM ABA counterexample remains a known FAIL; isolated system screenshot self-inclusion retains its earlier FAIL. Passing a limitation test does not turn its counterexample into safety success.

## Direct next local-Mac increment

Use the final formal PR #1 checkpoint and [uploadStarted v1 §7](../../../docs/UPLOAD_STARTED_CONTRACT_V1.md#7-第四轮合流后的直接接入要求). Implement real per-operation start observation, explicit version/strict normalization and immediate `append` return, then verify start→durable hidden visibility→later ATTACHED/UNKNOWN on the v3 App. Preserve original identity/attachment ID, one input, legacy read-only recovery and independent safe-termination requirements. Do not call input.files/change/placeholder or historical `started` counters admitted start evidence.

**Current Web still does not emit `.uploadStarted`; real fast swallow has not been tested.** Ordinary capture uses UnavailableAdapter. Production upload/start/safe-retry and Web synthetic start/safe-retry maps remain closed. Local Codex owns the real Web implementation/verification; root owns Core/UI/App admission and formal integration. No main merge, release, automatic message send, private image upload or blind retry occurred.

[Machine verification and original manifest](verification.json) · [Independent review](review.json) · [Actual log excerpts](ci-excerpt.txt) · [Original fourth-round evidence](../2026-10-27-real-mac-round4/README.md)
