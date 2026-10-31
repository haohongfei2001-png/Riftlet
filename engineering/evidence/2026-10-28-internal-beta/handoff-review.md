# Internal Beta — non-author handoff and scope review

Reviewer: `/root/beta_feedback_review`.

Reviewed committed source: `70cf5881e07ad18f44c96aa3e7200d3be3df2b04`.

Tree: `5d970fd354f1a4a8c70b0ec0b1a027825944f8b5`.

Parents, in order: `c177174e400064d8ec8bb79685c33d01c4e93b89`, `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`.

## Conclusion

**PASS for source/handoff consistency, with two minor wording clarifications recommended below.** No claim of the final combined CI or downloadable artifact being verified is made by this review; those actual results will be reviewed separately. The worktree was clean at the start. No worktree, Git, index or product source was modified by the reviewer.

## Reviewed material and checks

Read `docs/INTERNAL_BETA.md`, the current boundary in `AGENTS.md`, current top sections in `docs/VERIFICATION.md` and `docs/INTEGRATION_HANDOFF.md`, and the complete packaged `packaging/internal-beta/README-zh-CN.txt` plus candidate launcher. Compared the H summary with its original README/result/timeline, the instructions with the actual ApplicationMode/startup/menu logic, and Feedback statements with the source review already completed.

Independently executed the actual committed `python3 -B scripts/verify-internal-beta-integration.py`: **31/31 checks PASS**. It resolved this exact commit and both merge parents; official e421, c177 acceptance, and f195 feedback are ancestors. All pinned screenshot and feedback directory objects and the original H evidence tree match. The 16 original App files other than Main/FeedbackHost are unchanged. Main is exactly the reviewed blob `5b1c64348cc0661f0de359c45a54158e828d6c22`; separate `git diff --numstat e421 70cf588 -- Sources/RiftletApp/RiftletMain.swift` confirms 20 additions/1 replacement.

The audit uses actual committed objects, rejects missing paths, and disables Git replacement objects. It does not derive expected sources from PR metadata or dirty files. The CLI does not expose source-pin overrides. No unrelated or previously completed test suite was rerun for this documentation review.

## Accurate source and evidence boundaries

- c177 is described as the direct child of e421 with seven evidence-only files; the integration preserves the feedback ancestor and does not repeat old screenshot source.
- H actual runtime is explicitly e421, not this combined Beta. It remains one new PNG/software CGEvent/prebound-ACK sample, not a new physical mouse, cold-first-click, network failure or broad release acceptance.
- The README and detailed handoff separate AppKit measured animation duration (126.964 ms) from original click to WindowServer first absence (about 2.72 seconds). Exact sRGB content comparison, sampled preservation and independent completion are correctly distinguished.
- Old A/D/F UNKNOWN records, locks, media and audit preservation remain explicit. H is already input and cannot be replayed. The docs do not request another H upload, retroactively enroll F, unlock old records or fabricate a start.
- The final macOS Native/Feedback runs are required to identify the exact final source and artifact. Prior e421/f195 CI is not represented as execution of this combined source. Expected test composition is clearly labelled as expected rather than already-passed final results.
- Safety failure/retry and ordinary production uploads remain closed. Current Chrome Chinese ordinary persisted threads and corresponding RGBA8 PNG bounds are not enlarged to Home/Work, arbitrary PNGs, other browsers or native ChatGPT.

## Real App and founder entry

- The documented artifact is the complete `Riftlet-Internal-Beta.zip`, not the isolated Feedback Demo or only a test report.
- The candidate launcher resolves its adjacent full App and passes exactly `--system-screenshot-candidate`. It does not change the default mode, alter the candidate data root, enable private trace, kill processes, bypass permissions or reset data.
- The documentation correctly says double-clicking the App alone opens ordinary capture, while the explicit command entry launches `Riftlet REAL TEST`. The existing menu alternative, required adjacent files, previous-instance exit and first-use/permission controls are described.
- The actual App displays onboarding for first-use modes that collect screenshots, including the candidate. The Chrome automation/Apple Events setup is not silently bypassed, and no extension or automatic message sending is requested.
- Development ARM64/ad-hoc/not-notarized status and separate Finder/Gatekeeper first-install scope are disclosed. Only normal system approval paths are suggested.

## Feedback scope

- The handoff correctly identifies the unchanged delivered Feedback modules and independent feedback database/Keychain/diagnostic whitelist.
- Endpoint remains nil; Cloudflare/D1/Issues have not been deployed/configured. Explicit Send freezes a local queued report; it is not cloud success or proof the developer received it. Draft save/close/reopen does not send.
- The current implementation permits no new screenshot target, ACK, input, state-machine or queue mutation through the diagnostic hooks. The documentation does not claim actual zero latency or real GUI/Keychain acceptance merely from software tests.
- Physical Feedback close/reopen/IME/VoiceOver, Keychain permission/restart, click-latency comparison and cloud E2E remain separate product-quality checks.

## Minor wording recommendations

1. Packaged README says `只有主动勾选并预览的白名单诊断会被放进这份反馈`. The actual implementation freezes the snapshot on opt-in; opening the preview is available but not an enforced prerequisite. Prefer `只有主动勾选的白名单诊断会被放进这份反馈，可在发送前预览`.
2. `docs/INTERNAL_BETA.md` says diagnostics do not collect `原图、正文、路径...`. Replace `正文` with `聊天正文` so the statement cannot be confused with the deliberately user-entered feedback text.

These are documentation precision improvements, not reasons to redesign Feedback or the screenshot lifecycle. They were sent to the integration lead for the final documentation checkpoint.
