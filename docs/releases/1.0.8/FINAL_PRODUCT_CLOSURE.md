# Riftlet 1.0.8 product closure

## Release decision

Public stable remains 1.0.5 (31). Build 61 has a confirmed recovery defect. Choosing Attach Again after the duplicate warning can still refuse a fresh click when the original attachment remains on the same draft. The history action checks local records before the warning and does not inspect the original card. A source fix requires a new signed candidate, build 62.

## Acceptance contract

One screenshot click hands the original image to the exact draft. A positive, persistent START records the handoff. ChatGPT controls subsequent upload and the user controls sending. A failed preflight leaves the image available. A reliably attributed failure returns the image. An uncertain result preserves the PNG and the original invocation until the user handles it. Reattachment requires a new click bound to the same document, composer and draft generation.

The observed Chrome double-click intervals for build 61 were 581.676, 569.889 and 619.928 ms. The Edge intervals were 551.605, 568.999 and 549.887 ms. These results belong exclusively to build 61.

Real ChatGPT named upstream failure cards and upstream HTTP 4xx lack acceptance evidence. Historic G4 experiments remain archived. The release decision uses the product's recovery behavior, including positive and negative cases, through the native UI, isolated local page and real SQLite. Third-party network fault injection is retired from the required gates.

## Required evidence for build 62

The history action now inspects the original browser process, window, tab, document, composer and draft generation before offering reattachment. If the page still shows a matching card or filename, the default action returns to the draft. Cancellation leaves the old invocation alone. Confirming prepares the image for a separate desktop click with a new operation, invocation and click binding.

The local copy remains protected when the latest observation actually reports uncertainty. A normal accepted handoff still reads “Handed to ChatGPT”. A named failure on the original member returns the image to the queue. A late error for a superseded invocation is recorded against its own operation without changing either attempt or entering the file setter.

The controlled native suite uses the production history window, mouse handling, adapter, coordinator and SQLite. A separate test host supplies the local browser receiver and isolated storage. The signed candidate uses ordinary Chrome and Edge for site acceptance. Raw screenshots and databases are private. The [twelve-question audit and release-scope review](https://github.com/haohongfei2001-png/Riftlet/tree/358320c9976046287c37e35e1bf656e4599241f0/docs/releases/1.0.8/evidence/build62) document the build 61 baseline.

| Gate | Status |
| --- | --- |
| Native recovery A–H, including cancellation, stale target, late receipt and relaunch | Eight cases passed on the build 62 controlled host. Match the final source and independent audit before release. |
| Original data retention and three historical database copies | Independent migrations and retention controls passed. Match the final source before release. |
| Full Swift and web regression, ARM64 and Intel, non-author source admission | 408 web tests passed. Formal Swift, both architecture jobs and the source decision are tracked on PR #125. |
| Signed and notarized DMG, staple, Gatekeeper and independent installation | Pending |
| Signed candidate G1 Chrome and G2 Edge on dedicated Temporary Chats | Pending |
| Formal merge, public artifact, signed update metadata and isolated 1.0.5 (31) in-app upgrade | Pending release gates |
