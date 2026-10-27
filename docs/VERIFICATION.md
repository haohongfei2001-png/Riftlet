# Engineering verification record

2026-10-27 Asia/Shanghai. Initial foundation branch based on `5a3ab5d7a761d5397f8bc15b6f40d761b29e58d2`.

## Evidence categories

- Source implementation is not runtime validation.
- Linux static checks and the inherited Oracle offline fixture do not prove macOS or ChatGPT behavior.
- macOS CI compilation/tests/package smoke do not prove interactive focus, click-through, Spaces or real upload.
- No real user screenshots, chats or browser sessions are used in automated tests.

## Current execution

| Check | State | Scope |
| --- | --- | --- |
| Library handoff PACKAGE_INDEX | PASS 16/16 | Exact byte lengths and SHA-256; original archive SHA-256 in engineering plan |
| Repository baseline + working branch | VERIFIED | main pinned, independent feature branch; no merge |
| Swift / macOS GUI in authoring environment | UNAVAILABLE | Linux; no local Swift toolchain. Actual native tests/builds run on GitHub macOS Actions |
| Authored-source `git diff --check` | PASS | Authored code/docs only. Exact upstream licenses/research retain their original whitespace. |
| macOS Swift tests | PASS 139/139 | Capture48 + Core30 + UI17 + Adapters44 at `97f10b0`; actual macOS runner |
| Actual Web handoff source/evidence | VERIFIED + OFFLINE REPLAY PASS | Exact6f415698 archive, 55manifest entries, 19historical cases, 89real-trace prefixes, 2simulated late-error vetoes; not new live tests |
| Integrated bundled page program | PASS 9/9 synthetic VM | Actual shipped JS against controlled DOM events; no live Chrome or GUI |
| Release build + `.app` + ad-hoc signature verification | PASS | ARM64 development application, not notarized or publicly released |
| Packaged executable `--self-check` | PASS | Actual built executable; synthetic private import→queue→receipt→restart, no GUI or ChatGPT |
| Relocated `.app` `--web-acceptance-self-check` | PASS | Page resource loaded from the copied app, isolated mode/policy checks; explicitly `CHROME_NOT_RUN; GUI_NOT_RUN` |
| GUI acceptance helper fixture `--self-check` | PASS | 12 generated PNGs, 2/3/12 scenes and layout/state checks; explicitly `GUI_NOT_RUN` |
| Inherited Oracle offline cases | REPRODUCED 4/4 | Node24.22.1/Linux; source fixture counterexamples only |
| First-click focus / transparent hit / fullscreen / multi-monitor | NOT_RUN | Requires authorized real Mac GUI |
| Real system screenshot latency and idle resources | NOT_RUN | No fabricated measurements |
| Integrated real ChatGPT completion / anomaly matrix | NOT_RUN | E07 actual source/scoped inherited evidence now reviewed; this combined program still needs live test. Registered Mac offline; ordinary App remains capture-only |

Production successful-completion and safe-retry profiles are both empty. Real screenshot automatic consumption is not enabled.

## W2 actual source integration — current native evidence

