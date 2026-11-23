# Ordinary browser pre-click timing on macOS

The local experiment asks whether a page can identify an original draft, return a native acknowledgement, and have a separately addressed native mouse event occur later. The QA page extracts the product's original-receiver function from a supplied resource. Four different receiver IDs represent four prepared samples. The fixture never uploads a screenshot or edits the page. The signed application's production click, attachment card receipt and logged-in website acceptance have separate gates.

## Run on a dedicated QA window

Build the intended RiftletAdapters target in Debug. Use its SwiftPM product directory (shown by `swift build --show-bin-path` with the same build options). The following compile command assumes an Xcode-style macOS product directory containing RiftletAdapters.o and RiftletCore.o.

```sh
swiftc -parse-as-library -I "$qaBin" -I Sources/CSQLite \
  Tests/PreClickLease/native/{identity,owned,press}.swift \
  "$qaBin/RiftletAdapters.o" "$qaBin/RiftletCore.o" -o "$qaOut/identity"
node Tests/PreClickLease/native/route.cjs "$qaResource" "$qaOut"
```

Use a new private output directory. The service listens only on a random IPv4 loopback port and emits a different URL per family. A document can display a receiver once its original editor is present, visible and active. The page changes its title and clears its test grant labels on retirement. The loopback service writes a receipt identified by its random document ID. Redirecting a vendor URL to localhost is outside this procedure.

1. Run `identity availability chrome` or `identity availability edge`. For each candidate returned at the expected standard path, use `identity --pid PID snapshot FAMILY` and save the JSON. This validates the signing identity of the running process, kernel birth, executable, standard app path, and existing window IDs without listing their tabs or reading their URLs.
2. For an official-control trial, use the requested family in the official browser client. Create a **new** controlled QA tab, navigate it to the freshly generated URL, and use the official window management API restricted to that URL and its owning window. Require exactly one match and a single-tab normal window. Record the native window/tab pair separately from the opaque provider reference and claimed tab handle. A family name or matching digits does not identify the process. The native helper next requires a newly added window, the expected selected native IDs, the fresh URL and the exact document ID from the page.
3. For a separate native transport trial, `identity --pid PID create FAMILY BEFORE_JSON LOOPBACK_URL CREATION_JSON` addresses the already verified process. It persists the creation request before sending it once, validates the returned window specifier and its sole blank tab, and sets only that tab to the local URL. If any step is uncertain, preserve its receipt. Do not send another creation or close a window by position.
4. For either trial, run `identity --pid PID series FAMILY BEFORE_JSON WINDOW TAB LOOPBACK_URL DOCUMENT_UUID`. For each slot the helper reads a different QA receiver ID through Chromium's native execute-JavaScript Apple Event, receives the acknowledgement, then posts a tagged CGEvent **only to its own PID**. The AppKit view checks both its own panel number and the tag. Each JSON sample separates event time, view callback time, and ACK time on the macOS uptime clock. The OS foreground, original native selection and page challenge are checked around the sample. A refused identity cannot initiate a new mouse event. The first measurement includes creation of the native QA panel. The last two samples test closely spaced native presses.
5. To test same-URL replacement, use the official browser's reload on the verified QA tab. Call `identity --pid PID verify FAMILY BEFORE_JSON WINDOW TAB LOOPBACK_URL OLD_UUID` and require a mismatch. Repeat with the replacement UUID. This only tests read-side refusal before input. It does not measure DOM setters, uploaded images or application-side operation storage.
6. Close only the owned tab. The native trial uses `identity --pid PID close FAMILY CREATION_JSON LOOPBACK_URL`, which addresses the same live receiver and requires its original sole tab and exact QA address. Recheck the pre-existing window IDs. Stop the loopback service. Keep raw process/window identifiers, private URLs and any screenshots of a signed-in service outside the repository.

## Evidence from 2026-11-22

Chrome 157.0.8103.79 and Edge 158.0.4370.33 each delivered four tagged software mouse events to the native QA view. The last two occurred 116.210 ms apart on Chrome and 102.158 ms apart on Edge. Both positive runs used a real installed ordinary browser and a local QA page. The four receiver IDs and native mouse callbacks measure event ordering. There were no screenshot uploads in these samples. The complete per-sample values, running-code requirements, exact paths, output hashes and cleanup scope are in [receipt.json](receipt.json).

