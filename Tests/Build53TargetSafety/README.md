# Click-time target safety in the build 53 page program

On 2026-11-21 the same 13 cases ran in Chrome 157.0.8103.79 and Edge 157.0.4341.60 on macOS. The original product resource passed 10 cases per browser. The independently built test fixture found three cases where the original operation continued sending events after its destination changed. The resource from repair source tree `024a15e9` (published commit `95d8cf80`) passed 13 cases per browser.

| Case | Evidence |
| --- | --- |
| Original composer | The native FileList setter, input, change and send counts were 1/1/1/0. Original text, selection endpoints and prior attachment node survived. Observe and a duplicate commit produced no new input. |
| Tab switch and tab A→B→A | Both pages reported their true visibility and focus. The renderer received trusted blur and visibilitychange. The original operation could read its original draft, but a commit was rejected with 0/0/0/0 in either case. |
| Navigation to the same URL and reload | Each created a distinct document instance at the identical URL. The replacement rejected the original operation ID. |
| History A→B→A | Two navigation entry changes occurred in the same document. Returning to the original URL did not restore the witness. |
| Page hide and BFCache | One case attempted commit in the actual trusted pagehide handler. A separate case restored the exact document and observed both pagehide.persisted and pageshow.persisted. Neither allowed another input. |
| Editor replacement and tab close | A normally rebuilt editor rejected the old operation. A closed QA tab's original pipe session could no longer execute a call. A surviving sibling checked the fixture's origin-scoped counters. |
| Menu discovery spanning a tab A→B→A switch | The product opened the menu while authorized. The fixture supplied the menu choice after the tab regained focus. Build 53 activated that choice, dispatched Escape and restored selection once each. The repair stopped all three. File input counters remained 0/0/0/0 in both resources. |
| Editor rebuilt in the site's input handler | Build 53 proceeded to change. The repair stopped at 1/1/0/0, reported UNKNOWN, and refused another commit on that operation. |
| File portal moved in the site's input handler | The input kept the same immediate parent and HTML form while its enclosing portal moved. The same 1/1/0/0, UNKNOWN and no-reentry outcome held on the repaired resource. |

The browser executed the hash-pinned product JavaScript against a loopback composer with an original FileList setter, file input, contenteditable selection and Navigation API. Only the test's own child process exposes a debugging pipe. Each process gets a fresh, disposable QA profile. Only the nonce-protected loopback fixture can be reached, and cleanup checks the owned process group before deleting the profile.

The fixture supplies the native identity arguments and maps its URL to the supported ChatGPT route for the page program. The fixture counts setter entries and file input/change events throughout the QA origin, plus send-control clicks and form submissions. Each cross-document case uses the original serialized operation without creating a new click witness. These results cover renderer behavior. Native Apple Events, process birth/ID reuse, SQLite, the signed application and authenticated ChatGPT each require their own evidence. No real service upload or login occurred.

## Reproduce

With the installed macOS Chrome and Edge apps and a modern Node.js, run from this worktree:

```sh
node Tests/Build53TargetSafety/run.cjs
```

The baseline runner verifies resource SHA-256 `50b0d16d10f38c688ce33189df55ad3da6588b4c7006b710777f30340dc55ed7`. Its nonzero exit records the three failing cases on the unmodified resource. Provide a separate source root and explicit digest to run the identical suite against the repair:

```sh
RIFTLET_SAFETY_SOURCE_ROOT=/path/to/95d8cf80 \
RIFTLET_SAFETY_EXPECT_SHA256=9b9a1ecd12b8433c7a9243ebedb72fefcc7dc8d69fd2602e4caf895c89b7ab36 \
node Tests/Build53TargetSafety/run.cjs
```

Pass `chrome` or `edge` as a positional argument to run a single browser. A BFCache navigation that reloads the document is recorded as NOT_RUN and yields a nonzero exit. The raw case summaries are in [build53-results.json](build53-results.json) and [build54-source-results.json](build54-source-results.json).
