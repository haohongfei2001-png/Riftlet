# G4 passive upload calibration

The module observes one explicitly enrolled system PNG in the already identified Temporary Chat. The selected browser target, execution world, original editor, signed build, original source bytes and once-only AppKit click must be independently attested by the acceptance host. The module itself provides neither host access nor a transport fault.

## Invocation

Load the self-contained expression in `calibrate.js` using the fixed, separately authorized host entry point for the selected page. Invoke the returned function with the configuration and original editor object. The configuration keys are `nonce` (32–128 hex characters), `entryID`, numeric `timeOrigin`, lowercase `pngSHA256` and numeric `pngBytes`. An `ARMED` receipt starts a 60-second observation. The host verifies the identity again before the only AppKit click.

Call `globalThis[Symbol.for("riftlet.g4.passive.v1")].sample(nonce)` on the same page to read progress and `.finish(nonce)` to detach. Finish is mandatory for the final receipt. Wait until `requestPending` is false and `observerPending` is zero. Retain the last sample if a deadline expires while either is pending.

## Admission

`CALIBRATED` requires each of `inputs`, `changes`, `creates`, `responses` and `byteRequests` to equal one. The original File, SHA-256, unique operation UUID filename, explicit source creation, singular signed URL, native byte-request return and successful response at that exact URL must all correlate. Both fetch and XHR are supported. An early XHR PUT may hold one URL until the creation response arrives. The observer retains its body only if it is the enrolled File. Unowned request/response contents are excluded.

The sanitized return contains the SHA-256 of the signed URL plus the fixed creation method/path, response field name, transport, status and body type. `entire-body` means the full request payload reproduces the PNG. `single-file-part` means the only FormData entry reproduces the PNG and the browser supplies the enclosing multipart boundary. Neither the signed URL nor the multipart boundary is emitted.

The observer immediately forwards every original method call and returns its native value or original promise. Successful byte evidence requires the individual fetch response or XHR loadend with an exact final URL and a successful HTTP status. The observer never calls xhr.abort, fetch or xhr.send to create an independent request. Oversize, unavailable or disputed observations are inconclusive. A release cannot treat private test fixture results as real site evidence.

`CALIBRATED` is a positive observation of calls on these installed entry points. Pair it with the original operation ledger, site card and independent observer because cached network functions and alternate execution contexts can be invisible to these hooks. It supplies no positive error card, UNKNOWN recovery proof or fault-injection claim.

## Offline checks

Run `node --test calibrate.test.mjs` in this directory. The fixtures are in-process with mocked browser objects, one synthetic ephemeral test PNG and zero outbound requests.

## One controlled XHR cancellation

The separate QA-only `once.js` uses the transport observed in the signed build 59 Edge calibration. The native test host first binds the signed browser process, creation receipt, original window and tab, temporary document, visible original editor, and a new system PNG. It reserves a single fault before arming. Within that document the probe associates the original input File and full SHA-256 with exactly one creation response and the XHR that sends that same immutable File to the returned upload URL. It cancels only after native send returns, with an original trusted loadstart and no observed response. A reopened XHR, a second loadstart, or competing candidates disqualify the request. The receipt records whether positive upload progress was observed. Signed URLs stay in memory.

The original request's trusted abort and loadend close the probe and restore the original functions and event listeners. The host reads the frozen outcome through its original nonce. The existing page card and SQLite verifiers decide whether the application can proceed to an explicit recovery attempt.

Run `node --test once.test.mjs` for the isolated controls. Network cancellation, a named website error card, and an eligible failed operation are separate acceptance results.

## Later upload events

The two additional QA strategies in `late-once.js` use separate reservations on fresh screenshots and operations. The original XHR, native request generation, immutable File, full PNG SHA-256 and returned upload URL must match. Both strategies require native send to have returned and the browser to have observed no response. The partial-progress strategy requires a trusted upload progress event with a positive count strictly below the full PNG length. The second strategy requires a trusted upload load event with the full PNG length. Both decisions are made in the original upload event callback. Neither uses displayed percentages or an elapsed-time threshold.

When an event is missing or ownership is uncertain, the request continues normally. A terminal receipt includes the browser's measured upload counters, any actually observed cancellation, and scoped cleanup. A browser upload counter does not independently prove how many bytes reached a server.

Run `node --test late-once.test.mjs` for the offline controls. Real-site timings, card observations, database snapshots and explicit recovery require separate evidence.
