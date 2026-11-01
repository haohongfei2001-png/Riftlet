# Prebinding delivery scheduling — 2026-11-01

Base: `aa0f40f341777ebeb2513996bde07c30893ec0d9` (PR #29 already integrated).
This short-lived increment does not repeat its AX notification fix.

## Implemented changes

1. Complete the scheduler, validate the capture's epoch and foreground, and
   publish the actual ACK before `updateSetup`. That presentation path enumerates
   screens/display UUIDs and synchronously updates settings controls. Previously
   all of it preceded the ACK. The ACK timestamp is still the real MainActor
   assignment time; native arrival and the original event are never substituted.
2. When a replacement capture is pending, schedule it before auxiliary AX binding,
   recovery and settings work. Swift Task enqueue order is not claimed to guarantee
   priority on the serial Apple Events queue.
3. Do not start original-operation recovery from the first stale startup capture
   while a replacement is pending. Defer at most once; a current completion
   (including capture failure) or the next stale completion releases recovery.
   Thus continuous window changes do not indefinitely suppress original-ID-only
   observations. Existing transport timeouts remain; no new timer, cancellation,
   retry or permission cache is introduced.
4. Consume an empty recovery list without launching a permission check or remote
   observation task. Nonempty recovery retains its independent permission check.

## Verification and limits

- Local ARM64 product compile: PASS (`swift build --product Riftlet` with external
  scratch directory; Command Line Tools). No App was launched.
- Deterministic regression source covers the original-event/ACK boundary,
  stale/current completions, repeated invalidation, editor-focus hints,
  consecutive capture demand, and bounded recovery deferral. A source-order
  assertion checks the private App wiring; it is not an AppKit runtime test.
- Full Native ARM64/Intel, Feedback and mainline G/H source admission: see exact
  Draft PR checks and admission record; they must be complete before integration.
  This document does not predeclare their outcome.
- Live Chrome natural first click / physical mouse: NOT_RUN; no new authorized
  independent upload target was used. Real upload acceptance remains BLOCKED.
- No new measured latency, first-click success rate or MAC_PASS is claimed.

## Remaining boundary

The fixes remove avoidable work after a complete capture and ahead of its pending
replacement. They do not make an incomplete Apple Events capture into proof.
A press before the actual accepted ACK remains safely refused, even if delivery
of that mouse event is delayed until after the ACK. A changed window/tab/document
still requires the original-target checks; no click is retained or retargeted.
Existing capture-durable, Chrome activation/window hints and pointer-approach
triggers remain in place. The scheduler's existing single-flight/coalescing and
permission publication rules are preserved.

No screenshot, media, database, UNKNOWN or historical operation was opened or
changed. Core, adapters/page program, receipt policy, UI geometry and upload
profiles are unchanged. Ordinary production, safe-retry and Web continuation
remain closed (NO-GO). Integration belongs to the formal lead after exact-source
review and all five formal CI jobs; this increment stays a Draft PR.