- Source commit: [`97f10b0bf03fbd9421083a15eefec0eb22ead606`](https://github.com/haohongfei2001-png/Riftlet/commit/97f10b0bf03fbd9421083a15eefec0eb22ead606), parentb5958d1; same Draft PR #1, no main merge/release.
- [Successful run40437937532](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532), job`121971048580`; completed2026-10-27 10:22:41Beijing. Runner macOS14.8.9/build23J631/arm64/Swift5.10, Node22.23.2. Temporary PR test merge`26fcd175e60ad144f8a7ad4d279c454632cf8542` is not a merge into main.
- Tests:139/139 native,9/9 integrated page VM; inherited archive replay55files/19cases/89prefixes/2simulated late errors. All successful. Release build, ad-hoc app/signature, capture/queue self-check, relocated Web resource/policy self-check and existing GUI helper fixture self-check passed.
- [Application, GUI helper and logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532/artifacts/12705495014), artifactSHA256`961936e9931175b469c1196527fd20a627a2cab8990019e25a526dbcdbc33e34`, expires2026-11-10. This is a development artifact, not a released/notarized app.
- Permanent [machine record](../engineering/evidence/2026-10-27/web-integration-verification.json), [exact log excerpt](../engineering/evidence/2026-10-27/web-ci-excerpt.txt), [handoff review](../engineering/evidence/2026-10-27/web-handoff-review.json), and [program review](../engineering/evidence/2026-10-27/web-integration-review.json).

Actual parallel ownership: root implemented App/Core policy/resources/build integration; `w2_implementation` implemented the page/adapter; `w2_evidence_review` independently audited source and inherited traces; `n1_native_acceptance` checked the authorized Mac and reviewed root's integration after finding it offline. Review fixed original-node equality, transient removal/source restoration, proof provenance, bounded invalid buffers and post-journal-recovery synthetic isolation. These distinct agents are technical non-authors, not human GitHub approvers or extra Macs.

The only real uploads in the imported evidence are the other Codex session's recorded experiments. New NodeVM cases and Swift fake transport tests do not add real uploads. The integrated acceptance mode can exercise generated-image consumption with its own profile, but cannot consume real screenshots or grant retry. Production late-failure revival is still absent. [MAC_ACCEPTANCE](MAC_ACCEPTANCE.md) supplies the direct live continuation steps; no extra planning or module rebuild is needed.

## Original foundation macOS run — historical evidence

- [Successful workflow](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770), job `121764396954`, completed 2026-10-27 02:25:32 Beijing.
- Tested source head: `2f60f01657cc29e7a4cabe41792c6ccd558d6974`. PR's temporary integration commit: `88119b980c8546079129626877b8057709934f3c`. This temporary test merge is **not** a merge into main.
- Environment: macOS14.8.9 / build23J631 / arm64 / Apple Swift5.10 (`swiftlang-5.10.0.13`).
- Debug/test compilation 12.81s; release compilation13.07s. These are CI build durations, not screenshot/upload latency.
- [Build artifact and logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770/artifacts/12675615934): contains `Riftlet-macOS-development.zip` (app zipped with executable permissions) and test/build/self-check logs. Artifact retention14days; source, workflow and this evidence remain in git. Artifact outer ZIP SHA-256 `b5d33fbbd2e46b67f69448a47ccceeb8899bf01a309bb916c4c6436a39e17f7d`.
- [Machine-readable evidence](../engineering/evidence/2026-10-27/verification.json) and [compiler/test excerpt](../engineering/evidence/2026-10-27/macos-ci-excerpt.txt).

The first run exposed nested weak-reference capture concurrency errors; these were fixed in the tested source commit. The successful run compiles all native targets and runs all40 tests, not only a stub. The final evidence/documentation commit changes no source/build/test files, so it does not repeat this completed gate.

## Continuous delivery — actual code and native execution

| Tested source commit | Native test count | Successful workflow | Included increment |
| --- | --- | --- | --- |
| `94df78c74e75cf79b7832e62a228c6fd37913cf9` | 63 | [40386356404](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40386356404) | Q1/Core recovery, W0 normalization and U1 helper |
| `3e7b8eac6c3bd235f4e376172d6085ab0d5b4426` | 98 | [40387437225](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40387437225) | C1 source binding, U2 layout, W1 transport and D1 storage |
| `1afd849a9b2d2cfada0d01cd47b5f1ee31f83d37` | 127 | [40388958638](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40388958638) | C2 faults/recovery and M0 injected Mac flow |
| `e76e7985c05197c487dd4e7f585dc028ed64b1af` | **134** | [40389753080](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40389753080) | C1 review fixes and nonblocking special-file rejection |

All four runs completed successfully on macOS14.8.9 arm64 / Apple Swift5.10. Each ran `swift test --parallel`, release build, actual ad-hoc `.app` packaging/signature verification, packaged App self-check and the separate GUI helper fixture self-check. The final run's job is `121807449326`; its temporary PR test merge `847471105ad2520e897a0d32e3a3e8337e5db0e1` is not a merge into main.

The [previous foundation artifact](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40389753080/artifacts/12682330742) includes `Riftlet-macOS-development.zip`, `Riftlet-GUI-Acceptance.zip` and test/build/self-check logs. Outer artifact SHA-256: `5f7c9eb727e8fb751c569b0b2e6e67254e7bf01f63d327b928f439dd62179d19`. Artifacts expire after14days; source, workflow and the durable evidence records remain in git.

Permanent records: [machine-readable run/review/scope data](../engineering/evidence/2026-10-27/continuous-verification.json) and [native log excerpts](../engineering/evidence/2026-10-27/continuous-ci-excerpt.txt). Documentation/checkpoint commits after the final source commit change no native source, tests, dependencies, resources or build entry points. PR-wide path matching may trigger another automatic run; such a run is separate, not predeclared successful.

### Independent review and concrete fixes

The root integrated and implemented Core, App wiring, part of C2 and the special-file fix. Three independent agents actually ran C1/U1/W0 concurrently, then took C2/U2/W1/D1/M0 or reviewed another author's code. This was one shared workspace with disjoint ownership, not three separate Mac machines or an unattended background coding service.

- Core/Q1 was reviewed by `ui_u1` and `adapter_w0`; the root's missing-media recovery fix and transaction rollback tests were independently checked.
- U1/U2/D1 modules were reviewed by root; C1/D1 App wiring was reviewed by `ui_u1`. The GUI helper no longer logs key codes, and large configured insets no longer move fitted rows outside narrow screens.
- W0/W1 were reviewed by root and `ui_u1`. Nested unknown observation fields are rejected, and AppleScript runs on a shared serial utility queue rather than blocking MainActor.
- C1's initial CI pass did not close its later review findings. `ui_u1` identified the handoff-await arrival gap, stale start after stop and unreadable terminal-enumeration gap. The author fixed these and added five targeted tests; the final134-case run covers them.
- C2 was authored by `capture_c1` and root and reviewed by `ui_u1`. Journal rename transfers ownership before directory sync; stage-directory ordering, persistent SQL locks, recovery IO errors, unreadable journals, malformed JSON isolation and used-record preservation are tested. The author also independently read root's additions.
- M0 was reviewed by root and `ui_u1`. A separately admitted terminal failure now releases the local input lease for a later explicit retry, while retaining clipboard bytes; UNKNOWN and unadmitted failures do not unlock or paste again.
- Root fixed the FIFO open-before-fstat issue found by `ui_u1`; the reviewer also caught and helped bound the regression harness's rescue path. The two tests use actual `mkfifo` files and pass on the native runner.

Review here means non-author technical review by distinct execution agents. It is not a human GitHub approval or authorization to merge/publish. The branch and PR remain isolated and draft.

## Material remaining limits

- C1 now automatically rebinds from preference-file/parent events, with durable old-directory handoff and startup generation guards. Temporary-file watcher cases are automated; actual Screenshot.app propagation, TCC/permission UX and real sleep remain system acceptance.
- Delayed metadata/partial writes get five bounded retries; a later event/wake/rescan can retry again. No indefinite polling is used. Real-system coverage must establish whether a supplementary metadata observer is needed.
- Used media and journals are retained because archive/delete semantics are undecided. Unjournaled staging fragments are not auto-imported or auto-deleted. Retention/recovery cleanup remains a scoped follow-up.
- Recovery preserves journal ownership across IO/SQL failures and never labels an unreadable journal as safely discarded. A storage IO error conservatively stops that recovery call; startup may therefore remain paused until access is restored. Malformed JSON is isolated from unrelated valid journals. These are distinct behaviors, not a claim that every IO failure is isolated per image.
- C2 interruptions use real temporary files/SQLite and deterministic in-process fault hooks plus reopening; no SIGKILL, OS crash or power-loss test is claimed. `fsync` ordering was reviewed and executed, not certified as hardware power-loss protection.
- The current build is ARM64 on the verified runner. Intel and the user's newer macOS build are not claimed tested.
- Transparent minimum-hit rectangles, fullscreen behavior and exclusion from Apple's own screenshots are not established by pure layout tests.
- Developer simulation is not an upload adapter, and the production build intentionally retains real images.
- Web page source and scoped real evidence are now imported and adapted. The new combined program is compiled/offline-tested, not live-tested; foreground/window/tab guards still do not establish click-time tab identity before queued Apple Events. Scope is currently Home Chat/Chinese labels/PNG, not arbitrary existing conversations. Same-URL draft changes and production post-consumption late-failure revival remain unresolved. Mac has only injected platform drivers; cross-instance/restart clipboard coordination remains required before native enablement.

## Autonomous execution plan v2 — historical documentation increment

The follow-up authorization was recorded in AGENTS, decision entries P12/P13 and the v2 engineering plan, with a concrete execution board and PR template. Web/Mac implementation is separated from real-evidence admission. Reuse provenance was rechecked; Oracle's archive count is now described precisely as six source/fixture files plus LICENSE.

This increment changes documentation and the PR template only. Native sources, tests, resources, licenses, `Package.swift`, build scripts and the native workflow are unchanged relative to the tested source head above. The macOS run was read back as completed/success at that exact SHA; that existing evidence is not relabeled as a new validation. No extra manual native run is needed for the documentation, but the existing PR-wide path trigger may automatically run CI again; any such result belongs to its own SHA/run and is not predeclared passed. New plan packets marked READY are not claimed implemented.

Validation for this increment: authored `git diff --check`, relative Markdown target checks, conflict-marker/whitespace checks, non-author execution-plan review and a separate actual-reuse/license audit. The audit confirmed the two adaptations, independently implemented Tendedero-informed panels, reference-only Oracle/Maccy status and license packaging. Main was observed at `6dfba79f9ccef295cc0234580a3adc99f0757e09`; its additional website-only change was inspected and left untouched.
