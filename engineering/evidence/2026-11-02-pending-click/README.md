# Pending native click candidate — 2026-11-02

Base: `2fc362a8e5a12b5c833a14e09cf2946afbbd613d` (PR32 integrated).
This increment does not merge main or enable production. It is **not a completed
cold-first-click fix**. Existing ordinary and restricted system-screenshot modes
retain PR31's exact native pinner and PR32's original receiver observations.

## Implemented and bounded

The pending path requires a disposable build with the explicit compiler flag
`RIFTLET_PENDING_CLICK_LOCAL`, `webAcceptance` / adapter `syntheticDevelopment`,
and the exact owned loopback origin `http://127.0.0.1:18766/c/<uuid>`.
App wiring, adapter methods, isolated witness and MAIN actions enforce these
boundaries. Official builds (including ordinary `--web-acceptance`) retain the
old pinner. The production page program's capture origin is unchanged; local
execution additionally requires the documented disposable fixture overlay. The native press
captures asset, process incarnation, absolute window/tab and a one-use document/
form/editor/file-input witness. It submits MAIN preparation to original A.
MAIN records a specific state and pin; it does not export the full TargetLease
at this boundary. A five-second runtime ticket awaits the original nonce reply
and resolves that exact state off the main thread. It cannot bind a later
registry tail, recover after restart, replay a receipt or create a durable intent
before promotion. Existing Core dispatch, validation, single-input, start and
completion rules are unchanged.

Hide/remove/termination/original receiver denial cancel pending authority. A
new accepted press cancels an abandoned same-asset down/up-outside ticket; release
requires the exact current press ID. The existing UI freezes visibilityRevision
before onPress and keeps the reservation through release and asynchronous work.
Original matched-state blur recovery uses the existing continuous lease renewal;
it cannot install a successor for an invalid old state.

An initial review caught tail substitution, undrained mutation records, ancestor
removal ABA and abandoned-press reuse in the WIP. Those are addressed before any
external input. Original document references are checked by a one-use isolated
listener which drains MutationObserver records in the MAIN preparation event.

## Verified scope

- Local macOS `swift build --product Riftlet`: PASS.
- Local complete release App packaging, resource checks, ad-hoc signature and
  ordinary binary policy identity: PASS (not launched into the shared desktop).
- Production page-program deterministic suite: 140 cases PASS; retained legacy
  read-only suite: 61 cases PASS. These are component tests, not MAC_PASS.
- Two real headless Chromium 151.0.7922.34 isolated-world/MAIN channel cases:
  fresh fixture without registry, prepare original click, request B bringToFront
  after 50 or 200 ms, resolve only A, one file-change, synthetic final attached; A
  controlled text preserved, B zero file-change, zero send. See results.json.
  Only owned loopback HTTP was permitted; no ChatGPT or user profile access.
  A separate no-input calibration showed this headless backend keeps BOTH pages
  visible/focused after bringToFront. These cases therefore prove realm/channel
  and identity integration, NOT actual background-tab/OS-focus behavior. Hidden
  and blur behavior is covered only by deterministic fixtures in this increment.
- Local XCTest: NOT_RUN, Command Line Tools cannot resolve XCTest. Formal
  ARM64/Intel/Feedback execution is required on the reviewed PR merge.
- Actual AppKit mouse → pin → input performance and all three real desktop switch
  variants: NOT_RUN in this increment. Read-only task inventory showed concurrent
  Mac/browser diagnosis tasks active. No foreground was taken or coordination
  message sent. No synthetic component timing is presented as native latency.
- Physical mouse: NOT_RUN. ChatGPT: BLOCKED by host policy; not accessed.

## Remaining safety/product boundaries

1. **Not zero main-thread work.** Absolute native routing, document witness and
   first MAIN preparation submission remain synchronous with a cumulative native
   event deadline of 150 ms. CPU work is not a hard real-time bound. Full receipt
   waiting and target decoding are asynchronous. There is no truthful nonblocking
   click-time tab identity API in the current bridge; cache freshness and a later
   active-tab query cannot replace it. No imperceptible-latency claim is made.
2. **Before first MAIN monitoring**, an opaque business replacement on identical
   DOM nodes cannot be proved absent by a document/node witness. A deterministic
   counterexample deliberately demonstrates that limitation (zero file input).
   Hence the new mechanism stays compiler-gated and loopback-only; it is not enabled for real
   screenshots or admitted as a general cold-first-click solution.
3. The narrow foreground-check → javascript URL setter interval can still race
   a switch during first channel installation. This increment does not claim
   focus preservation in that interval. Once preparation completes, resolve is
   absolute-addressed, never installs, never queries the current active tab and
   never selects or activates A.
4. FIRST MAIN missing when preparation executes hidden is a no-input refusal.
   Existing-state delayed receipt → background resolution is supported in the
   component evidence; it is not proof of arbitrary zero-observation success.

The public results contain generated fixture counts/times only. Full local
logs, fixture sources and artifacts remain private. No old media/database,
UNKNOWN, source admission, safe retry or continuation was changed. Production
remains **NO-GO**. Do not integrate this branch as production cold-click admission.
