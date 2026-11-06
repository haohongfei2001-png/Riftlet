# History display styles — native implementation

Base: `41217b2dfb5feb0a0d609b7b369d448d8eb5a344`, actual main after PR #44.
The user's earlier `71d726c5` remains the historical Beta 2 base. This increment
does not install, merge main, change capture/attachment architecture, or open a
production database. The installed personal Beta is outside the candidate run.

## Existing design input

The four authoritative design inputs are preserved on
`codex/design-experience-20261107`, originally at
`276574a44485c17821a5ce3e0195116e83e9fad8`, under
`design/experience-20261107/`: `IMPLEMENTATION-SPEC.md`,
`SETTINGS-HANDOFF.md`, `SETTINGS-MAP.md`, and `TOKENS.json`.
Only their history dual-style increment is implemented here. This is not a
settings redesign. The standalone export repair and its browser evidence stay
on the design branch and are not native acceptance evidence.

## Preference and ownership

`historyDisplayStyle` is an independent `UserDefaults.standard` string in
ordinary installed use: `current` or `imageGrid`. A missing/unknown value reads
as `current` without rewriting it. An explicit choice writes only this key.
It is not a `SettingsField`, layout draft, archive transaction, SQLite column,
asset property, migration, or part of Restore Defaults.

`ApplicationController` constructs one lazy `HistoryDisplayPreferences` after
acquiring its existing root lock, before the settings host is installed. Both
native entry points use that same owner. Explicit selections publish
synchronously; defaults notifications re-read only this owner's domain and
publish only an actual change. There is no additional save acknowledgement or
upload eligibility gate.

Review/synthetic modes use a deterministic separate suite derived from the
isolated root path. This allows a same-root process restart to test persistence
without writing the installed application's standard preference. Tests inject
their own disposable suites; no test selects a production standard value.

## Same history, two renderers

`RiftHistoryController` remains the sole history presentation owner. Its
existing page, search, six filters, detail view, original-preview window,
restore/remove/reveal callbacks and eligibility checks serve both renderers.
`current` keeps the existing list columns and layout. `imageGrid` uses an
`NSCollectionView` grouped into today/yesterday/earlier; pictures use Fit.

Selection is now a UUID independent of `NSTableView.selectedRow`. A style
projection does not request another page, refresh the store, rebuild records,
call an action, activate a window or close the original preview. Query/filter,
page offset, selected UUID, preview window/zoom and current window size survive
the change. The grid's larger initial size applies only when it is first opened.

Both renderers use the existing action authority. Restore changes local queue
visibility through the same owner; removal does not delete media or a remote
attachment. Switching display style performs neither action.

## Images and accessibility

The grid has one sequential bounded thumbnail requester using the existing
validated `HistoryPreviewLoader`. Its cancellation state is separate from the
original-preview owner, while both use the existing static serial decode queue.
This lets thumbnails finish while an original remains open without adding a
parallel ImageIO lane. Visible work, item count and decoded cache bytes are
bounded; an already queued original is served before the next thumbnail. Stale
owner/generation and file-identity checks remain in effect. Grid cells do not
create decoders or their own file-import path.

The grid alone uses the approved `#19B7A4` / `#087C70` accents and semantic text
colors; existing global appearance and the default list are preserved. The
official `website-assets/riftlet.svg` is unchanged. State is available as text,
not color alone. Native controls/cells expose identifiers and labels; keyboard
selection and Space open the shared original preview. AX labels and native
keyboard checks do not constitute a complete spoken VoiceOver certification.

## Validation identities

Preference, shared-settings projection, UUID selection, filters/pages, preview,
grid reuse and decoder regression cases live in the existing App/UI XCTest
targets. The formal five-check workflows and source-admission protocol are
unchanged. Build, XCTest, programmatic native control, actual software GUI event,
raw native screenshot and browser evidence are reported separately in the
delivery record. No browser result is promoted to AppKit PASS.
