# Ordinary browser QA window

Before opening a window, call `resolveController(await agent.browsers.list(), family, selected.browserId)` from [controller.mjs](controller.mjs) with the already documented family handle. Two clients advertising the same family are ambiguous. The optional fourth argument accepts the actual tab-v1 mention attached by the user. Only on that path select the unique inventory match, read that client's full documentation, and use `matchReference(await browser.user.openTabs(), result.reference)` to obtain the exact reference for the official claim. A family name, an apparently numeric reference and a synthesized mention cannot establish the association.

After claiming a dedicated window, [native-marker.swift](native-marker.swift) reads the exact target process's kernel birth, its selected native window/tab and the one-time loopback challenge. It requires the installed application path and the challenge returned independently by the official controller. `sample` is read-only. `activate-owned` may foreground that specific application only after the verified QA tab is already selected. All browser UI operations use the official controller. Record `systemForeground` and `exactLocalMarker` at each sample.

Start the service using the signed candidate's installed page resource and its independently verified SHA-256.

```sh
node Tests/OriginalDocumentDelivery/official/server.cjs /absolute/installed/chatgpt-web-20261027.js EXPECTED_SHA256 /absolute/new/receipt-directory
```

The first stdout line contains separate private loopback URLs for Chrome and Edge. Open each URL in its verified, dedicated, normal browser window. Record the original native process/window/tab independently; reconfirm the same identity after the reload.

1. For independent keyboard evidence focus **独立按键框** and enter one real lowercase q. The field records trusted keydown, typed input and keyup observed in that document. General clipboard, scripted text and replaying an old key are outside this check. A missing genuine key is recorded separately as NOT_RUN.
2. Click **1. 验证原稿并挂起旧操作** and **2. 更换文档**. The first action appends a semantic q and a QA PNG through the product receiver, preserving original text, selection and the old attachment element. A distinct authorized operation remains unspent. The second click waits for the server's barrier and reloads the exact same URL.
3. In document B, click **3. 验证旧操作与新草稿**. B looks up the transported old operation in its own renderer registry, then measures zero effects before separately issuing a fresh B operation. The fresh operation must deliver both semantic text and PNG. The final result includes real native file SHA, event counts, document/editor/operation IDs and database-free server timestamps.

Inspect chrome.json and edge.json in the supplied receipt directory. The service writes these atomically as the run advances. Report the browser-specific trusted key status independently of the semantic receiver result. Stop the service after both runs. The fixture provides no browser discovery, remote debugging, authentication, clipboard use or chat submission. It cannot establish a ChatGPT website or signed-app tray result.

The browser loads the full candidate JavaScript with subresource integrity. In each top-level QA document it invokes the unchanged riftletWebAcceptance pinTarget with the real loopback address. The server requires PAGE_ROUTE_UNSUPPORTED, zero file setter / key / input / change / submit events and the unchanged seed, selection and prior card. It records this independently in routeChecks. The origin and URL are never rewritten; only a hash of the private QA URL is retained.

For native correlation, use the independent macOS ID observer and official tab control to capture one A and one B sample while the displayed document IDs match. Save each as JSON using the observed values of doc (full UUID displayed by that page), observedUTC, bundle, sessionID (kernel birth), windowID and tabID (native ID strings). Capture A before clicking button 2 and B after the reload. Then run:

```sh
node Tests/OriginalDocumentDelivery/official/correlate-native.cjs /absolute/receipt-directory chrome /absolute/chrome-A.json /absolute/chrome-B.json
```

The same command takes edge for Edge. A MATCH requires both native samples to confirm the private QA URL and system foreground in the same native process, window and tab. Sample A must precede the original action receipt. Sample B must follow the replacement barrier and precede the completion receipt. The QA page supplies the two distinct document IDs. A tie at millisecond resolution leaves their order unproven. The sibling receipt contains the SHA of the original browser report.

The firstWitnessBoundary field records the first grant created in B. The old operation existed in A and has no entry in B, where a newly granted operation succeeds on B. This controlled observation covers a renderer receiver acquired after the click. The physical click itself is outside the measurement.
