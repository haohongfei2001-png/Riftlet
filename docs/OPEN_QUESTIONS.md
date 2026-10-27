# Open questions — research history and current engineering gates

**2026-10-27 update:** development is authorized. The [actual scoped Web handoff](../research/web-attachment-handoff-2026-10-27/README.md) has now been obtained, independently reviewed and integrated into an explicit generated-image Web acceptance mode. The missing prerequisite is now the online Mac test of this integrated program, accurate click-time target capture, safe production consumption/recovery and separate retry admission. It is no longer a missing-source or missing-plan task. See [the execution checkpoint](EXECUTION_BOARD.md).

**Historical 2026-10-26 factual questions (read alongside E04/E05):**
1. Real ChatGPT web: does selected DOM/FileList or native path append the new image into the **correct composer** without replacing text/attachments?
2. Can the system positively match the **specific new attachment** to READY/ERROR, not just placeholder or send-enabled?
3. Can the installed new ChatGPT Mac app's AX tree show a sufficiently strong per-image READY signal? Classic is separate.
4. Rapid clicks, multiple tabs/profiles/windows, navigation, failures, crashes: can the same target be protected and unknown results reconciled without blind duplicates?
5. System screenshot to private copy timing, system floating thumbnail, self-capture of the rift, fullscreen/multi-Space/other monitors.

**Still to design:**
6. Slit line, true coin-size, partial occlusion and hit targets, numbers and animations.
7. Rare 10+ queue case without making recently added image hard to hit.
8. Close/hide, remove/delete, archive of already swallowed images; minimal management window.
9. Meaning of UNKNOWN and user-visible feedback without adding an interaction step.

Historical phase at this list's creation: formal development was not yet approved. **Superseded by P09 on 2026-10-27**; native foundations now proceed in parallel with scoped validation. Visual candidates and upload admission are still not final.

## 2026-10-27 — autonomous execution treatment

P12/P13 authorize routine decisions and parallel work without the user's participation. The questions above are not a queue of questions to send back to the user. The lead uses these conservative defaults and continues the [execution board](EXECUTION_BOARD.md):

| Unresolved item | Work that proceeds now | Waiting condition applies only to |
| --- | --- | --- |
| Integrated Web real target/completion/recovery evidence | Actual handoff archived and replayed; bundled program + native acceptance mode built/tested | W2 live integrated verification and success/retry enablement; exact tab capture and late-failure revival remain unresolved |
| Mac client AX/input evidence | M0 target/pasteboard ownership logic and synthetic tests | M1 actual input/AX completion and per-surface support |
| Real first-click, transparency, Spaces/displays/self-inclusion | U1 helper, U2 deterministic tests, Capture recovery fixes | The specific N1 GUI/system acceptance claim |
| Final geometry/animation/Logo | Adjustable R2 01 defaults; no final approval label | Visual/brand finishing |
| Overflow and UNKNOWN presentation | Keep all images, continuous numbers, current configurable window/unknown marker; refine within the two-action product contract | Evidence-based refinement of those mechanisms, not unrelated implementation |
| Archive/delete/management window | Preserve originals and used private copies; implement accounting and storage-error behavior | Automatic cleanup or extra management UI |
| Signing/public release prerequisites | Repeatable ad-hoc app, CI evidence and permission/install documentation | Formal distribution |

Known correctness defects are handled immediately within their affected changes. Waiting for a machine or proof never becomes permission to claim a test passed, lower the swallow threshold, overwrite another draft or auto-retry UNKNOWN. Record an exact resumption trigger and move to another READY task; do not repeatedly recheck an unavailable environment or ask the user for the same decision.

## 2026-10-27 — fast-swallow product decision: resolved principles and remaining evidence

See the authoritative [interaction contract](INTERACTION_CONTRACT_2026-10-27.md) and USER decisions P16–P22 in [DECISIONS.md](DECISIONS.md).

**Decided:** click once; click-time **current** supported ChatGPT draft, not fixed or guessed; actual upload start triggers **very fast visual swallow**, before READY; only explicit/extremely high-confidence actual failure rebirths; UNKNOWN after start stays hidden in internal local history; no auto re-upload; stale visible screenshots auto-archive and can be singly/bulk removed; no visible screenshots means **no trace of the slit**.

