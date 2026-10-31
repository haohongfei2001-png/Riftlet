# Internal Beta — independent real fast-swallow evidence archival review

Date: 2026-10-28 (Asia/Shanghai)

Reviewer: `beta_evidence_review`, a non-author of the acceptance execution and integration source changes.

**Decision: PASS for faithful formal archival of the existing limited real-Mac acceptance. No new admission, retry, production, physical-mouse, or release approval is granted.** No blocking inconsistency was found in the seven public handoff files, their Git ancestry, or their relationship to the unchanged tested source.

## Review authority and limits

I read `AGENTS.md`, all seven files in `engineering/evidence/2026-10-28-system-screenshot-swallow`, the relevant current target-freeze/ACK publication code, v2 registration policy and ordinary/candidate composition. I inspected Git objects and independently checked 19 numeric, ordering, identity-summary and scope invariants in the public JSON. I did not alter the integration worktree or index, operate Chrome or a Mac, upload a screenshot, read the original private screenshots/full identities/SQLite snapshots, or claim to rerun native tests.

The public handoff intentionally contains bounded assertions and hashes rather than private target identities or raw image/database content. The original `review.md` records a separate `native_gui` non-author reading of those private originals, including all 84 indexed items and eight original screenshot hashes. This review verifies that public handoff's consistency and archival suitability; the original private-data assertions remain attributed to that local evidence and its recorded review.

## Exact ancestry and source preservation

- Handoff commit: `c177174e400064d8ec8bb79685c33d01c4e93b89`.
- Its sole parent: `e421e6687651c2fac1441410c1af2bd5b8151e55`.
- Its tree: `5e64df4a262d0786f528d1ac112236cc7bf75c1d`.
- The complete parent-to-child diff consists of seven added files under the one evidence directory, with no deletions or changes elsewhere.
- `Sources`, `Tests`, `Package.swift`, `Resources`, `.github`, and `scripts` Git objects are identical between e421e668 and c177174. Therefore archiving c177 must preserve its actual ancestry, without replaying or rewriting the already integrated source.
- The handoff correctly identifies actual runtime e421e668, reuse of successful CI `40674197202`, and a separate local full App build/bundle check. It explicitly says it did not rerun the 457 native tests in this acceptance session.

## Evidence findings

### 1. New screenshot, target and unique input

H is reported as a new genuine macOS selection screenshot: 1652 × 1010, 1,789,589 bytes, PNG RGBA8/color type 6, noninterlaced. Its 1,668,520 pixels and file size lie within the existing restricted admission limits. Native screenshot metadata is recorded. Original and private-file SHA-256 are both `43721c40157a71eeb54751d8bd35d06a1dad250432559e4fe4a5b1178e53de2a`.

The public identity assertions consistently describe one new operation, attempt 1, a different persisted ordinary Chinese ChatGPT draft from every legacy operation, and complete click/operation/page/registration target equality. The pre-input checks and the original private review record original asset/hash, ordinal, native window/frame, Chrome foreground PID and sampling readiness before the one software down/up pair.

The effective ACK is 35,635.339 ms before the original event; its MainActor publication is 35,635.338 ms before it. These are separately labelled rather than conflated. `freezeAccepted`, matching host/foreground session and original target are reported. A refresh in flight did not supply retroactive click authority. Existing source explicitly preserves the effective timestamp when an identical armed target is refreshed, checks original-event ordering/epoch/session, and clears authority on invalidation. The old timestamp alone is therefore not evidence of a late ACK bypass. This remains a prebound case and proves no no-ACK cold-first-click result.

Input counters agree: 1 begin, 7 chunks, 1 commit, page input count 1, independent change count 1. No automatic Send or second H input is claimed.

### 2. Start and completion remain independent

Strict start is an increasing progress observation on the original attachment node, 4.710072392734034% → 9.420144785468068%, with input sequence 2 and start sequence 16. It occurs 1,995.7 ms after page input. This is not a start inferred from setting the file, a placeholder or a single uploading flag.

The final sequence independently progresses through 100% at 30, progress-ended at 41, final load at 42 and strict proof at 44, 7,345.0 ms after input. Original nodes/source/identity and no operation error/invalidation are recorded. Start precedes completion in both sequence and duration; the v2 qualification is never described as either proof.

The independent explicit sRGB RGBA comparison records zero differing channels out of 6,674,080, exactly `1652 × 1010 × 4`, with matching full RGBA digest `9642bb7d677b407adca96515d302ac9b97bfb45e7e654df172bc00f6e01fa826`. Preview-file SHA-256 is `d6e9df91276abf75e6b0e9de246dbd6763aac20279724b9eafda95e534d43c11`, also present in private index entry E074. Different original/preview PNG bytes are disclosed; neither server-original-byte preservation nor approximate pixel matching is asserted.

### 3. Actual animation/window disappearance and durable result

The native timestamps form a coherent causal sequence: click at 0; commit execution 492.393–579.482 ms; swallowed persistence observed by 2,559.124 ms; AppKit scheduled at 2,559.618; actual animation starts at 2,559.649; close called at 2,686.613. Their measured difference is exactly 126.964 ms, distinct from the 0.120 s configuration.

