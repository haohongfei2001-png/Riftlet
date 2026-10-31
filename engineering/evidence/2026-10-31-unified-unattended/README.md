# Unified App unattended acceptance — 2026-10-31

Formal PR #1 remains Draft at `2bddb61a19114167b7485c392600c4b91dc62725`, rechecked after execution. Reviewed successor product source is **`b0cc67366fa78e6fc24d8e0c5cc468fd6a13cb76`**, on `codex/riftlet-real-mac-acceptance-internal-beta-unattended-20261031`. Only three App ownership/test files change. PR #1, PR #15, main, website, endpoint, database schema and upload admissions were not changed.

## Product result

**PASS, limited software-controlled internal ordinary entry:** one NEW genuine macOS system-shortcut PNG was collected, clicked once through its native micro-window, positively observed uploading, swallowed, and independently completed as SQLite `succeeded` / asset `used`. This was the unified successor built with the existing fixed **internal ordinary acceptance** configuration, launched with only `--acceptance-trace`. It was not the default production-disabled App, not a test overlay, not an old image replay, and not a physical or no-ACK cold-click result.

The separate default App still disables input/start/completion. Its complete production upload experience is **NOT_RUN** and is not certified by this sample. No new admission, safe retry, built-in source upload or Web continuation was enabled.

## Accurate version and CI

[Formal artifact audit](artifact-audit.md) distinguishes the successful formal CI package from this patch. Formal Native 41126228170 / Feedback 41126227847 used merge checkout `f2610e795c2eb41242289a32d0517edde094b587`; all App input objects match formal head `2bddb61`. Neither old artifact contains this startup fix.

For exact successor `b0cc673`:

- Native run **41138988332**: ARM and Intel macOS jobs **PASS**.
- Feedback run **41138988306**: Feedback job **PASS**.
- Both workflows overall **FAIL**, because `source_admission` still pins the previously reviewed formal composition. This pin was intentionally not weakened or changed. The integrator must review the combined source, update its exact gate, and run final composition CI.
- Local native build, ad-hoc signature, bundle verification and internal Beta packaging **PASS**.
- Local filtered XCTest invocation **NOT_RUN**: Command Line Tools lacks XCTest. Real XCTest ran in the cloud jobs; no toolchain permissions were changed.
- Non-author product review **PASS** for the exact three hashes in [results.json](results.json). A separate non-author review rehashed the new original/private PNG and verified page/journal/SQLite identity, unique start, completion, timing and preservation: **limited real-upload PASS**, retaining every boundary below.

Executable hashes (SHA256):

| Artifact | Hash |
|---|---|
| Default local App | `4c7e52f5ba2a8638028d60294876e57613ad1d4e0fba359355e840c6bcf73817` |
| Internal ordinary App actually uploaded | `a0d7d34f5d9fd374e5ac3521a05b6d35c2899ee462a935fa69508208709076fb` |
| Local internal Beta ZIP | `eb59b4d7bbe112aca0f28be6158cf71e4768bb250230816ecf92dc588dc64ef3` |

The ZIP is a development package with an explicit restricted launcher, not a notarized upload-enabled default distribution.

## Fixed startup race

The former App scheduled Feedback initialization before acquiring its mode instance lock. A deterministic real FeedbackStore/Darwin flock reproduction demonstrated process B holding the Feedback lock while process A held the App lock. A could not initialize Feedback; B could not start the App.

The patch takes mode ownership synchronously before menus, first-use, sidecar and store initialization. A loser exits without creating Feedback or lazy folder-access state. The non-author reviewer also required ownership to survive irreversible termination until kernel process exit, so a successor cannot take the App lock while the old FeedbackStore remains alive. File descriptors are failure-safe, regular-file checked, no-follow and close-on-exec. No data is deleted.

Six native lock/store/process harness scenarios passed. The packaged normal App was also launched against an already-owned ordinary root: **PASS**, explicit refusal and exit in **0.196 seconds**, no observed window, foreground change or Feedback lock claim. This is packaged loser-path acceptance, not two successful simultaneous GUI launches.

## New real screenshot and original operation

Public sample alias **U1** maps to the full original identity only in private evidence. A CGEvent-driven macOS Command-Shift-4 region capture produced a new original with system screenshot metadata. CLI images were used only as local diagnostics, never as an uploaded source.

- Original/private bytes: **1,196,165**, **702 × 494**, single-frame noninterlaced RGBA8 PNG.
- Original/private SHA256: `d878067f4183dea7c1ba5f887f4d1e53fcf88adf78ed3f09c6b00cdbc39e8287`.
- Content inspected: controlled colored noise only. `kMDItemIsScreenCapture = 1`.
- One fresh asset, operation and attempt; exact original target/hash retained. One durable dispatch and one original page input (`committed = true`, `inputCount = 1`). File change capture saw one file; bubbling subsequently saw zero after the site cleared the input. This is not another input.
- The native bridge diagnostic hit its 1,000-event cap before input. **This run does not independently count begin/chunk/commit commands.** Page input identity, file-change trace, original operation record and journal provide the unique-input evidence instead.
- The source file was absent during the first bounded 15-second check, then naturally appeared and imported. Exact T0/T1/T2 were not measured. A later control reused one directory-baseline filename; that first baseline is not independently retained. Raw first event log and the actual original remain. Do not attribute the unmeasured interval to the watcher.

The executor used only its known Chrome process/session/window/tab and a separately created own Home tab. No other task's tabs were reloaded/closed or coordinated by message; no chat message was sent. Chrome receiver, target and full private identifiers are deliberately omitted here.

## Causal timing and completion

All native times below are seconds in one boot's monotonic uptime. Page performance timestamps are separate and are **not** directly subtracted from native uptime.

