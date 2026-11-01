# Normal-use capture priority extraction

Base: actual main `2fc362a8e5a12b5c833a14e09cf2946afbbd613d`.
Extracted from PR33 source increment `48da85a3220aba8ebe72add507d4fa32dce41107`,
reviewed successor `0691e3a6c5652ad3fe614aed535dd6abc4896927`.
This short branch is not the pending-click experiment and does not enable it.

## Product change

An already observed, original pinned click must not wait for an obsolete target
discovery's remaining receipt-poll loop. Supersede read-only discovery at the
native press and before pinned validate/begin/chunk/commit enqueue. Check its
generation before/after native sends, receipt reads and cache/ACK publication.
Continue using the existing serial transport; input and original-operation
observe/discard do not receive cancellation tickets. A cancelled capture cannot
create an ACK, clear a bound transaction or replay input. App publication retains
an existing ACK only under the original epoch/session conditions.

An already executing native event is not forcibly interrupted. Receipt sends
retain their 250 ms budget; other native calls retain existing timeouts up to
five seconds. No new wall-clock performance guarantee is claimed.

Only eight source/test files change. The page program, MAIN relay, Core,
SQLite, capture/UI, Feedback, workflows and every production admission remain
exactly as main. PR33's witness, pending click, async resolution queue, inline
bootstrap and compiler flag are absent. Its MAIN reentrancy patch affects only
the absent experimental prepareClick path, so importing it would add an unused
experimental capability; it is deliberately not extracted.

## Verification and normal-use admission

Local complete App build and six standalone Swift scenarios using the actual
priority/receipt source pass. Native XCTest covers obsolete/late discovery,
fresh capture, serial input, unaffected input receipt, epoch/session mismatch
and exactly-once scheduler completion. Exact G/H independent review and full
ARM64/Intel/Feedback/source CI are recorded on the resulting Draft PR.

Normal already-open-page AppKit acceptance is BLOCKED at this source checkpoint:
read-only inventory found another active Mac/browser task; no foreground was
taken. No new click timing samples, A-to-B switches, two-image interaction or
restart acceptance were executed. No polling for armed=true or artificial user
preparation is proposed. A future measurement must choose click time from visible
thumbnail availability, retain all failures, and report whether prior page
identity was naturally present. Completely unobserved pages remain a separate,
unsupported boundary; they are not mixed into normal-use success rates.

Existing upload evidence is preserved at its original SHA, not reused as a new
pass. ChatGPT host restrictions remain respected; localhost start/completion is
not real upload proof. No old UNKNOWN, user database, media or screenshot was
read, replayed or changed. Production remains NO-GO; source, retry and Web
continuation admissions are unchanged. This extraction alone does not establish
internal daily-use readiness or authorize a merge/release.
