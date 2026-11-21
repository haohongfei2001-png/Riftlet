# Build 53 live draft QA

The two previously recorded operations can be read from the isolated build 53 QueueStore without opening either browser. Supply the original QA root, operation UUID and PNG digest to `python3 read-operation.py`. The command verifies the candidate executable, then returns a sanitized record for that operation. The two captured records are in [build53-exploratory-store.json](../../docs/releases/1.0.7/evidence/build53-exploratory-store.json).

The public Browser client exposes provider tab IDs in enumeration results. Its standard `tabs.new()` has no dedicated-window option, and a controlled Tab's optional `windowId` is unavailable on the extension backend by default. The canary uses the advertised `management` capability on the selected external browser. For an explicitly requested family, use the official client's initial selection and documentation step in the connected session:

```js
const chrome = await agent.browsers.get("chrome");
nodeRepl.write(await chrome.documentation());
```

For Edge, acquire its separate persistent handle with `const edge = await agent.browsers.get("edge");` followed immediately by `nodeRepl.write(await edge.documentation());`. Read the complete output before using the handle and consult the advertised management capability documentation. Supply that same `browser`, `browsers: agent.browsers`, `bundle` and optionally `browserID`. The harness checks the selected handle's ID and family against discovery metadata. A failed bootstrap can be classified with `browserHealth({connectionError: error})`. An unknown family, missing trusted RPC or absent window-management capability stops before creating a window.

Call `browserHealth(options)` from `browser-preflight.cjs` for a read-only precheck. It returns only status fields. `openVerifiedWindow(options)` creates one normal QA window with a single blank tab, verifies its frontmost native process/window/tab, then creates a uniquely named tab group on that tab. The fresh group membership binds the public tab reference to the native window. The reference ID, provider ID, claimed handle ID and native window/tab IDs are recorded in their own domains. The guard rechecks the claimed handle/provider association, original group and native selection without retrieving unrelated user-page contents. The returned lease exposes only identity, a guard, and a once-only `closeBlank()`. Close the test blank with that lease after checking it. A lost creation, claim or close reply must not trigger another attempt.

Supply an independent `readNative(bundle)` callback returning the current foreground bundle, kernel-birth session ID, window ID and selected tab ID as strings. Build the identity-only observer with `Tests/LiveDraftAcceptance/build-front-identity.sh /absolute/path/to/front-identity`. It sends one PID-addressed Apple Event requesting the selected tab descriptor with interaction and permission prompts disabled. Keep native and opaque identifiers local.

### Signed-in keyboard precondition

The normal `createLockedDraft` and `withLockedDraft` entry points currently return `BLOCKED / ORIGINAL_DOCUMENT_KEYBOARD_UNAVAILABLE` before creating a window or opening ChatGPT. On the real Edge QA surface, a retained tab keyboard action delivered a key to the focused editor in a replacement document. Repeating native or page checks before that call cannot make the delivery conditional. A live sender must enforce the original native target, document generation and editor in the operation that actually delivers the key. Generic tab, Accessibility and process-addressed keys cannot open this gate. G1/G2/G4 require separate live runs after such a sender has passed the replacement case.

The live entry selects an adapter from the module-owned reviewed list before opening a window. The list is empty for the current release. A successful resolution feeds the same draft workflow used in contract tests. The adapter owns New chat, editor focus, keys, selection and exact-target close. Caller-supplied writers and capability flags cannot enable the live entry.

The separate `test-support/isolated-draft.cjs` adapter operates in memory and has no live registration. It checks native identity, navigation, document and editor at each simulated delivery. Tests replace the target between precheck and delivery for New chat, editor focus, seed keys and selection. Fixture outcomes do not count towards live acceptance.

If Edge shows the generated QA filename but the signed App has no START, `edgePreviewShape(generatedName)` requires the observer's `locateOriginalEditor(tab, target)` to return the original native and draft identity fields, tab/window handles and a locator uniquely bound to that composer. Each sample uses a read-only evaluation on the original locator and requires the same foreground identity before and after sampling. A collector lacking that locator cannot collect the shape. The diagnostic samples the original editor's visible matching preview and its bounded ancestry. It records source type, current/declared source equality, decoded dimensions, child counts and placement of the same-file Remove control. Original URLs, pixel data, message text and generated filename are excluded. No observation of this shape was possible on the historic attempt.

`node --test locked-draft.test.cjs` runs an isolated fake browser with deliberate focus/identity changes. It does not exercise browser keyboard delivery or establish G1/G2/G4.

On the normal Mac installation, run `node Tests/LiveDraftAcceptance/installed-controller.cjs` before browser setup. It reports only counts and transport availability. `READY_FOR_RPC_CHECK` requires a running browser, a correct native manifest and an enabled extension in at least one existing profile. Extension state alone cannot establish a trusted connection or tell which profile is connected.

For a fresh Edge diagnostic, use `observeEdgeTimeline({run, readOperation, operation, png, targetSHA256})` from `edge-timeline.cjs` after identifying the single signed-App operation. Supply an asynchronous, time-limited reader of the isolated store through `read-operation.py`. The collector calls only the locked page observer and that reader. Each joined sample requires the same process, native window/tab and original document/composer/generation. A timeout keeps any completed page half and ends the run without another call. Page and store read boundaries use a monotonic clock starting at the first diagnostic read. Stored START and the latest store update have separate times relative to operation creation. A START already present on the first poll is known only to have existed by that read. Page preview shape and a store START row remain separate observations.

### Native permission preflight

Compile the read-only diagnostic in the QA checkout and run it from the same execution context as the proposed native collector.

```sh
probe_dir="$(mktemp -d)"
xcrun clang -Wall -Wextra -fobjc-arc -framework AppKit -framework ApplicationServices -framework Carbon \
  Tests/LiveDraftAcceptance/native-permission-preflight.m -o "$probe_dir/preflight"
"$probe_dir/preflight"
```

Keep PIDs local. The result identifies the calling helper, its parent and each already running Chrome/Edge receiver. An empty target list means there was no running receiver to check. AX and CoreGraphics report the helper's current access. An Apple Events result of zero means macOS permits querying that PID with `core/getd`. None of the probes posts events, requests consent, or establishes tab-directed keyboard delivery. macOS keyboard posting accepts a process or application as the destination. Changes to the active tab can occur after a focus check, so signed-in keyboard acceptance requires an original-document-bound delivery mechanism. [Apple AX keyboard API](https://developer.apple.com/documentation/applicationservices/1462057-axuielementpostkeyboardevent) · [Apple CoreGraphics keyboard destination](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:))