All three original WindowServer windows were present at 2,700.388 ms and first absent at 2,720.581 ms. The handoff records 2,315 valid queries, zero failed queries, no reappearance and Chrome foreground throughout those queries. These are actual window-presence observations, not a claim of per-frame visual sampling or precise compositor presentation time.

The first observed durable start has `transferring/swallowed`, revision 1 and one `upload_starts`; the final result is operation `succeeded`, asset `used`, visibility still `swallowed`, reason still `uploadStarted`, revision still 1, with no second animation. Ready persistence is observed by click +8,105.598 ms; the listed final consistent SQLite read ends at +8,107.809 ms. Both are correctly presented as observation upper bounds rather than an exact commit timestamp.

For founder-facing wording, the rapid animation is approximately 127 ms; the measured complete click-to-window-absence was approximately 2.72 seconds in this one sample. Do not present 127 ms as click-to-upload or click-to-disappearance.

### 4. Draft, old operations and local data preservation

The recorded checkpoints preserve a nonempty 48-character body, the original editor's noncollapsed selection 8..11, one stable old attachment and message nodes. Attachment count goes from one to two. Twenty-four post-input snapshots and the final snapshot agree; the old attachment's prepared bytes equal its final preview bytes. The editor was not focused before input. First observed page focus loss occurs at input +12,537 ms, after final proof at +7,345 ms; it is not misreported as uninterrupted focus throughout the full collection period.

The preserved candidate data root grows from 6 to 8 assets and 4 to 5 operations, correctly explaining the additional oversized 11,489,808-byte screenshot naturally collected on startup without any selection, operation or input. The only new operation is H. The separately prepared small generated old attachment is disclosed and not counted as H's real-system input.

Old A/D/F remain original-identity/attempt `unknown`, visible and locked, with no v2 backfill or first-start rows. B remains failed. Old assets, 14 checkpoints, compensations and private media hashes are reported preserved. Observation-only changes are accurately disclosed: A updated_at/reason, D updated_at, F updated_at/receipt_json/reason. F's latest invalidated observation does not erase its old first start/attached observations, imply a new failure admission, unlock it or retroactively succeed it. The handoff does not claim every old database row stayed byte-identical.

## Privacy and public evidence integrity

All seven public files were read. They disclose aliases, bounded facts, timings, source hashes and an opaque E001–E084 hash/length index. I found no raw screenshots, chat text, local private paths, full target/session/tab identities, authentication data or database contents. The 84 IDs are unique, sequential and have valid 64-character lower-case SHA-256 values and nonnegative byte lengths. Duplicate digests for identical private objects are not duplicate evidence IDs.

The public files currently have these SHA-256 digests, suitable for confirming verbatim archival:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| README.md | 7295 | `fe2693e65ade26f3b65432b81fbe8075715fbaa90463b8568d477916c9aacf4f` |
| data-preservation.json | 1249 | `e07114e523af7c6c7f616834810913b4ab1790c7b34e3100d51340743481c714` |
| private-evidence-sha256.json | 12319 | `2a9ef2734f57f9e0aac61dc0018ad137c2c9e7f03da579902146a1ba63c2a7a7` |
| result.json | 3157 | `ece5d1323abb7c2da1ac7122def61fc5952d0be2ba48d6b81e2bccd4f0e3cf1a` |
| review.md | 1698 | `042453ae3876c84eb6febf1fb88925e7a096102f17e6d39edd9fa9d7873ed199` |
| timeline.json | 2266 | `9708eb38f9aaf2df3ab84de1436fea3c0e05690e7e6f4a48b70ab76686477cd3` |
| verification.json | 420 | `6a2584b26c0d0b38916aad0ac34413a5b86c42032467a469cfbb773e317af88a` |

## Boundaries to retain in the integration handoff

- Limited PASS: this single new H, macOS 27.0 (26A428) arm64 / Chrome 156.0.8078.73, ordinary persisted Chinese ChatGPT chat, existing v2 scope, valid prebound software CGEvent original click, unique input, strict start, actual AppKit/WindowServer disappearance, independent completion and preserved local/draft data.
- NOT_RUN: manual physical mouse and per-frame pixels; no broader multi-screen/fullscreen/Spaces or network-fault matrix follows from this case.
- Unresolved: no-ACK cold first click. No late ACK may authorize the old original click.
- Closed: ordinary production uploads, safe-failure and safe-retry admission. No automatic resend, database reset, old UNKNOWN unlock/clear, media deletion or F/legacy re-input.
- The new Feedback-integrated Beta must get its own accurate CI/package/source record. This archived acceptance ran e421e668 and must never be relabelled as a fresh real-Mac run of the later combined executable.

## Nonblocking documentation actions for the integration lead

Update the current top-level status in `AGENTS.md`, current admission/handoff docs, execution board and verification overview, which still say the e421 fast-swallow interaction needs a different new screenshot. Replace that current-state sentence with a link to c177's now-recorded limited H result while keeping prior historical records intact. Retain these seven original handoff files byte-for-byte, rather than rewriting the original execution narrative to describe the new Beta.

No product-source change or further screenshot upload is requested by this review.
