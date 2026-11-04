# Page recognition and first-click target repair

Base: `1cd7bc9054b07ce6648a9f8bb42b2425b2c8aaad` (merged PR #39).

## Incident boundary

The user reports Chrome Automation granted, repeated
`pageRejected(UNSUPPORTED_TEST_SURFACE)`, then `nativeClickPinRefused`, with no
file input. The reported failure is before input-resource reservation. The
historical error combines URL, top-level, visibility and focus predicates;
it does not identify which predicate was false in that user's click.

The named `/Users/hhf/` logs, diagnostics and production database are not
mounted in this Linux execution environment. They were not read, reset,
modified or replayed. The authorized Browser bootstrap returned missing
originating browser context. No other browser-control entry point is used to
inspect or operate live ChatGPT.

## Baseline counterexamples

[Exact old-source results](baseline-counterexamples.json) bind the original
resource SHA-256. The controlled harmless Home query, identity-proven Project
route candidates and post-capture focus loss all reject before native input.
Hidden/non-top-level pages also reject and must remain rejected after repair.
An unavailable editor and a disabled input previously share one composer code.
These results distinguish source behavior from the unknown historical predicate.

The [HTML focus model](https://html.spec.whatwg.org/dev/interaction.html#focus)
distinguishes a browser tab retaining user attention from its document receiving
keyboard input: a location bar can hold the latter. `document.hasFocus()` is
therefore not the same fact as Chrome being the foreground app with a particular
selected tab. This standard explains why separate native and page checks are
necessary; it does not establish which focus event occurred on the user's Mac.

The [official Projects description](https://help.openai.com/en/articles/10169521-projects-in-chatgpt)
establishes existing/new chats within Projects, but does not specify their URL or
DOM contract. No Project route or React shape in these tests is claimed as a
newly observed production fact on that basis.

## Implemented correction

| Gate | Stable code |
| --- | --- |
| Unsupported official route or other origin | `PAGE_ROUTE_UNSUPPORTED` |
| Non-top-level page | `PAGE_NOT_TOP_LEVEL` |
| Hidden page at discovery/press | `PAGE_NOT_VISIBLE` |
| No document focus and no valid original native-press proof | `PAGE_UNFOCUSED` |
| Missing, blocked or unusable editor | `EDITOR_UNAVAILABLE` |
| Missing, ambiguous, disabled or unusable attachment input | `ATTACHMENT_INPUT_UNAVAILABLE` |

Existing finer ambiguous-composer, unproved business-identity and changed-route
codes remain separate. Legacy `UNSUPPORTED_TEST_SURFACE` is decoded for old
receipts, but the current discovery no longer emits that combined gate.

Route candidates are exact HTTPS `chatgpt.com` Home (including query/hash),
ordinary `/c/`, and Project `/g/g-p-…/c/…` or `/g/g-p-…/project`.
The Project candidates require the existing committed Chat draft profiles;
they cannot borrow the legacy Home header as identity. Every capture and pin
retains unique global editor, local native file input, draft, form and route
continuity checks. A Project-owned chat on `/c/` uses the ordinary proved
conversation contract; no Project-specific URL is assumed for all chats.

Only the synchronous native press path emits `nativePressProof`, with a fixed
kind and the exact current click ID. The route and captured target must both
predate the original event; the pinner checks the live process, foreground
Chrome, selected window and tab again before dispatching to that fixed object.
The native event may be at most 750 ms old at callback start; the bridge has a
separate 750 ms deadline. These are two bounds, not a 750 ms end-to-end promise.
Background same-route polling preserves earlier evidence; an observed native
route change clears the cache and a late different-route receipt cannot seed it.

Initial unfocused discovery still fails. Once captured while focused, the exact
continuously monitored target may survive one focus-loss epoch and receive
distinct fresh native presses, each producing its own one-use, 30-second pin.
Focus restoration, visibility/lifecycle changes or any original identity/node
loss close that exception. Failed unfocused background polling does not erase
the existing trusted target. There is no arbitrary screenshot/omnibox dwell
timeout; every actual press still requires native route proof and continuous
page identity. No code calls focus or activates a browser window.

An App press refusal now writes its closed error label to the bounded critical
diagnostics alongside hashed local correlation, rather than retaining only
`nativeClickPinRefused`. Page text, complete URL, conversation ID and attachment
content are not included.

## Evidence scope

- Exact old source and deterministic page fixtures establish which source
  predicates reject each counterexample. They cannot retrospectively identify
  the user's original predicate.
- Isolated native Chrome uses a fresh temporary profile and loopback synthetic
  application. File, FileList, DataTransfer, DOM, Selection, Blob and Request
  primitives are Chrome's actual implementations. Application handling and
  START/progress are controlled fixtures, with no upload network requests.
- Two of those native Chrome cases deliberately override only the document
  focus read and dispatch a synthetic blur after a real focused capture, to
  exercise two consecutive inputs through the new proof path. That focus
  boundary is modeled; Chrome's FileList/DOM/Selection/request primitives remain
  real, and no physical macOS focus claim follows from it.
- Project candidate routes use the same explicitly constructed, committed Chat
  draft identity as the ordinary composer fixture. A passing candidate does not
  claim that today's real Project DOM was inspected. A Project chat can also
  use an ordinary conversation URL; URL shape alone never establishes membership.
- AppKit tests exercise native panel properties and mouse callback ordering.
  They distinguish down-time target freeze from release-time routing, and are
  not physical mouse/WindowServer or user-machine TCC acceptance.
- Complete native CI includes Core/SQLite, adapter, AppKit, App, Feedback,
  packaging and the existing START/UNKNOWN/independent-input regressions.
  CI results and exact source/package identities are recorded after completion
  in this repair's PR, not predicted here.

## Preserved behavior

PR #39's retained FileList qualification and exact owner release remain in place.
New target qualification does not reserve an upload resource, prove START,
complete an attachment, authorize UNKNOWN replay or send a message. The sole
native file input still rechecks its original target and one-use operation.
Existing content, selection and attachments remain protected. Visual queue exit
still requires the original per-image START evidence.

## Local pre-CI verification

The final bundled-program controlled suite passed 200/200 cases with zero
skips. The legacy observer suite passed 61/61 with zero skips. The current
Chrome fixture parses successfully; this Linux executor has no native Chrome
or Swift, so native Chrome, Swift/AppKit and App packaging are delegated to the
required actual-PR macOS CI. Local skipped Chrome scenarios are not counted as
passes. The source checkpoint and CI/package results belong to the single PR.

## Last real-platform acceptance

The remaining product acceptance is the exact candidate ordinary App on the
user's original Chrome draft: one natural thumbnail press must freeze that
same draft, enter its unique native input once and produce the same image's
START/swallow; a following distinct image must preserve the old attachments,
text and selection. Any refusal must retain its specific sanitized page/native
code. This is one current-candidate acceptance, not a repetition of historical
upload experiments or permission to retry old UNKNOWN operations.
