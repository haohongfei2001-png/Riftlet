# Final-device follow-up: missing Chrome launchDate

Base/original delivered App: `60eaaef64848fc5535580e4fcb65e45f3f41e814`.
Reviewed local correction source: `898f4db733ddb19f60f0045664cc6a8d57fe2a8f`.
GitHub API handoff source: `5d198fd2b998718cce63ac7f62faf97e48d1203f`;
exact source tree equals `43b9ba49562283581b52cc2baca90e4f4bc22e1f`.
The original delivered ARM64 executable remains byte-identical (SHA-256
`f3988e978555b172fc004f42d0e54f7d1ce95e7c61eda791ec30a70ecece3158`).
It was not replaced, relaunched or repackaged in this follow-up. New-source
compilation below is a separate validation, not a retest of that original App.

## What the real device established

The other task finished its shared-profile work. Read-only task and process
checks established normal Chrome foreground, separately from the job profile.
Unlike the previous attempt, resource occupancy was no longer the blocker.

The live Chrome NSRunningApplication had the expected bundle ID and was not
terminated, but `launchDate` was nil. The process was real and responsive: native
AE window/tab metadata reads succeeded. The kernel returned a complete
`proc_bsdinfo` with matching PID and integer birth seconds/microseconds. No TCC,
Chrome configuration, account, extension or profile setting was changed.

Original source rejects this state in ChromeAppleEventsExecutor before page
submission, Main's foreground session, permission receiver selection and Chrome
activity-observer installation. This is a specific supported-process identity
compatibility defect; the safe refusal itself is correct. It is not proof of a
page ACK race, attachment invalidation or selection-collapse cause.

The previously authorized persisted conversation was absent from the restarted
windows. Exactly one owned new window was created and navigated to that original
authorized conversation. ChatGPT redirected it to Home. Existing tabs/drafts were
not changed. Home is outside the original candidate's persisted-target admission;
no initialization message or input was sent and no additional window was created.
The old user-provided system PNG remains available and was never uploaded.

## Minimal correction

- A shared Chrome process identity reads the full kernel record on both sides of
  the application metadata read, validates PID/birth/bundle/liveness and emits a
  versioned integer birth session for **new** captures. A late LaunchServices date
  cannot change this session. No current-time substitute or PID-only identity.
- AE, activity hints, foreground session and permission receiver selection use
  that same identity. Process lifetime is rechecked after queueing, before page
  submission, after receipt and before delivery/publication. AX registration and
  deferred hints recheck too; hints still do not authorize input.
- Old session strings are never rewritten. Only `.observe` can match a legacy
  session, and only against the actual exact LaunchServices date. Kernel birth
  never fabricates a missing old date. Legacy begin/chunk/commit/discard refuse.
  Permission legacy matching only selects a receiver; it is not input authority.
- The existing offline permission self-check fixture remains available, with no
  verified process and therefore unable to pass the native permission checks.
- No Core, SQLite, page program, target/composer/draft identity, ACK timing,
  screenshot source, uploadStarted/completion admission, retry, continuation,
  Feedback or UI change. The separate MacAttachment/M1 process contract is not
  migrated by this Chrome-specific correction.

## Validation and exact limitations

| Check | Result |
|---|---|
| Live nil-launchDate Chrome and responsive AE | MAC_PASS, read-only identity/environment observation |
| Same production identity resolver against that live process | MAC_PASS, tagged identity present and stable; legacy date not inferred; zero UI/input actions |
| Corrected passive permission checker against the same live process | MAC_PASS, granted, same lifetime after return; no prompt/page/input |
| `swift build --target RiftletApp` for corrected source | MAC_PASS, ARM64 compile/link; not packaged or launched |
| Standalone native execution of the two committed targeted test bodies | MAC_PASS, 15 cases / 83 assertions; lightweight assertion harness, **not XCTest** |
| `swift test --filter 'ChromeProcessIdentityTests\|AutomationPermissionTests'` | NOT_RUN: local Command Line Tools lack XCTest; dependency compilation failed before tests |
| New-source macOS CI / full unified candidate | NOT_RUN at this handoff; do not borrow old main CI as new-source proof |
| Real AE queue/receipt interruption with process reuse | NOT_RUN; pure identity change counterexamples and boundary code review only |
| Natural first click / upload / noncollapsed-selection retention | BLOCKED: restored authorized chat redirects to unadmitted Home; no current full target ACK or new input |
| Physical thumbnail click | NOT_RUN |
| Old UNKNOWN/media/queue preservation | MAC_PASS; all candidate tables unchanged, 18 assets / 7 operations / 3 starts; all 36 protected files match |
| Production admission | Remains NO_GO/closed; original historical cold/selection FAILs unresolved |

The targeted cases cover nil/late launchDate, birth second and microsecond
changes, incomplete/wrong-PID/invalid records, wrong bundle/terminated state,
legacy read-only matching, and exact receiver selection with multiple processes.
Non-author review found no blocking source issues; its AX deferred-recheck
suggestion was implemented and re-reviewed. The full target compile exposed an
existing self-check constructor dependency, which was retained safely and then
compiled successfully. No existing source/admission gate was relaxed.

## Integration and remaining device entry

Take only the seven-file correction source above for formal integration; evidence
is separate. Main and formal integration refs were not modified. New App source
review, full CI and original-artifact acceptance remain the formal owner's
responsibility. This source fix does not retroactively fix the delivered 60eaaef
App or establish a successful current upload.

Reuse the retained system PNG (SHA-256
`414eb83b018cfe91c7645d93ea6eb10be0388c5f7c48de918847ef193203beb4`);
no new screenshot is needed. A currently valid, authorized persisted empty test
chat is still required under the original package's admission. Rebind its actual
current receiver/window/tab/document; do not reuse dead IDs or old ACKs. After a
reviewed corrected App is supplied, perform the first visible-condition-driven
native click and original selection observation once, with no ACK-based wait,
message send, Range restoration or old-operation replay.
