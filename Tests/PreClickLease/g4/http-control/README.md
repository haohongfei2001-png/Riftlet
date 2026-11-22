# Native XHR HTTP response control

From the repository root on macOS with ordinary Google Chrome installed, run:

```sh
node Tests/PreClickLease/g4/http-control/run.cjs
```

The runner opens a fresh headless Chrome with an inherited debugging pipe and a disposable profile. The test server listens on an ephemeral IPv4 loopback port. Each case receives its own page and upload route. The fixture has a form, a file selector, a preview state and a send button. The driver selects one real synthetic 1×1 PNG through the browser file-input API. The page sends that File in one native XHR PUT. The server consumes the whole body and computes its own SHA-256.

The 413 case uses a server limit one byte below the 70-byte file. The 503 case simulates a locally unavailable service. A 201 case verifies the normal branch. The runner checks the response against the server's observed bytes, accepted request count and file hash. It verifies trusted input/change, OPENED through DONE, the response-bearing load and loadend, zero send-button clicks, zero submits and unchanged fixture draft text. It verifies that the only browser page action selecting a file targets the new fixture tab. Browser process ownership and listener cleanup use the repository's existing helper.

The JSON on stdout is reproducible browser-and-server evidence. File selection is driven by the browser test API. A local error or accepted card is rendered by this fixture's own code. Signed Riftlet, SQLite, and ChatGPT's website and servers are outside this test. The published receipt records the separately reviewed historical site evidence and the limits of the official product documentation.
