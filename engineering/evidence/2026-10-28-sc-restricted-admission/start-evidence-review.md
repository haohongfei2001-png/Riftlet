# Independent evidence review: restricted system-screenshot upload-start admission

Reviewer: `/root/admission_start_review`, a non-author AI reviewer. Read-only source and handed-off public evidence review; no tracked source/ref writes, browser interaction, real input, private database or private image access.

## Decision

**The new F evidence supports restricted internal-candidate uploadStarted admission, provided the implementation enforces the narrow scope and prospective-operation boundary below.** No defect in the handed-off start evidence was found. This decision concerns start alone; it does not grant completion, safe-failure/retry, ordinary production, or a claim that the new candidate UI has been exercised on a real Mac.

Reviewed evidence commit: `493d1d8b898d18e34709463d2dceca8c85ad4014`, tree `d2823feecbff87a137645440a8955abee781d1ba`.
Actual runtime source: `48574df19f34e5681ee98815750e279540e9eb9b`.
Official integration baseline: `871d825a43a759bb6dd8ded9cdc99a340d8e0e64`.

The new evidence commit is a documentation/evidence child of `f2ae645451044649fbe73326952efbe084353869`. I verified its Sources/Tests/Resources/Package/scripts/.github/ThirdPartyNotices/research objects are unchanged from runtime source48574df. The source JS SHA-256 recomputed from Git is `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`, exactly the resource hash recorded in F's evidence.

## Positive start evidence

1. **New real system screenshot.** The source packet records native screenshot metadata, a new macOS selection capture, original/private-copy SHA-256 equality, 6,796,322 bytes and 1746×1164, 8-bit RGBA PNG. Its recorded original/private hash is `0c19cb16f5c6dfdcaf0958284d6f40450912ea03babe5a79e1d268c2f06ff596`. This is not an old F/D/A replay or a generated file merely relabelled with screenshot metadata. The visible pattern was synthetic, while the captured file came from the actual system screenshot flow.
2. **Original click and exactly one formal input.** The original full ACK predates F's native click by1208.909ms; the evidence reports one frozen original selection and equal full target/asset/operation/attempt/hash in pre-click, page, journal and SQLite. Formal native actions are exactly1begin/26chunks/1commit, all successful and non-overlapping. Independently checking `ceil(6,796,322 / 262,144)` gives26 chunks. Page inputCount and a separate change listener each report1; the chunks are not multiple inputs.
3. **Start is attached to the original file and original attachment.** `timeline.json` reports input first, then the unique original card/progress node. Initial missing progress and a blob preview load do not claim start. After file hash verification, that same node reports2.4538636176 at+1948.7ms, then3.6807954264 at+2151.4ms; only the second sample has the adapter's positive start. Both values are finite, strictly increasing and below100. I checked all34 finite recorded values are strictly increasing, retain inputCount1, hashVerified and original node/card identity.
4. **Start precedes completion.** Public sequence facts are input2 < hash7 < start17 < hundred50 < ended59 < loaded60 < proof62. The page start is+2151.4ms and final proof+8784.0ms relative to file input. Native uptime and document clocks remain separate; no cross-clock exact latency is inferred. Historical start survives normal progress removal in the journal; a later `startDisqualified` is not used to manufacture a new current-upload claim.
5. **Durable original identity.** The handed-off journal has unknown/input/start/attached first slots for the same operation/attempt; input/start/attached attachmentIDs are reported equal. Its start is uploadStarted, exactImageIdentity=true, belongsToOriginalDraft=true, isUploading=true, hasError=false. The provenance remains integratedDevelopment. At this original run all admissions were closed, F remained unknown/visible and upload_starts remained0: the evidence is not an already-admitted swallow or succeeded claim.

## Source predicates support this interpretation

The frozen v13 page's `sampleStart` requires a unique stable progress node, original input sequence, finite document timestamps, verified file hash and two strictly increasing finite values below100. Missing progress only before the first numeric sample is tolerated without proving start; replacement, invalid numbers, regression or incompatible mutation permanently revoke start eligibility. The output additionally requires current original membership, inputCount1, active uploading, no error/proof/end and current value below100. A stored historic start is therefore not replayed after completion or invalidation.

`AttachmentObservation.swift` independently validates inputCount1, startSequence>inputSequence, finite nondecreasing clocks, bounded evidence ID and strict progress ordering. `ObservationNormalizer` verifies asset/op/attempt/hash/full target and original provenance/scope. `ReceiptPolicy.allowsUploadStart` requires the admitted start profile, original-draft membership, uploading, a nonempty original attachment ID, no error/positiveReady/safeRetry. These existing mechanisms can feed the existing durable start/UI path; the upload mechanism or animation does not need rewriting.

