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
| Swift / macOS GUI in authoring environment | UNAVAILABLE | Linux; no local Swift toolchain. Mac Actions is the planned compile/test executor |
| Authored-source `git diff --check` | PASS | Authored code/docs only. Exact upstream licenses/research retain their original whitespace. |
| macOS Swift tests | PASS 40/40 | Capture12 + QueueStore12 + Coordinator6 + Layout/Pointer10; real macOS runner |
| Release build + `.app` + ad-hoc signature verification | PASS | ARM64 development application, not notarized or publicly released |
| Packaged executable `--self-check` | PASS | Actual built executable; synthetic private import→queue→receipt→restart, no GUI or ChatGPT |
| Inherited Oracle offline cases | REPRODUCED 4/4 | Node24.22.1/Linux; source fixture counterexamples only |
| First-click focus / transparent hit / fullscreen / multi-monitor | NOT_RUN | Requires authorized real Mac GUI |
| Real system screenshot latency and idle resources | NOT_RUN | No fabricated measurements |
| Real ChatGPT completion / anomaly matrix | NOT_RUN in this branch | Parallel Codex session owns current real validation; current App adapter disabled |

Production successful-completion and safe-retry profiles are both empty. Real screenshot automatic consumption is not enabled.

## Actual macOS run

- [Successful workflow](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770), job `121764396954`, completed 2026-10-27 02:25:32 Beijing.
- Tested source head: `2f60f01657cc29e7a4cabe41792c6ccd558d6974`. PR's temporary integration commit: `88119b980c8546079129626877b8057709934f3c`. This temporary test merge is **not** a merge into main.
- Environment: macOS14.8.9 / build23J631 / arm64 / Apple Swift5.10 (`swiftlang-5.10.0.13`).
- Debug/test compilation 12.81s; release compilation13.07s. These are CI build durations, not screenshot/upload latency.
- [Build artifact and logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770/artifacts/12675615934): contains `Riftlet-macOS-development.zip` (app zipped with executable permissions) and test/build/self-check logs. Artifact retention14days; source, workflow and this evidence remain in git. Artifact outer ZIP SHA-256 `b5d33fbbd2e46b67f69448a47ccceeb8899bf01a309bb916c4c6436a39e17f7d`.
- [Machine-readable evidence](../engineering/evidence/2026-10-27/verification.json) and [compiler/test excerpt](../engineering/evidence/2026-10-27/macos-ci-excerpt.txt).

The first run exposed nested weak-reference capture concurrency errors; these were fixed in the tested source commit. The successful run compiles all native targets and runs all40 tests, not only a stub. The final evidence/documentation commit changes no source/build/test files, so it does not repeat this completed gate.

## Material remaining limits

- Collection is event-driven for the configured local directory. Live source preference changes currently refresh on wake or the developer menu; fully automatic preference rebinding and one-time bookmark/permission UX remain work.
- Delayed metadata/partial writes get five bounded retries; a later event/wake/rescan can retry again. No indefinite polling is used. Real-system coverage must establish whether a supplementary metadata observer is needed.
- Used media and journals are retained because archive/delete semantics are undecided. Unjournaled staging fragments are not auto-imported or auto-deleted. Retention/recovery cleanup remains a scoped follow-up.
- The current build is ARM64 on the verified runner. Intel and the user's newer macOS build are not claimed tested.
- Transparent minimum-hit rectangles, fullscreen behavior and exclusion from Apple's own screenshots are not established by pure layout tests.
- Developer simulation is not an upload adapter, and the production build intentionally retains real images.

## Autonomous execution plan v2 — 2026-10-27

The follow-up authorization was recorded in AGENTS, decision entries P12/P13 and the v2 engineering plan, with a concrete execution board and PR template. Web/Mac implementation is separated from real-evidence admission. Reuse provenance was rechecked; Oracle's archive count is now described precisely as six source/fixture files plus LICENSE.

This increment changes documentation and the PR template only. Native sources, tests, resources, licenses, `Package.swift`, build scripts and the native workflow are unchanged relative to the tested source head above. The macOS run was read back as completed/success at that exact SHA; that existing evidence is not relabeled as a new validation. No extra manual native run is needed for the documentation, but the existing PR-wide path trigger may automatically run CI again; any such result belongs to its own SHA/run and is not predeclared passed. New plan packets marked READY are not claimed implemented.

Validation for this increment: authored `git diff --check`, relative Markdown target checks, conflict-marker/whitespace checks, non-author execution-plan review and a separate actual-reuse/license audit. The audit confirmed the two adaptations, independently implemented Tendedero-informed panels, reference-only Oracle/Maccy status and license packaging. Main was observed at `6dfba79f9ccef295cc0234580a3adc99f0757e09`; its additional website-only change was inspected and left untouched.
