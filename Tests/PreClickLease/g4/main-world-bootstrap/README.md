# Native execution world on the owned local file

This macOS QA test asks the build 61 native transport to call a fixed function in a file authored for this test. The only browser choices are ordinary Chrome and Edge. The executable creates its own window, verifies its single new tab, and pins the local file, browser signature and process start. It accepts no caller-supplied page address, window, tab, script or network request.

The builder copies the Core and Adapters trees from frozen commit `49b9204974088c1983cda469910d9a78d8f4c43b` into a private, dependency-free Swift package. It verifies the native transport source SHA-256 and compiles the original file with a QA-only caller appended to the copy. The test executable is a source-level native integration test. Signed-app evidence comes from the separately identified product sessions. [Signed-app command review](../../../../docs/releases/1.0.8/evidence/build61/recorded-product-command-review.json)

The local file contains a single, hash-authorized script. The document prohibits network connections, frames, workers and form submissions. It stores the receipt in a hidden data attribute and leaves the page text empty. No UI link, timer or page-load handler initiates the marker test.

1. An ordinary Apple Event reads the initial document. The test records the file address, navigation entry, time origin and page nonce.
2. The native install action supplies a separate random challenge. Only the local function can acknowledge it. Its caller must present the same global object and XHR prototype captured when the file loaded. The function installs two temporary, nonenumerable data markers.
3. An ordinary Apple Event reads the shared receipt and looks for the exact random marker names in its own global and XHR prototype. A second native submission performs a separate read in the original page, including a newly constructed, unopened XHR.
4. The clear action verifies restoration of the descriptors and removes the temporary DOM node and listeners. A final action retires the receipt. An independent read checks the still-original document for an empty receipt node before the owned window is closed.

Raw window identities, challenges, local file URLs and originals belong in the private QA archive. The projection uses hashes. Per-document Resource Timing, its buffer-full listener and the document's policy-violation counter cover this local fixture. The host's other tabs and browser background traffic are outside that measurement.

The offline controls can be run from the repository root.

```sh
python3 -B -m unittest discover -s Tests/PreClickLease/g4/main-world-bootstrap -p test_verify.py
```

For native execution, `build_local.py` takes a new mode-0700 `/private/tmp/riftlet61-owned-native-*` directory. Its build manifest records the frozen source, fixed fixture, assembled source and executable hashes. The GUI acceptance coordinator checks the interactive session and existing Automation permission and holds the browser QA lock before invoking the executable once per browser. Each phase writes an exclusive receipt. The verifier distinguishes a successful native return, a page-authored response, an original-world read and cleanup. [G4 acceptance report](../../../../docs/releases/1.0.8/G4_FINAL_ACCEPTANCE.md)