The official Chrome family selector reached Owl and refused window creation. Standard Google Chrome was independently verified through its vendor-signed native process and newly created QA window. For Edge, the official controller and the signed Microsoft process matched the challenge in the same QA window. A separately verified new Edge window reached the exact ChatGPT temporary-chat URL. The official tab title was ChatGPT. Scoped editor/upload probes timed out, and the OS foreground moved away after navigation. Account status, an editable draft and upload availability remain unverified. No real website input was performed. [Website preflight](website-preflight.json)

The official controller can perform a new, same-tab read of known composer or upload-control locators. A narrowly cropped screenshot requires verified geometry that keeps private content out of the image. A full accessibility tree or an arbitrary viewport screenshot would expose more than the allowed UI. A signed candidate can separately exercise its product read-only prebind in a new temporary test window after its identity and authorization have been independently verified. It must establish its own original identity and receipt under its own process permissions. An unsigned QA process's successful no-prompt checks are recorded separately. [Apple running-code validation](https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:))

## Build 59 pair timing

Run the offline timing reader against a published series manifest and its original private receipts. The final integer is the second image index in the pair. The Chrome series uses index 4, the first Edge series uses indices 4 and 6, and the final Edge series uses index 3.

```sh
python3 Tests/PreClickLease/native/rapid_timing.py \
  docs/releases/1.0.8/evidence/build59/chrome-live-after-start.json \
  "$private_chrome_series" 4
```

The reader verifies each consumed receipt against its published SHA-256 and matches AppKit, operation, invocation, original PNG, card and durable START. Host timings are milliseconds relative to the first NSEvent timestamp received by AppKit. Both callbacks also have their own host timestamps. Browser input and change use the original document's rounded performance clock. The native commit interval and returned setter flag bound the host observation. Exact renderer setter entry and card acceptance instants were not traced. The tray sample proves the row was available at sampling time. The UI trace records the animation's start and close callbacks.

In the completed Chrome pair, the second row passed its initial hit and pixel checks 2,192.745 ms before the first down. Its press used a pre-click acknowledgement at +1,434.973 ms. The sequential verifier launched separate per-row checks and obtained the last pre-dispatch row sample at +2,487.889 ms. The first image's START reached the host at +2,208.680 ms and its animation closed at +2,338.971 ms. Those activities overlapped the verifier. The original records do not partition the entire 2,507.972 ms interval into exclusive product, browser and verifier costs.

All three Edge pairs registered the second down before the first animation closed. The 582.373 ms pair used the batched verifier, which prepared both rows before the first press, enforced a 260 ms minimum post interval and took 313.568 ms for the second final checks. It rechecked native row, pixels, browser route, editor and process before dispatch. Each posted or ambiguous press retained its original no-replay reservation. These timings quantify the benefit available from scheduling the verifier independently of the first card, while the Chrome result with that verifier is still outstanding. [Four reconstructed pair timelines](../../../docs/releases/1.0.8/evidence/build59/rapid-pair-timing.json)

### Read-only account checks for a new pair run

The official controller first reads the random document marker from the exact private local challenge tab. Its ID and the matched signed native process, window and tab travel together to the temporary page. The account reader requires a single visible profile button and positive account UI on the original page. An enabled sign-out or account-management action in the unique account navigation landmark provides positive evidence for free accounts. An explicitly labelled current paid plan inside the profile control or a subscription management link in account navigation can also supply evidence. A generic profile button, a display name that says “Pro”, a sign-in control, a hidden cue, a changed selection or a controller error cannot supply the proof. No menu is opened, closed or activated by this reader. It does not access session APIs or browser storage. [Account reader](official_account.mjs)

These positive UI shapes and the guest counterexamples have only been exercised in controlled fixtures. Their availability on a live temporary page remains unverified. When the official controller cannot inspect the site or the page exposes insufficient evidence, keep the run at the preflight boundary. Run the controls with `node --test Tests/PreClickLease/native/official_account.test.mjs`.