**Still unapproved/unverified:**
1. Per-surface *positive* upload-start observation and timing; neither an issued click nor a placeholder counts automatically; W2/M1 still need measured evidence.
2. Objective, replayable conditions for **extremely high-confidence actual failure**, late errors, user-initiated attachment deletion, and safe explicit retry without duplicates.
3. Durable queue/UI state split: visible vs swallowed/unknown/used/archived; no indefinite same-draft blocker for **other distinct images** while preserving original operation observation and wrong-target protections.
4. Archive idle duration and UI; single/bulk remove behavior and private media lifecycle; how to view/restore hidden uncertain images. No invented automatic deletion policy.
5. Real first-click/current-window capture, speed of swallow animation, no slit when empty, visible queue rebirth after delayed failure, restart and multi-Space evidence.

**Engineering scope:** this documentation update does not implement those state-machine migrations, revise production evidence registries, or validate macOS/Chrome behavior. Existing CI and past ATTACHED/READY results remain scoped to the old implementation.

## 2026-10-27 — additional decisions: corrections to outstanding product questions

Latest **resolved product behavior** is in [INTERACTION_CONTRACT_2026-10-27.md](INTERACTION_CONTRACT_2026-10-27.md) and [DECISIONS.md](DECISIONS.md) P23–P28:

- Faster near-consecutive multi-image clicking is an optimization **only without sacrificing experience or stability**, not an unconditional parallel-upload requirement.
- No success toast; the actual ChatGPT draft attachment communicates progress/completion to the user, who chooses when to send.
- Once failure qualifies for rebirth it is an **ordinary immediately clickable** screenshot with normal remove/archive lifecycle. Do not substitute non-clickable failed rows or suppress rebirth due solely to elapsed time/context change.
- No usable current composer/attachment entry means **no swallow/no disappearance**; once uploaded to the draft, the image stays hidden from the rift unless genuine failure qualifies for rebirth. Original macOS screenshot and local Riftlet history are retrieval paths.
- Clearing the visible queue does not remove attachments from ChatGPT.
- Press-and-hold drag is **CONSIDERATION_ONLY**, pending interaction and AppKit testing; not approved for launch.

**Still a technical validation question, not an invitation to reinterpret the user decision:** classify explicit/extremely high-confidence failure precisely enough that **reborn images are clickable for a genuine new user attempt** while the UNKNOWN class does not produce unwanted duplicates. Tests should include late success/late failure, composer absent or lost, burst clicks, and clearing during a started upload.

## 2026-10-27 — release UX feasibility follow-up (user-confirmed scope)

**No longer a product-choice question:** a usable current ChatGPT composer must accept **one Riftlet click without pre-focusing the text field**. No composer/unsupported surface must not swallow, but must give small press/reset feedback. Auto-archive must defer during hover/press/transition. Other consumer usability/maintenance goals are confirmed in [RELEASE_UX_REQUIREMENTS](RELEASE_UX_REQUIREMENTS_2026-10-27.md).

**Requires independent feasibility research:** Do existing Apple public APIs or tested mechanisms allow the ordinary macOS system Screenshot.app to omit Riftlet's own floating thumbnails across all supported shortcuts/modes? Existing Round 2 observations suggest self-inclusion; ScreenCaptureKit's client-local window exclusion must not be mistaken for a system-wide guarantee. See [Pro brief](PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md).

**Tests still pending:** Web and Mac clients must prove focusless click in existing drafts, including sidebar/text selection and first-click races; screenshot inclusion must be investigated per OS/capture source/permission without timing guesses. Hover/press archive suppression is implementation work, not a previously verified feature.

## 2026-10-27 — Pro feasibility study received

The independently supplied Pro review concludes Web composer **unfocused field** attachment is **conditionally feasible**, with outstanding click-time authority and cold first-click timing; Mac native remains unproved; no supported universal exclusion of Riftlet from Apple's ordinary system screenshots has been established. Invalid-click press/reset and non-interrupting archive are low-/medium-complexity candidates. The precise engineering handoff and source/evidence limits are recorded in [PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md](PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md).

**Do not relabel this as PASS.** The PDF referenced in the user-pasted Pro response was not uploaded into the present tool session. Web physical cold first-click, native-client AX attachment, self-capture source isolation, production uploadStarted swallow and archive-interaction cases remain pending real-environment validation. Do not reopen the settled user product choices, or force a new screenshot shortcut/engine for window exclusion.
