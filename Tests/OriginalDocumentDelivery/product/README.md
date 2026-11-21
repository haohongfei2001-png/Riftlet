# Full product page program after an origin changes and returns

The runner loads the complete supplied product resource and calls pinTarget, captureTarget, begin, chunk, commit, read-only observe and a duplicate commit. It uses a fresh file, operation ID, invocation ID and original click for each case. The script runs in a disposable real browser engine, on a loopback fixture with a controlled route/native argument as in the existing page-program regressions. These results measure the product page program. The ordinary application’s native click path and live website each require separate receipts.

| Scenario | Signed build 54 resource in Chrome and Edge | Build 55 source resource in Chrome and Edge |
| --- | --- | --- |
| File input's container leaves its original parent during input, then returns to precisely the same place before the event ends | change still fired. Setter/input/change/send were 1/1/1/0 | UNKNOWN, 1/1/0/0 |
| Original editor loses focus to a second editor and regains it before commit, in the original visible focused document | The old operation wrote once, 1/1/1/0 | The witness retired before input, 0/0/0/0 |
| Normal local attachment menu with a prior attachment and text selection | Once-only open, option, picker invocation and file delivery with 1/1/1/0 | Same once-only result. The original text, selection and attachment node survived |
| Independent textarea inside a closed shadow below a plain div in the original contenteditable | The old operation wrote 1/1/1/0 after focus returned | The original click retired with zero setter/input/change/send. Trusted inner focus and blur, external retargeting to the host, and native focus back to the original editor were measured. |
| Pointerdown synchronously opens an unlinked body-level menu and moves focus to its item | The original normal menu behavior completed once and preserved text, selection and prior card | The original entry opened once. Its menu option mounted and invoked one responsible input, 1/1/1/0, preserving the same draft state. |

The intermediate resource `0dcface2` had fixed the first two cases but allowed the closed-shadow focus round trip and rejected the unlinked menu. Across both browsers the signed build 54 resource passed 4/10, that intermediate resource passed 6/10, and the resulting `61669b50` resource passed 10/10.

Every case refused another commit of its original operation. The focus case verifies actual trusted focusin events delivered to both exact editors and an unchanged active document. A native focus round trip can change the selection itself; only the uninterrupted menu control is subject to the original-selection assertion. The portal case compares the final DOM lineage and sibling position inside the synchronous input handler.

## Repeat on an installed candidate

```sh
node Tests/OriginalDocumentDelivery/product/run.cjs chrome /absolute/path/to/chatgpt-web-20261027.js
node Tests/OriginalDocumentDelivery/product/run.cjs edge /absolute/path/to/chatgpt-web-20261027.js
```

Use the JS file under the installed application's RiftletAdapters resource bundle. Each invocation reports its resource digest and exits nonzero if any expected invariant fails. Both variants use the installed browser engines' normal sandbox; only the owned child’s inherited debugging pipe is attached. [Build 54 package and build 55 source comparison](source-comparison.json)