| Native boundary | Uptime | Delta from mouseDown |
|---|---:|---:|
| Complete pre-event ACK | 755953.6433859584 | −255.858 s |
| CGEvent mouseDown | 756209.501291833 | 0 |
| Native selection callback | 756209.5093589167 | 0.008067 s |
| CGEvent mouseUp | 756209.586231000 | 0.084939 s |
| Swallowed durable visibility observed (upper bound) | 756211.3771549168 | 1.875863 s |
| AppKit swallow starts | 756211.3779296251 | **1.876638 s** |
| AppKit original panel closes | 756211.5087907084 | **2.007499 s** |
| Persisted success observed (upper bound) | 756235.093233625 | 25.591942 s |

This was a **staged prebound sample**, not a natural immediate-click success-rate measurement. The editor was focused for the successful sample. It does not certify unfocused, physical or no-pre-ACK operation. Original mouse routing hit the exact new asset's native window; AXPress was not used for that upload click.

The original page operation observed input at 19820423.100000024 ms (sequence 140) and start at 19821637.900000095 ms (sequence 157): **1.2148 s input-to-start**. Original progress increased from approximately **6.9706% to 13.9412%**. Exactly one correlated `upload_starts` row was persisted. These are positive intermediate upload values, not a placeholder or inferred historical start.

After swallowing, the independent original-operation observer returned `attached`, exact image identity and strict content proof; the live original operation remained committed, file-hash verified, invalid=false, error=false, with connected complete image and proof present. SQLite final receipt was verifiedReady / positiveReady / belongsOriginal, safeRetry=false; operation succeeded, asset used, visibility swallowed. Content proof is decoded strict sRGB identity, not a claim of server original-byte preservation. Actual pixel-presentation latency is not measured; the recorded native close callback is distinct from final upload completion.

## Draft preservation and selection limitation

The controlled nonempty draft's hash was unchanged; its old attachment remained the same connected node/form while U1 became the second attachment. No message was sent. Real CGEvent keyboard input formed range **37 → 30** before selection. It survived file change, immediate microtask, mutation, frame and task observations.

The first later observed collapse was `element-blur`, followed by button focus, approximately 3.1574 seconds after change capture. A visible-dialog query then confirmed a site **storage-space notice** containing the focused button, with document visibility/focus retained. The first post-page snapshot did not locate the active element inside its sampled dialog; only the later visible-dialog query did. **Selection preservation is FAIL for this sample**, with a site-dialog limitation under investigation, not a PASS. The earlier read-only native-attachment control at its original source had also shown the site's dialog behavior; it is not relabeled as a new control on this build. The current trace establishes temporal association, not proof of every hidden site-internal cause. No forced focus, stale Range restoration or text rewrite was added.

## Restart, Feedback and local safety

After graceful restarts, all five internal operation identities/targets/attempts, all three start records, all asset image identities and compensation records matched the pre-restart snapshot. The two old internal UNKNOWN operations remained UNKNOWN; U1 remained succeeded/used. No extra input was created.

Final integrity and foreign-key checks passed for all three existing roots:

| Root class | Assets/media | Operations | Starts |
|---|---:|---:|---:|
| Ordinary | 16 | 0 | 0 |
| Internal ordinary | 6 | 5 | 3 |
| Restricted candidate | 18 | 7 | 3 |

All **39 old media plus the one new U1** match their stored byte counts/hash. Historical 122 evidence files also matched their prior manifest. No UNKNOWN was cleared or replayed. Read-only reconciliation can update observation reasons/times; this is not a claim that every historical row byte is unchanged after startup.

Actual packaged Feedback UI **PASS, local-only AX control**: fixed synthetic Chinese multiline text saved, reopened, survived graceful App restart, and matched its original hash. Diagnostics stayed unchecked. The exact own test text was then cleared through the UI, restoring the initial empty draft. Reports=0, submissions=0. This does not test IME/VoiceOver/physical typing or native cloud delivery. Native cloud end-to-end remains NOT_RUN: independent D1 management/cleanup path was unavailable, so no new report was created with an unresolved cleanup obligation.

The actual built-in capture entry opened, switched to region mode and cancelled through its native AX controls. A guarded attempt over the safe helper backdrop found a foreign process's window above the intended area and **refused before any screenshot mouse gesture**. No built-in image was created or uploaded; region/window/fullscreen completion is NOT_RUN. This does not establish a product geometry defect. The earlier own Preview window could not be reliably presented and was also refused before the Home capture.

## Remaining bounds and handoff

- New Home/local tab preparation established visible foreground, a real keyboard noncollapsed selection and editor-not-focused state without sending a message or altering its inherited controlled text. **Home attachment NOT_RUN**: a new safe capture target could not be established; no new asset or input was attempted there.
- No-ACK cold first click, immediate natural screenshot-to-click distribution, physical mouse, Spaces/fullscreen transitions, pending A/B overlap and safe failure rebirth remain **NOT_RUN** on this source. No success percentage is inferred from one staged sample.
- Default ordinary production input/start/completion, built-in upload, Web continuation and safe retry remain **closed**.
- Integrator can take only `b0cc673` (three reviewed files), preserve current website/main, repin the exact reviewed composition and run one final combined CI/package. No experimental workflow is part of this patch.
- A final exact default-App admission decision and end-to-end test are still required before claiming normal daily-use upload. Home/local and unfocused coverage need their own actual final-package result. Developer ID/notarization remain separate.

Private raw files, screenshot, database snapshot, target/session identity and local paths are not committed. Private manifest SHA256: `1ffd50647ab520c77e328c43617e3cedab554b91543592fd7181418500857f33`. It covers 111 private files; source/archive references are local only. Physical testing is the only item here necessarily requiring a human; unresolved engineering environment/gate work is not assigned to founder Beta participation.
