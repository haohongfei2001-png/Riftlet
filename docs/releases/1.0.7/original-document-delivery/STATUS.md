# Delivery status

Initial baseline checked on 2026-11-21: #119 `c7642464`, #123 `95d8cf80`, #122 `a9a1c03c`, main `9fd8ad15`, public v1.0.5. All three PRs are Draft; #120 remains open. The current architecture decision selects renderer-owned direct file delivery. The prior Edge keyboard counterexample concerns the QA keyboard. Build 54 remains the previous candidate, with its own evidence.

The renderer and ordinary-window harnesses now record the candidate resource hash, the side effects on each document, the saved operation and the result after a same-URL replacement. The ordinary-window record requires separate native samples. The dedicated macOS guest started ordinary Chrome and Edge; its launcher could not establish permission to control either one. Both guest page checks are NOT_RUN. See [guest receipt](../../../../Tests/OriginalDocumentDelivery/guest/guest-capabilities.json).
