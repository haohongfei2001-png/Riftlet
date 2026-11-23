# Riftlet 1.0.8 product closure

## Release decision

Build 62 source is [871187f2](https://github.com/haohongfei2001-png/Riftlet/commit/871187f2be5eada68fccf2adcc07d120991e1c15). The independent reviewer approved tree `f5eb856b9faed30a2ff82e906a081d61647b6f04`. Build 61 could hide Attach Again or reject a new click after confirmation when the original attachment remained in the draft.

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
| Native recovery A–H, including cancellation, stale target, late receipt and relaunch | PASS on the frozen build 62 controlled host. Independent review checked 175 production source files, seven completed scenarios and 1,405 archived files. |
| Original data retention and three historical database copies | PASS. A non-author verified the frozen-source migrations on copies of three sealed build 59 databases, including original operations, invocations, START and PNG identity. |
| Full Swift and web regression, ARM64 and Intel, non-author source admission | 408 web tests passed. Independent source admission passed. Formal Swift and architecture jobs are tracked on PR #125. |
| Signed and notarized DMG, staple, Gatekeeper and independent installation | PASS. The independently installed universal app and the mounted archive matched across 193 entries. Both notarizations and staples were verified. |
| Signed candidate G1 Chrome and G2 Edge on dedicated Temporary Chats | Pending |
| Formal merge, public artifact, signed update metadata and isolated 1.0.5 (31) in-app upgrade | Pending release gates |

The frozen-source native run included the same unconfirmed original operation through the warning, cancellation, explicit re-selection and second START. A separate current named failure returned its own image to the tray. One additional run stopped safely before its second click while the window was gaining focus. All owned windows and listeners were closed. [Native receipt](evidence/build62/frozen-native-recovery.json) · [Independent verdict](evidence/build62/frozen-native-independent.json)

The signed DMG contains 14,225,854 bytes. Its SHA-256 is `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`. Its product source is `871187f2be5eada68fccf2adcc07d120991e1c15`. [Package receipt](evidence/build62/signed-package.json) · [Independent installation](evidence/build62/signed-package-independent.json) · [Frozen historical data review](evidence/build62/frozen-history-independent.json)

The first formal ARM64 and Intel runs failed on the same three XCTest cases. Two expectations still used earlier history states and copy. The third counted the original pending query and a subsequent explicit selection together. The updated case checks each query separately, compares the complete original identity, and verifies that checking completion issues zero browser commands. The correction changes two test files. Formal rerun results are tracked on [PR #125](https://github.com/haohongfei2001-png/Riftlet/pull/125).
