# Independent attachment lifecycle repair

Base: `4c3175dd3c537466279d27844466fbe65f79eb6e`. This increment changes product
source, not the screenshot format or the user's interaction contract.

## Changes

- The original START still atomically swallows only its own screenshot. Backend
  completion, UNKNOWN and late compensation are independent of that visibility.
- New ordinary operations can retain separately admitted browser input ownership
  through UNKNOWN/compensation. This reuses the existing original invocation,
  native click pin, continuation scope, SQLite and attachment-alias checks.
- A request-owned continuation requires the one original File, exactly one native
  request preceding START, exact bytes/hash, synchronous change return, current
  own attachment and the original live append. Browser request IDs are never
  represented as server task/finalization identities. Origin-scoped native
  profiles require this specific evidence variant.
- Shared input remains serial until the original bounded append releases it.
  If that call has returned without sufficient isolation, a subsequent prepared
  operation is refused immediately and visibly before any new invocation/input;
  it cannot remain at the head of the queue for 30 seconds or block another chat.
- A scaled, mismatched or unreadable completion preview leaves COMPLETE unproven
  without invalidating the original attachment. Ten fixed diagnostic labels
  distinguish proof unavailability from target/member/identity failure. Exact
  completion and safe-retry requirements are not relaxed.

## Reused actual platform facts

`research/web-attachment-handoff-2026-10-27/evidence/exceptions/main/identity-observation.json`
records A/B input on the same input node 44.7 ms apart, two simultaneously
uploading cards, B's final preview while A is still uploading, then both retained.
The three-input trace and final composer snapshot in that package retain all
three attachments and original text/selection. These are archived Chrome Home
Chat observations, not new acceptance of this source on a persisted thread.

The HTML files setter replaces the control's FileList. It does not append an
application attachment list. File/Blob bodies are immutable; XHR/fetch extraction
owns the request body independently of a later FileList. Application-specific
append behavior comes from the archived platform observations, not those browser
specifications alone:

- https://html.spec.whatwg.org/multipage/input.html#dom-input-files
- https://w3c.github.io/FileAPI/#file-section
- https://xhr.spec.whatwg.org/#the-send()-method
- https://fetch.spec.whatwg.org/#concept-bodyinit-extract

## Current reported defect and read-only verification

The supplied user account described one swallowed UNKNOWN plus four selections
expiring without input. A subsequent authorized read-only Mac inspection found
one UNKNOWN plus six failed selections, each expiring after 29.969–29.998 s. The
original target still belonged to its draft when invalidated; no explicit upload
error was recorded. Its journals were schema2 and had no original-File request
evidence. This does not prove why that request was unobserved. Raw operation,
target and media identifiers, private text and screenshots are not published.

The concrete preview-proof defect is independently reproducible, and the existing
`2026-11-01-completion-proof` sample documents a real scaled preview. Neither fact
alone identifies the exact cause of this user's unqualified invalidated label.

## Validation scope

Local Web regressions: 225 passed, no skipped (164 current, 61 legacy).
New SQLite/coordinator tests cover 2/3/5 operations across START, UNKNOWN,
COMPLETE, safe-failure and compensation, rebirth requiring a new click,
late/misbound receipts, request/attachment alias rejection, restart, unchanged
historical UNKNOWN and the exact repeated-selection expiry regression. Adapter
tests check the strict schema and the separate non-START proof failure labels.
Native XCTest, AppKit, both architecture packages and source-admission results
are recorded on the formal PR for the exact final source, not asserted here.

## Remaining platform limits

No new ChatGPT browser interaction was performed. The Browser connection did
not expose an originating context; no shell/CDP/Apple Events fallback was used to
bypass it. The online Mac supports native compilation; formal XCTest needs the
full-Xcode CI runners. Production data and historical media were read-only.

An upload using copied/rewritten Blob/FormData, cached transport functions or
another path without the exact original File request cannot acquire this
continuation proof. The user's original schema2 operation lacks that proof and
is not retroactively unlocked. Its later screenshots receive accurate immediate
feedback, not a claim of successful input. Current persisted-thread safe overlap,
scaled-preview platform finalization and irreversible post-START failure
retirement still need their actual facts. This PR is a bounded implemented repair,
not a claim that every current ChatGPT upload path is fixed.
