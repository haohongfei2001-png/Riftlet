# Owned native upload control

Ordinary Google Chrome runs headless in a disposable profile. Each of two independent local pages receives the same privately retained 1920×1440 system screenshot. The browser reads an actual File from its single file input. The file selection uses the repository's fixture driver on the local page. The two cases have distinct request IDs and URLs.

| Case | Original selected bytes | Browser observation | Server observation |
| --- | ---: | --- | --- |
| Complete | 7,921,752 | Trusted request load and loadend, HTTP 201 | All 7,921,752 bytes matched the original SHA-256 |
| Partial | 7,921,752 | One native abort during a trusted upload progress event at 1,425,408 bytes (17.9936%) | Read 1,376,256 bytes equal to the original prefix, then observed ECONNRESET. No HTTP response was issued |

The source PNG SHA-256 is `66057577de807a2d2a266360b59efdfb80e6301a158d9eb1bd2bf028757dd3a7`. Its private capture receipt identifies the single nonactivating local pattern window and confirms unchanged foreground ownership. The complete original browser/server receipt is [system-result.json](system-result.json), SHA-256 `5573712c551ecf4c90a355c962a5bca0c3323727d0f100b3376569d3548394f5`.

## Procedure

The server binds to the IPv4 loopback address on an ephemeral port. Each local page creates one transfer through its fixed `/case/<case>/create` endpoint. The server matches the original size and SHA, assigns a request ID and issues only `/case/<case>/png/<id>`. The original page constructs the native XMLHttpRequest and sends its selected File once. For the partial case the page calls abort on that instance only when upload progress is trusted, computable, between 10% and 50%, and observed before a response. The server paces its own consumption so the upload can report intermediate progress.

The browser logs upload and request events separately. The partial request emitted one trusted abort and one trusted loadend at each target, with zero error events. Both runs had one file input, one change, one creation, one PUT, zero sends of the form and zero submissions. Both pages removed their listeners. The owned browser process group exited, its profile was removed, the listener closed and the tracked PUT count returned to zero.

To reproduce on macOS with ordinary Google Chrome, pass a privately retained local PNG and its matching capture receipt. Omitting the final argument labels the run as a development fixture. The runner accepts 5–15 MiB PNGs.

```sh
node Tests/PreClickLease/g4/owned-transfer/run.cjs "$QA_PNG" "$CAPTURE_RECEIPT" > "$RESULT"
```

To verify file and prefix hashes, origin and URL digests, event counts, operation identity, byte counts and cleanup from an existing receipt, run the offline verifier. [offline-result.json](offline-result.json) records its result for this sample.

```sh
node Tests/PreClickLease/g4/owned-transfer/verify.cjs "$RESULT" "$QA_PNG"
```

The browser progress count and the server's application-read count measure different points in the transfer. The fixed page, receiver and all responses belong to this loopback test. Signed Riftlet input, ChatGPT transport, real failure-card rendering and original-draft recovery require their own evidence.
