# Isolated push-identity / Native Messaging experiment

This is a runnable architecture comparison, not an attachment adapter. Baseline: `b0778e7`. It contains no screenshot, login, chat text, upload, paste, file-picker, send-message or production-admission capability. Every response says `inputAuthority: false`. The lab's “candidate” means transport metadata reached the host, never a proved ChatGPT composer or draft.

## What runs

- `extension/content.js`: statically declared `document_start`, ISOLATED world, top frame, only a fixed loopback path. Sends a random per-document nonce and lifecycle signal. Reads no page text/form/cookie/storage. No MAIN-world bridge.
- `extension/worker.js`: accepts only the expected extension sender and synthetic loopback URL; obtains document/frame/tab/window identifiers from Chrome's sender object, not the payload. Serial native handshake → invalidation barrier → publication. Activation/navigation/source disconnect rotate view epochs. Asynchronous metadata queries must still belong to their original epoch. No reconnection/replay after native failure. Four source ports, eight signals per source, 120 native messages, 100 diagnostic entries maximum.
- `native_host.py`: real Chrome Native Messaging framing, UTF-8 JSON, four-byte native-endian length, strict 4 KiB maximum before body allocation, exact keys, no duplicate JSON fields, no NaN, separate exact browser document-token / UUID-nonce / integer / frame constraints, exact extension-origin argument, host-issued connection epoch, contiguous sequence, bounded non-reusable view epochs. Invalid input closes the channel and clears the candidate. It never uses renderer clocks to backdate a publication.
- `Gate.freeze`: host-side fixture decision using the original host event time, exact expected identity and epoch, actual host publication time strictly before the event, and a deliberately short experimental freshness bound. It returns only an eligible candidate flag. The 500 ms bound is a lab parameter, not a product guarantee or approved timing policy.
- `browser-lab.mjs`: root runtime owner only. Creates a fresh temporary profile and extension key, places the unique host manifest inside that profile, starts one headless Chrome for Testing, serves two fixed synthetic loopback pages, inspects metadata via CDP, then closes its own child. No original Chrome profile or installation is changed. The temporary directory is retained for the runtime owner to audit and remove. Output includes its private path and must be sanitized before publication.

## Executed tests and real-browser scope

The implementation agent ran **15 Python tests** and **7 Node VM tests** successfully. Python includes an actual subprocess stdin/stdout framed native-host exchange and exact origin rejection. VM tests exercise worker sender checks, invalidation during a suspended metadata query, and rejection of an old document’s later lifecycle ACK as evidence of a new document. No browser was launched by the implementation agent.

The root runtime owner executed the browser harness successfully after three recorded safe failures. The implementation agent independently checked its final JSON; see [sanitized browser result](browser-result.sanitized.json). This run proves the specific headless extension → Native Messaging channel and fresh document publication, including the profile-local host lookup. A second-document result requires a native publication ACK associated with a different Chrome-owned document ID, not merely another ACK count. It does **not** prove a native foreground click, document-to-business-draft continuity, ChatGPT composer readiness, attachment start/completion, or production enablement. Browser runtime evidence must be recorded separately, with the exact source, browser version, snapshots and result. Worker restart and message-delay cases are currently deterministic protocol/VM tests, not real browser restart acceptance.

Run offline from the repository root:

```sh
python3 -m unittest discover -s engineering/evidence/2026-10-28-real-mac-round8/extension-lab -p 'test_*.py' -v
node --test engineering/evidence/2026-10-28-real-mac-round8/extension-lab/worker.test.cjs
```

Root-only browser invocation (set `RIFTLET_LAB_CFT` to the discovered **Chrome for Testing** executable and `RIFTLET_LAB_PYTHON` to an absolute Python executable):

```sh
node engineering/evidence/2026-10-28-real-mac-round8/extension-lab/browser-lab.mjs \
  --browser "$RIFTLET_LAB_CFT" --python "$RIFTLET_LAB_PYTHON" \
  --out /tmp/riftlet-round8-extension-browser.json
```

There is no global native-host installation command. A blocked run exits 2 and records the precise bounded-wait/error class and available worker state; absence of native connection must remain BLOCKED, never counted as a synthetic “pass.” The loopback server and owned browser are stopped in `finally`; no broad process-kill command exists.

## Causal comparison

| Boundary | Existing Apple Events pull | Document-start push + Native Messaging |
| --- | --- | --- |
| Target already validated and published before original event | Can use the existing original ACK | Can use a previously published transport candidate, subject to independent current target/draft proof |
| First event precedes any channel or host publication | Cannot repair it by later capture/ACK | Cannot repair it by later handshake/publication; fixture explicitly rejects equal or later timestamps |
| Renderer reports an earlier timestamp but host receives after event | Native receipt/publication chronology still required | Renderer timestamps are not accepted on the wire |
| Navigation delivered before old queued publication | Old target must fail validation | View epoch/sequence reject old publication; old epochs cannot be revived |
| Navigation occurred but invalidation IPC is still undelivered | Post-receipt target validation remains necessary | Cached candidate can still appear current; the adversarial fixture demonstrates this gap explicitly |
| New document in same tab | Needs new target proof | Browser `documentId` distinguishes documents, but not same-document SPA business drafts |
| Worker/native process restart | Native capture restarts without original old authority | New connection/host epoch; no persisted candidate/replay; a new startup gap remains |
| End-to-end attachment input | Existing adapter retains target-side validation | Entirely absent from this lab |

