# Ordinary browser QA window

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

The same command takes edge for Edge. A MATCH requires the same original native process, window and tab with different actual document IDs and the correct ordering around the server barrier. The new sibling receipt contains the SHA of its original browser report. The server cannot assert a native match on its own. firstWitnessBoundary records what is observable when the first grant is created in B: the old object was present in A, B has no registry entry for it, and a newly granted B operation succeeds only on B. This is a controlled observation about the timing of the first witness; it is not a physical-mouse test or evidence of a Riftlet misdelivery.
