# Beta 2 real-environment acceptance and bounded repairs — 2026-11-07

Base main is `71d726c5d6416346b84e1ac93047af5bb321d925`; installed personal Beta2 is 0.2.0 (2), ARM64 binary `e0505af18b2828c3acf88477e6fbb382c975c9097b1de1a222a19e5383e36c39`. The user has approved the appearance and assigns all executable acceptance to Codex. This increment does not redesign settings, attachment input or source admission.

Native testing now uses the complete target application's `AXExtrasMenuBar`, exact native target identity and fresh hit testing before software-generated OS `CGEvent` down/up. Actual WindowServer windows, AX controls and a separately owned synthetic-window receiver distinguish event delivery from direct AppKit target-action and from physical hardware. Existing permissions were read without prompting. The initial menu-bar hit guards correctly refused hidden/occluded coordinates; original failed attempts are retained privately. Browser use remains disabled, so no alternative interface controls live Chrome or uploads into an unknown conversation.

## Confirmed failures and minimal repairs

- A status popover opened while another application stays active does not close on a click delivered to that already-active application. The receiver recorded the exact mouse-down/up marker; the same popover remained on screen after settling. Observe only other applications' mouse-down while shown, remove the observer on close/suspend/deinit, and reject a queued callback from an earlier presentation. No keyboard monitoring or application activation is added.
- With settings still open, the first Pause click activates the application and can start a source recheck between mouse-down and mouse-up. The first click left Pause off; a second click paused and persisted. Keep the existing queued-intent path available during recheck instead of disabling native tracking. Execution remains exclusive, and a pending collection command still prevents another command/recheck.
- `SMAppService.notFound` was treated as an unconditional prohibition before an explicit register call. A separate ad-hoc probe reproduced notFound, then registered successfully, read enabled, unregistered and read notRegistered. The actual old owner refused before calling this service; the repaired owner completes the same real probe lifecycle. Allow only an explicit enable from notFound, retaining real status/error readback, unknown/unavailable restrictions and no automatic registration. The production login item has not been registered by the agent.

- A button-only popover may remain non-key after explicit opening. Original Escape events reached the previously active owned fixture, even when AX/frontmost snapshots suggested Riftlet focus. A separate no-editor AppKit comparison proves that `makeKey()` gives the shown popover the keyboard route and native Escape closes it. Make only that explicitly opened window key; do not add global keyboard monitoring or change attachment targeting. This can make Riftlet active while the control center is open; it is not a claim of zero focus change. The full repaired App is undergoing the same bounded check.

## Candidate verification already observed

The first complete repair candidate, source `1cfbe674f0439cd4446c527a98f716e3ac23a8af`, binary `7509a1b4ff9c9b7aef17bc75e9efa088e8f8f1b2b3ec35b512fb2023f5c411d3`, uses an isolated settings-review root. AXPress opening followed by a fresh hit-checked global CGEvent outside click closes its popover; the independent receiver records the same marker. A single real Pause click now changes both the control-center and settings projection. Pause/hidden combinations, resume, settings/history routes and right mouse menu opening have corresponding event/state evidence. A left click closes the shown popover. An occluded subsequent menu-bar click is NOT_SENT, not a product failure. These results are controlled GUI automation, not physical hardware or a production attachment certification.

The installed Chinese Pinyin input method produced marked text, Chinese selection and mixed input in an isolated native Feedback editor. Closing during composition preserves it with a completion prompt; committed text persists across reopening, with zero submitted reports. Actual isolated archive-save failure preserves the draft and domain error across another setting's success. Retrying persists the original 3.5-hour choice while retaining a newer 4.5-hour draft; normal save then persists that draft. VoiceOver was enabled through its normal System Settings switch and verified running, then restored off. Limited actual output was observed, but full navigation and auditory acceptance remain unverified. No new system permission was granted.

## Current evidence boundary

The installed App has received an actual macOS Cmd-Shift-4 screenshot of an owned synthetic window. Its file has `kMDItemIsScreenCapture=1` and the original/media SHA agrees; a new visible asset was added while old operations/START/UNKNOWN remain unchanged. The system file appeared after the initial bounded poll, whose no-file result remains preserved. This does not claim a new ChatGPT attachment, setter/change or START. A transient source-unavailable message was observed around resume/recheck, followed by successful collection; its cause is not yet attributed to TCC or a product defect.

This source checkpoint is under native candidate verification. New full XCTest, five CI checks, independent exact-source admission and any replacement installation have not yet been completed. Earlier successes, visual approval, hardware/IME/VoiceOver limits and raw failures retain their own identities. No raw screenshots, private chat content, production databases/media or machine secrets are committed here.

## Final runtime candidate in this source increment

Runtime source `c3af6757634ad742a0988bc9dda87aad2a8b22e4` produces complete ARM64 binary `d41d0a819cb447f08a701713d68d7017683f2dabe0d5122ee7d084ec11a7e54f`. In its isolated root, observed global Escape closes the shown popover, and matching global outside mouse input closes it. Single-click Pause and Resume update both UI projections; an actual right click opens the native menu. This is controlled software GUI input, not hardware. `makeKey()` may activate the explicit control center; it is not a promise that focus never changes. No browser/chat identity assertion is made while browser access is disabled.

Additional status-cycle attempts remain inconclusive: one hidden-menu hit was refused before posting, and an AXPress sequence did not establish alternating visible windows. Those records are not converted into PASS. Earlier observed individual transitions and the independent AppKit key-window comparison remain separately identified.

[The source-checkpoint summary](acceptance-summary.json) binds sanitized private evidence hashes, preserved failures, candidates and limitations. `PERSONAL_BETA_2_ACCEPTED` remains false: this round has no fresh real ChatGPT double attachment and no complete VoiceOver acceptance. Four bounded repairs are ready for independent exact-source review and the existing five-check CI; the production install is unchanged at this checkpoint. No new notarization, public distribution, hardware, service, sleep or monitor-hotplug execution is claimed.

## First formal CI and test-lifecycle correction

[The preserved CI failure record](CI-LIFECYCLE-REGRESSION.md) records the first
PR #44 attempt, including the same immediate-deallocation assertion failure on
both architectures. A bounded asynchronous release assertion retains the full
cleanup checks without changing product source or the verified candidate App.
Local probes did not reach the required shown state and are not passing
lifecycle evidence. A new independently reviewed source checkpoint and all five
formal checks are required; the old failed attempt is not relabeled as success.
