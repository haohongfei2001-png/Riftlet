# Delivery status

**BLOCKED_TECHNICAL — 1.0.7 build 56.** Frozen product commit `2717fa6aaa7cb3750041ca1a0779c6dab65961cc` passed ARM64 and Intel CI. The universal app and disk image are signed, notarized, stapled and installation-verified. Ordinary Edge passed the two-document QA case. The normal local Chrome instance is ambiguous. Strict cold click-to-first-document identity and all three ChatGPT site gates remain open. The public release remains v1.0.5. [Acceptance and package identity](TARGET_DELIVERY_ACCEPTANCE.md)

## Checkpoints

Initial baseline checked on 2026-11-21: #119 `c7642464`, #123 `95d8cf80`, #122 `a9a1c03c`, main `9fd8ad15`, public v1.0.5. All three PRs are Draft; #120 remains open. The current architecture decision selects renderer-owned direct file delivery. The prior Edge keyboard counterexample concerns the QA keyboard. Build 54 remains the previous candidate, with its own evidence.

The renderer and ordinary-window harnesses now record the candidate resource hash, the side effects on each document, the saved operation and the result after a same-URL replacement. The ordinary-window record requires separate native samples. The dedicated macOS guest started ordinary Chrome and Edge; its launcher could not establish permission to control either one. Both guest page checks are NOT_RUN. See [guest receipt](../../../../Tests/OriginalDocumentDelivery/guest/guest-capabilities.json).

Build 55 product source is frozen after non-author review. Both engines passed five full-page controlled checks each, including an unlabelled portal and hidden shadow editor. Signed-package and ordinary-browser receipts are recorded separately in the acceptance report.

Both CI architectures caught build 55's first-click size regression. Build 56 addresses that regression with the original 20 KiB assertion in force. The full page resource has the same hash and the transmitted pin measures 19,799 bytes. The build 55 DMG is superseded. Final package and acceptance evidence must identify build 56.

Build 56 DMG SHA-256 is `4d20dc369e6cf548c57def04a1975201333503f5fe69e3b47b7a32fa0ef56b98`. Independent installation, signatures, stapled tickets and Gatekeeper passed. In ordinary Edge a trusted q reached the original fixture. The pending original operation produced zero effects after a same-URL reload. The independent native marker matched before and after the reload. Two clients advertised the Chrome family; the ordinary Chrome selector could not prove ownership. The verifier now rejects that ambiguity before opening a window. It accepts an explicit instance only if a genuine user-attached tab reference identifies it.

Independent offline replay of the original Edge measurements passed the stricter foreground, URL and timing requirements and reproduced the archived receipt byte for byte. The dedicated Edge window and loopback service have closed. The Chrome launch request still has no confirmed window identity.
