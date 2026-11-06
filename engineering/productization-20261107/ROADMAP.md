# Productization sprint — 2026-11-07

User-authorized window: 2026-11-06 23:10:34 UTC to 2026-11-07 09:10:34 UTC, or earlier when all independently executable high-value work is complete. This is an active work plan, not a claim of ten hours already run.

| Packet | Owner | Scope | State |
|---|---|---|---|
| P00 | root | Reconcile actual main/App, prior Beta3 delivery, open PRs/worktrees | DONE_BASELINE |
| P01 | root | Current-version isolated ChatGPT acceptance and START/final semantics | Browser part BLOCKED_TOOL_POLICY; semantic audit ACTIVE |
| P02 | root | Actual desktop/control center, isolated raw WindowServer baseline for Pro | ACTIVE |
| P03 | diagnostics | Login service and first-use permission audit; repair only new confirmed defects | ACTIVE |
| P04 | root then free lane | Real4K/different-aspect100-history performance, bounded long run/recovery | READY |
| P05 | readiness_independent | Signing/notary prerequisite audit, ZIP/DMG/manual update | ACTIVE |
| P06 | review | Consumer support/privacy/install docs, source-verified scope | ACTIVE |
| P07 | review | Closed Beta10–20 participant package, no invites/telemetry/public download | ACTIVE |
| P08 | root + non-author reviewer | Exact-source review/admission, fiveCI, safe integration, final A/B/C verdict | READY_AFTER_PACKETS |

All source changes stay on short-lived branches from actual main. Each packet preserves evidence and commits a reviewable result. Root alone operates foreground GUI/Chrome and production lifecycle. Do not queue GUI requests to the user. No automatic public release, invitations, paid-plan changes, production data reset or blind UNKNOWN replay.
