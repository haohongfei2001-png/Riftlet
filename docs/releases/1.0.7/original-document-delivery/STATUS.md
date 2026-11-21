# Delivery status

Initial baseline checked on 2026-11-21: #119 `c7642464`, #123 `95d8cf80`, #122 `a9a1c03c`, main `9fd8ad15`, public v1.0.5. All three PRs are Draft; #120 remains open. The current architecture decision selects renderer-owned direct file delivery. The prior Edge keyboard counterexample concerns the QA keyboard. Build 54 remains the previous candidate, with its own evidence.

The renderer and ordinary-window harnesses now record the candidate resource hash, the side effects on each document, the saved operation and the result after a same-URL replacement. The ordinary-window record requires separate native samples. The dedicated macOS guest started ordinary Chrome and Edge; its launcher could not establish permission to control either one. Both guest page checks are NOT_RUN. See [guest receipt](../../../../Tests/OriginalDocumentDelivery/guest/guest-capabilities.json).

Build 55 product source is frozen after non-author review. Both engines passed five full-page controlled checks each, including an unlabelled portal and hidden shadow editor. Signed-package and ordinary-browser receipts are recorded separately in the acceptance report.

Both CI architectures caught build 55's first-click size regression. Build 56 addresses that regression with the original 20 KiB assertion in force. The full page resource has the same hash and the transmitted pin measures 19,799 bytes. The build 55 DMG is superseded. Final package and acceptance evidence must identify build 56.
