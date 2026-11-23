# Offline conditions on two owned local tabs

Chrome 157.0.8103.79 and Edge 158.0.4370.33 each ran in a new headless profile. Each browser had two fixture tabs served by the same loopback listener. An independent Node HTTP client provided the third observation. All three callers sent deterministic synthetic POST bodies. The runner used Chromium's Network backend over the child process's inherited pipe and recorded the exact target, session, main frame, loader and document. The visible Network panel and browser-wide traffic were unmeasured.

| Condition on the target tab | Target tab | Peer tab in the same browser | Independent local client |
| --- | --- | --- | --- |
| Initial condition | 201 | 201 | 201 |
| Offline enabled after the server received a nonempty prefix of each 6 MiB POST | 201, full body matched | 201, full body matched | 201, full body matched |
| New 64-byte POST while offline | Browser reported disconnected, server received no request | 201 | 201 |
| Online restored | 201 | 201 | 201 |
| New 64-byte POST with one exact local URL blocked | Browser reported inspector block, server received no request | Same URL, 201 | Same URL, 201 |
| Exact URL block removed | 201 | 201 | 201 |

At the switch to Offline, the server had read 64,840 target bytes in Chrome and 16,332 in Edge. The server paused its request stream after the first chunk, withheld the response, then resumed reading while the condition was still active. The measured count is the server application's read position. Browser-side buffering and bytes already accepted by the operating system were unmeasured. All three requests in each browser run completed before the runner restored the online condition.

The distinct pre-request result is classified as `CLIENT_REQUEST_BLOCKED_BEFORE_BODY`. The target produced a Network request ID followed by `loadingFailed` with `blockedReason=inspector`. This request had no HTTP status. The two other callers reached the exact same URL and obtained 201. Both browser runs ended with the settings restored, two target closure acknowledgments, the child process group exited, the private profile removed, and zero open server requests or sockets.

The fixture accepts no external addresses, target IDs or script arguments. To run it afresh on macOS with both ordinary browsers installed, use `node run.cjs`. The command outputs the directory of its private evidence. Each completed run records an append-only journal, a second JSON serialization of every retained event, and the summary of expected and received bytes.

The checked-in scope receipt contains the original artifact and source hashes. Decompress each journal with `gzip -dc` to read its sequence of browser, server, client and condition transitions. Experiments apply to the fixed owned local resources. Website card outcomes, other browser profiles, third-party requests, browser-wide traffic, and renderer-process co-location remain unmeasured.
