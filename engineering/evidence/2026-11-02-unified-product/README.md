# Unified product implementation — 2026-11-02

Base: `a4463cddd3bce637dbe0a33c90713bc42370ed8f` (read back from GitHub).
Branch: `codex/riftlet-unified-product-20261102`.
This is implementation evidence, not real ChatGPT acceptance or release approval.
Exact source G, tree and independent review are recorded by admission-only H in
`engineering/mainline/source-admission.json`; the PR records actual CI runs and
their App artifacts. Earlier passes do not certify this new source.

## Implemented behavior

- Continuation compares the original Chrome process/window/tab/document/composer,
  stable draft epoch and recognized logical draft identity across distinct click
  pins. It never substitutes one pin in another receipt. The original invocation
  must have returned admitted START plus independent continuation evidence under
  the same coordinator owner. Legacy/missing evidence, restart and changed drafts
  remain locked. The Web producer still grants no continuation authority.
- Attachment aliases are rejected across those pins, including completed and
  compensated originals, completion without START, and records outside the first
  64 metadata rows. Keyset batches bound memory without deleting history; scans
  can still be linear in retained operation count.
- Ordinary capture uses the existing Web adapter. System and built-in sources
  have distinct profiles and origin-bound v2 dispatch registrations, but share
  transport, original target, SHA validation, queue and read-only recovery. New
  local identities and persisted identities are separately recognized, never
  converted into one another. Synthetic sources cannot borrow these profiles.
- The existing strict original PNG limits remain: single-frame, noninterlaced
  RGBA8, at most 8 MiB and 16,777,216 pixels. Built-in edited derivatives retain
  their actual application source and bytes; unsupported files are retained.
- START and COMPLETE are independently normalized and persisted. App composition
  configures only the new source-scoped product profiles. Historical input-only
  registrations can still be observed in their original journal but cannot be
  promoted to admitted success. No candidate database is moved or merged.
- A versioned proof can retire the still-running original append after commit
  only when the page irreversibly retired the operation, its asynchronous work
  settled, and it never entered the File setter. Setter entry is a sticky fact,
  including a setter that changes files then throws. Identity and invocation must
  exactly match the durable dispatch intent. Lost replies, old UNKNOWN, recovery
  observations and any possible input remain UNKNOWN. This is proven **no input**,
  not permission to retry an uploaded attachment.
- Packaging and source checks match these actual compiled capabilities:
  ordinary input/start/completion and built-in source enabled; post-input safe
  retry and Web continuation disabled. The default policy remains empty outside
  explicit composition. Arbitrary evidence-looking hashes grant nothing.

## Verification at source checkpoint

- Local ARM64 source build and ad-hoc package/layout/signature/policy checks:
  PASS. The built App was not launched against user data or Chrome.
- Targeted JavaScript, packaging and mainline-isolation regressions: PASS; exact
  suite output is retained in local logs and repeated by the formal CI.
- New native regressions cover per-origin normal composition through START,
  independent COMPLETE, durable restart, original-input deduplication, legacy
  input-only UNKNOWN upgrade, cross-pin alias ownership, and exact no-input
  retirement versus lost commit/late recovery. Native execution is pending CI
  at this checkpoint: the local Command Line Tools installation lacks XCTest.
- Full Native ARM64/Intel, Feedback and actual-merge source admission must all
  pass on this exact successor, independently of the above local build.
- Real Chrome/ChatGPT input, upload, physical interaction and final unified-App
  platform acceptance: NOT_RUN / PLATFORM_BLOCKED. No alternate browser or
  native mechanism was used to evade the existing page-access restriction.

## Unimplemented evidence producers and release boundary

This does **not** complete all requested product capabilities. The page currently
does not expose a verified platform attachment identifier plus authenticated
original-file/finalized-result response to this implementation. A downsized
preview cannot establish full original pixel identity. A re-encoded preview can
qualify only through the unchanged equal-dimension, exact sRGB RGBA comparison;
this does not claim server-side original-byte preservation. A failing proof
remains UNKNOWN. No pixel
tolerance, larger data limit or progress-100 shortcut was added.

Likewise, the current DOM facts do not prove terminal request retirement with no
automatic retry, nor that a later input cannot replace/cancel a pending prior
attachment. Therefore real post-input safe retry and the Web continuation
producer remain absent, despite the corrected Core consumer. New user clicks
can recover only strictly proven pre-input failures. Historical UNKNOWN and
possible external input never acquire retry authority.

These missing platform facts need an explicitly permitted real-page evidence
source and independent producer/consumer verification; adding invented response
fields would not solve them. This branch does not claim production GO, public
release, real-world upload PASS or completion of the full product request. It
does not create a second product tier. Preserve all historical media, databases,
UNKNOWN, source audits and main; no browser session or original data was touched.