## Preservation and baseline boundaries

F's public packet records48 unchanged characters, noncollapsed selection8..11 inside the original editor, page focus without editor focus, and one stable original attachment retaining card/image/source/dimensions/completion. The old attachment preview exactly matches its preparation file; total cards move1→2. Twenty-four post-click snapshots and the final snapshot retain the reported preservation predicates. That is bounded sampled evidence, not a claim about every unsampled instant.

The baseline attachment was a separate3,045-byte generated PNG input installed before the formal F observer, then restored in a normal fresh document. It is not counted as a system-screenshot test or F's input. The v7/v8-owned old page was not repaired or newly admitted; the ordinary fresh thread document allowed v13 to bind. Existing A/D remained UNKNOWN with original operation IDs/attempts/targets and preserved journals; the bounded preparation log is not treated alone as proof that there was no old input.

## Required admission scope

- Explicit system-screenshot internal-candidate composition only, real system origin and the existing private media/data root. Ordinary mode and all retry/failure profiles stay closed.
- The observed Chrome Chinese ordinary-thread structure, with a recognized ordinary-thread logical identity and all existing full target, native session and source-ID checks. The current `.webChat` surface alone also covers Home and is insufficient as a scope gate. Work, temporary/read-only, Home, non-Chrome and missing/unrecognized thread identity must not inherit F's admission. F is recorded as an existing ordinary business draft; its raw logical identity is deliberately redacted, so the current review does not independently prove the raw profile string. A conservative implementation may admit only the known persisted ordinary-thread profile.
- The observed single-frame8-bit RGBA PNG class (IHDR bitDepth8/colorType6), within unchanged8MiB/16,777,216-pixel transport limits, with actual per-operation byte/hash verification. The evidence does not validate all16-bit, HDR, wide-color or alternative PNG encodings merely because they can be captured. Keep original unsupported media intact; no conversion. F's exact dimensions and byte size are a sample, not a new mandated image size.
- **Prospective operations only.** A broad map switch must not reclassify F or an older UNKNOWN when observation resumes. Durable, immutable eligibility for new operations/attempts must be explicit, survive restart, and be checked independently of the old observation journal. No old proof, uploadStarted, retry, unlock, timestamp-based guess or rewritten operation is authorized by this evidence review.
- Start and completion policies must remain independently reviewable. The same case's final proof is relevant to identity consistency but is not the reason this review admits start. Completion has its own reviewer/decision and safe-failure/retry remain closed regardless.

The recorded environment is macOS27.0(26A428), arm64 and Chrome156.0.8078.73; this does not establish a broad browser/OS support matrix. A future eligible operation must still meet the exact current structural and evidence predicates. Fast small images may never expose two increasing intermediate values; such a sample must not get invented start merely because final proof arrives. No no-ACK cold click, hardware mouse, MID, physical multi-display, self-inclusion or actual fast-swallow timing acceptance is inferred.

## What was actually independently checked

I read all six public files in the exact493d1d8 evidence directory, the immutable48574df start/identity source, normalizer, receipt policy, candidate input scope and journal. A local consistency check verified native action counts/order, chunk arithmetic, channel/dimension arithmetic, all34 finite progress samples, first actual positive start, sequence ordering and the matching public identity assertions. It performed no upload, UI input or test-suite rerun.

The private hash index and original non-author review attest that the original executor/reviewer checked raw captures, full target IDs, DB snapshots and scripts. Those private bytes were not available to this reviewer. I independently recomputed the public source/evidence file hashes and cross-checked their internal consistency; I do not claim to have newly compared the redacted private identity fields or raw image bytes myself.

Public evidence SHA-256:

- README.md: `baa2eb191618b2e9a95fb11f3f5839aaf9a508d6e285e55497801cbc8996219f`
- result.json: `aafaf2e31c57ed388e812ae231addacaec51288731558948060ab1b8a897527b`
- timeline.json: `308246cab508a5d05a2e2e033fed1711e3a36852d972bbd60e0fb9f182f030ce`
- review.json: `ee0a09f55a05ede558afc22a775e345cf28b582caeb283f6e5bbf912277131fb`
- verification.json: `2eebfd0d08f781ad02ca013e40ca4cb72c374cf33f13646b48626dac75331e11`
- private-evidence-sha256.json: `1f575aeea9c7fdebba6f9f247e4e173210fb5b6caf287d9e6f7ca532548c2c57`

Final code/admission enforcement and new full macOS CI remain the integration lead's separate implementation/review gate. A subsequent real-Mac run must use a different new screenshot, never F or any old UNKNOWN.
