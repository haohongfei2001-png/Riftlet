# Application appearance preference backend

This implements the nonvisual owner specified in settings revision 2,
`IMPLEMENTATION-HANDOFF` §5.5. It is not connected to Main, a window, a panel, or
the settings UI. No installed application, production data root, system theme,
or current `NSApp.appearance` is changed by this increment.

## File and read contract

`ApplicationPresentationPreferences` accepts an explicit file URL. A future
host supplies its existing data root plus `app-presentation-settings.json`.
The owner does not discover a production root or create directories.

The complete version-1 document is:

```json
{ "version": 1, "appearance": "system" }
```

Only `system`, `light`, and `dark` are valid. Both keys are required; additional
keys, a different version, invalid value types, unknown choices, malformed
JSON, and files exceeding 4,096 bytes are unreadable. A directory or a symbolic
link at the file destination is also unreadable. The owner does not rewrite,
migrate, delete, or repair anything while loading.

| Cold read | Accepted selection | Load state | File writes / appearance callbacks |
| --- | --- | --- | --- |
| Missing file | `system` | `unselected` | None |
| Valid version 1 | Stored choice | `selected` | None; original formatting remains intact |
| Unreadable document | `system` | `unreadable` | None; original bytes remain intact |

This file is independent of the 27-field rift configuration, lifecycle,
capture-entry, arrival-motion, first-use, login-item, and Feedback domains.
Loading or saving appearance never resets their values. The existing geometry
file gains no new key. An explicit successful choice may replace an unreadable
appearance file; opening settings cannot do so.

## Explicit selection and retry

The owner is main-actor isolated and has synchronous, injectable preparation,
application, and file-writing closures. `select(choice)` performs:

1. Retain that exact choice as the pending target.
2. Prepare `NSAppearance` without applying it. `system` prepares `nil`, `light`
   prepares `.aqua`, and `dark` prepares `.darkAqua`. A missing explicit
   appearance is a preparation failure, not permission to fall back to system.
3. Encode the two-key document, atomically replace the file, and set mode 0600,
   following the existing capture-entry preference writer's pattern.
4. Only after the writer returns successfully, accept the choice, clear this
   owner's pending target/error, and invoke the application callback.

The application callback is mandatory and nonthrowing; no default callback
references `NSApp`. Future native wiring can assign the prepared value to the
application appearance. Passing `nil` when returning to `system` is essential:
it clears a prior explicit override instead of retaining its light/dark color.
The callback must apply synchronously on the main actor.

| State | Meaning |
| --- | --- |
| `selection` | Last choice accepted by this owner; not a query of the system or current application theme |
| `lastConfirmedSelection` | Last successfully loaded/saved value, or nil if none; historical confirmation, not a guarantee of current disk contents after an error |
| `loadState` | Result of initial read or the latest successful save; does not replace save-error reporting |
| `pendingSelection` | Latest explicit choice whose preparation/save has not succeeded |
| `failure` | `preparationFailed` or `saveFailed` for this owner only |
| `appliedSelection` | Last choice passed to the application callback; nil before that callback has run |

Preparation or saving failure retains the prior accepted/applied choice and
the same pending target. `retry()` attempts that target once; it does not invert
the visible selection. With no pending target it does nothing. A newer explicit
choice supersedes the pending target. There are no automatic retries.

A failure after atomic replacement, including a later permissions error, can
leave new bytes on disk. `saveFailed` therefore means **persistence unconfirmed**.
It never claims that the old file is still present or was rolled back. The
application keeps its prior accepted/applied appearance until a later explicit
save succeeds. A subsequent process may legitimately read the new valid file.

`applyAcceptedSelection()` is a separate future host startup hook. It prepares
and applies the already accepted choice without any file write, including a
missing-file system fallback. Construction does not call it. A preparation
failure is thrown to the caller. This hook never clears a pending save error or
changes its retry target; a host must not misreport it as a successful save.

## Verification and integration boundary

`ApplicationPresentationPreferencesTests` contains 15 XCTest methods using
isolated temporary files. They cover all three choices; read-without-write;
corrupt/future/extra-key/type/size rejection with preserved bytes; preparation,
save, and application order; real missing-parent and nonempty-directory write
failures; an injected error after an actual file replacement; same-target
retry; clearing an override with `system`; explicit replacement of an unreadable
file; unrelated-file preservation; symbolic-link refusal; and startup-hook
separation from pending saves. Test callbacks record prepared values and never
set the real application's appearance.

Local verification: standalone source type-check PASS, `swift build --target
RiftletApp` PASS, and test-file parser PASS. The installed CommandLineTools
environment lacks XCTest, so the 15 XCTest methods are **NOT_RUN locally** and
must be executed by the existing macOS CI; parsing is not their execution.
No substitute test framework or real appearance change was used.

Native host wiring, settings UI display of this domain's errors, inherited
window/popover appearance behavior, and real light/dark/system acceptance remain
separate work. This owner adds no login-start implementation and no new visual
design.