**Inference:** push can move useful work before a later click and avoid repeated pull round trips. It cannot make a proof exist before it actually exists, cannot synchronize an undelivered browser activation with a native event, and cannot turn a Chrome document token into a ChatGPT draft identity. A safe production alternative still needs independently proved business identity, original-event native binding, and a target-side validation at the eventual single input. A transport latency improvement alone cannot justify guaranteed no-ACK cold first-click support. The synthetic adversarial test intentionally shows stale eligibility when the expected current identity is itself stale; `inputAuthority` remains false.

## Official API/source constraints checked 2026-10-28

Static `document_start` runs before the page's DOM is constructed, so it is an early installation opportunity, not proof that a composer already exists. Isolated-world variables do not directly expose the page's MAIN-world business state. [Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)

Chrome supplies `MessageSender.documentId`, frame and tab metadata. `documentLifecycle` describes port-creation time and may subsequently change; checking it once is not a continuous-validity guarantee. [Chrome runtime MessageSender](https://developer.chrome.com/docs/extensions/reference/api/runtime#type-MessageSender)

Native Messaging uses framed JSON over stdin/stdout; `connectNative` runs from extension context, not directly from the content script. This lab deliberately uses a much smaller bound than Chrome's limits. [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

A connected native host can keep an MV3 service worker alive; host loss closes the port. This does not prove channel availability at browser startup or eliminate process failures. [Extension service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)

Chromium's `DIR_USER_NATIVE_MESSAGING` resolves `chrome::DIR_USER_DATA` and appends `NativeMessagingHosts`; it does not hard-code the default user's profile path. Thus the harness places the host manifest in its own `--user-data-dir`. This was subsequently confirmed by the actual headless browser/native-host run. [Chromium chrome_paths.cc](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/common/chrome_paths.cc), [Chromium user-data directory](https://github.com/chromium/chromium/blob/main/docs/user_data_dir.md)

The runtime API prose calls `documentId` a UUID, but Chromium's current `ExtensionApiFrameIdMap::DocumentId` is an `UnguessableToken`; its parser requires exactly 32 hexadecimal characters. The initial lab incorrectly reused the UUID-nonce validator and safely rejected real sender IDs. The corrected document-ID validator is separate, preserves the browser's value, rejects the zero token and arbitrary strings, and leaves nonce/epoch UUID validation unchanged. This is a source-backed compatibility correction, not removal of the identity gate. [Chromium document-ID parser](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/extensions/browser/extension_api_frame_id_map.cc), [DocumentId type](https://chromium.googlesource.com/chromium/src/+/HEAD/extensions/browser/extension_api_frame_id_map.h)

## Root-executed headless result

The root executor ran the isolated harness against installed Chrome for Testing `156.0.8078.4`; the reviewer checked the installed bundle metadata separately (no `Browser.getVersion` result was collected). At review the repository HEAD was `85250a869f06d99e3d3ab046116f560bac572fd9`; the lab had not yet been committed, so its exact file hashes are recorded in the sanitized result instead of pretending that HEAD alone identifies these files.

The initial snapshot had no native channel. The first synthetic `document_start` signal led to a real native connection, acknowledged invalidation sequence 1 and publication sequence 2. Navigation produced invalidation ACKs 3, 4 and 5, then publication 6 for a different Chrome-owned document token. The final page was independently confirmed as the second synthetic fixture. No protocol exceptions were reported. All records retained `inputAuthority: false`; no upload mechanism exists. This confirms profile-local native-host discovery and the metadata transport, not native foreground selection or business-draft proof.

Three preceding executions remain **BLOCKED** in the history: (1) worker target visible before script initialization, (2) bounded wait with no content/native signal and insufficient refusal diagnostics, and (3) precise rejection of Chromium's 32-hex document token by the initial UUID validator. Each led to a bounded diagnostic or format correction. An independent reviewer also found and closed the false second-document inference from ACK counts; the final harness requires a different document token and the second fixture state. The per-attempt summaries are recorded; their original complete JSON snapshots are not archived here.

The publication timestamps belong to the native host clock. Their separation includes controlled navigation and harness polling, so it is **not** a transport-latency benchmark or performance gain. Pre-event eligibility, late-publication refusal, worker restart and undelivered-invalidation counterexamples remain separately labeled protocol/VM tests. No no-ACK cold first-click claim, real ChatGPT acceptance, production enablement or retry admission follows from this result.
