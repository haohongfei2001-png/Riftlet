# Route B — document-start extension and a native receipt before the click

A headless commercial Edge 158 and Chrome for Testing 156 each loaded an actual MV3 extension and started a native messaging process in a disposable configuration. Per browser, three explicit operations delivered three generated PNGs to the original local fixture, with zero sends. The third receiver reply was deliberately discarded after delivery. A second request for that operation performed zero inputs. Ordinary Google Chrome 157 opened the fixture twice but did not register the unpacked extension. Safari received a documentation review only. [Exact builds, observations and source hashes](receipt.json)

| Measurement | Edge stable | Chrome for Testing | Google Chrome stable |
| --- | --- | --- | --- |
| Browser-launched native host and acknowledgement returned through the isolated document | Observed | Observed | Extension absent |
| Native event predates final ready receipt | Refused | Refused | Not run |
| First event after ready, then another explicit event on the same lease | 1 input each | 1 input each | Not run |
| Wrong window, tab or document; original editor removed and reinserted; same editor/new fixture draft generation; same URL reload | Refused | Refused | Not run |
| Original PNG digest, retained prior attachment, text and selection | Observed | Observed | Not run |
| Lost return after one actual delivery | Persisted UNKNOWN, repeat refused | Persisted UNKNOWN, repeat refused | Not run |

## Ownership and timing

The isolated-world script starts at document creation. It waits until the exact fixture form, editor, label and owned file input exist. The worker takes top-frame/window/tab/document identity from Chrome's message sender. The native host sends an unpredictable acknowledgement back through that same port. The host installs the lease and timestamps it using the native monotonic clock only after the original content script returns that acknowledgement. Window, tab, frame, URL, document, connection, generation and native acknowledgement all participate in routing. The content script checks its retained JavaScript objects and drains pending mutations immediately before the one setter. Draft-generation evidence here comes from this fixture’s explicit form attribute; a site that silently changes the meaning of the same editor needs separate provider evidence.

The test harness supplies a private local operation and an unposted AppKit mouse event stamped with macOS uptime. An event sampled before the browser started was rejected when presented after readiness. A native event created after readiness was accepted. The experiment checks ordering independently of page time. A newly constructed, unposted CoreGraphics event on this Mac had timestamp zero and was unsuitable for this measurement. Physical clicks, the Riftlet tray, signed-app delivery, macOS foreground browser identity and UI-to-extension window ID correlation still require product integration and acceptance.

A native SQLite transaction claims the operation before the first browser message. The worker uses the exact tab and browser-issued document ID. Loss of the original reply leaves the original operation UNKNOWN. The receiver's input/change return and independently collected fixture digest measure delivery. A positive service attachment card or START, service error recovery, and real ChatGPT or other logged-in draft acceptance remain untested. The test-only native launcher, local socket and generated PNG are confined to the disposable directory. A product native host would additionally need the signed caller/channel binding, real asset access, and original-card proof.

## Reproduce

Use macOS with Swift, Python 3, and a locally installed browser. Each command creates and removes a disposable configuration, private IPC endpoint, and NativeMessagingHosts registration. The fixture listens on loopback and the extension copy checks its exact randomized URL. The checkout’s extension has an empty URL by default. Only the browser process group started by the runner is stopped.

```sh
python3 Tests/PreClickLease/helper/run.py --browser "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" --label "Microsoft Edge stable"
python3 Tests/PreClickLease/helper/run.py --browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --label "Google Chrome stable"
python3 Tests/PreClickLease/helper/run.py --browser "$CFT_EXECUTABLE" --label "Chrome for Testing"
```

## Distribution and consent

- **Google Chrome.** A normal consumer deployment needs a signed, installed Riftlet native host and a reviewed Chrome Web Store extension with its production ID in the host's allowed origins. Users install the extension and grant access to the supported sites. Chrome’s official branded builds removed the command-line unpacked installation path used by this experiment. No store submission, developer-mode installation in an ordinary profile, or enterprise policy change was performed. [Chrome Web Store publishing](https://developer.chrome.com/docs/webstore/publish) · [Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) · [Chrome's branded-build flag change](https://developer.chrome.com/blog/extension-news-june-2025)
- **Microsoft Edge.** The ordinary path is Partner Center review, user installation from Edge Add-ons, and native host registration for that extension ID. Permission to use native messaging and site access must be declared. The measured Edge stable binary used a private unpacked development installation. Consumer onboarding and store approval remain untested. [Edge Add-ons publishing](https://learn.microsoft.com/en-us/microsoft-edge/extensions/publish/publish-extension) · [Microsoft native messaging](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/native-messaging)
- **Safari.** Safari web extensions have a containing app and a native app extension. The background script can message the native app extension, which can share approved state with the container through an App Group. A signed app and extension can go through the Mac App Store, or a Developer ID signed and notarized containing app can be distributed outside it. Users enable the extension and grant website access. Safari's ability to address the original top-level document, revoke its editor generation under navigation and return an acknowledgement before a Riftlet click requires its own test. [Apple native messaging and App Groups](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension) · [Apple distribution options](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)
