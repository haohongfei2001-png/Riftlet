# Riftlet

**Riftlet** is a proposed tiny, native macOS screenshot-to-chat bridge: **take a system screenshot, then click its micro-thumbnail once**. The intended result is an image appended to the correct ChatGPT draft—not a sent message.

**Status (2026-10-27): Active native development.** This branch contains automatic screenshot-source rebinding, SQLite v3 capture/queue state, upload-start-driven visual exit, persistent hide/removal/archive, lightweight native history, isolated Web/Mac adapter foundations and a synthetic GUI acceptance helper. There is no approved final visual design or admitted production ChatGPT adapter yet. **Native tests, Release packaging/signature and synthetic executable self-checks run on macOS14 ARM64 CI; the latest exact tested input and outcome are recorded below.** Exact tested commits/counts and remaining real-environment cases are in [the verification record](docs/VERIFICATION.md); [the execution board](docs/EXECUTION_BOARD.md) is the continuation checkpoint.

**Execution update:** routine engineering now proceeds autonomously with parallel module ownership and independent technical review; no per-increment user approval is required. The [v2 dependency plan](docs/ENGINEERING_PLAN.md) separates implementation from real-evidence admission, and the [live execution board](docs/EXECUTION_BOARD.md) identifies ready work, scoped waits and the next concrete actions. Production attachment profiles remain disabled until their evidence gates pass.

**Latest functional increment:** fifth-round Web v11 now shares the same native app with first-use/status guidance and permission recovery. Reviewed upload-start evidence is admitted only for generated images in explicit isolated Web acceptance; append returns at start, Core persists hidden visibility separately from final success, and legacy v6–v10 operations remain read-only. The two minimal acceptance overlays are integrated; the failed CUA window-ordering experiment is archived only. Ordinary capture, SQLite v3/history and first-use protections remain intact.

**Web integration boundary:** production screenshot upload and all Web safe-retry profiles remain disabled. The existing offline simulator remains separate. Passive Automation checks preserve the original frozen click target; Chrome activation/wake can now recover an initially unavailable browser without another settings visit or click replay. The local Mac executor continues round six independently; no unhanded-off branch was read or merged. The original fifth-round AX sample proves a scoped generated-image chain, not the new binary's permission/latency or physical-click acceptance. [Current handoff](docs/INTEGRATION_HANDOFF.md) · [unchanged receipt v1 and updated scoped admission](docs/UPLOAD_STARTED_CONTRACT_V1.md#8-第五轮正式合流受限开始准入与下一真机入口).

**Current tested input:** [`caa6a65`](https://github.com/haohongfei2001-png/Riftlet/commit/caa6a65b69c6038154a2fff65f2fb1157125bb7e), a two-parent integration of e655b1e and 3bb13999. [Full macOS CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640) passes **369 native tests**, page68/legacy45, diagnostic helpers9/4/2, packaging12, existing replay/fault/probe, Release/signature and four self-checks. Detailed lifecycle13/setup3/capture15/presentation4/Web-composition5/passive-resume8 all passed with no skips; repeats are already in369. [Development App/helper/logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640/artifacts/12739217183) · [permanent evidence and non-author review](engineering/evidence/2026-10-27-integration-round5/README.md). First ordinary launch opens first-use guidance; explicit Web acceptance uses generated images only. ARM64/ad-hoc, not a notarized public release.

## The distinctive interaction

- Extremely fine vertical **spatial rift** at the screen edge; tiny, aspect-ratio-preserving, roughly coin-sized screenshots protrude partly from it.
- Oldest at top. Everyday pending queue is normally **2–3 images**, occasionally 10+; each screenshot shows only the image and a simple number.
- Normal use takes **exactly two user actions**: macOS screenshot; click its thumbnail. No upload shortcut, drag-and-drop, file picker, extra confirmation or manual paste.
- On **positive evidence that this screenshot actually started uploading to the current click-time ChatGPT draft**, it **swallows and disappears very quickly**—without waiting for verified READY. Only explicit or extremely high-confidence actual failure makes it reappear. UNKNOWN after start is retained in internal local history without blind re-upload or indefinite visible queue blockage. Zero visible screenshots means **no visible rift**. Stale screenshots auto-archive; users can remove one or many. Core/UI/App implement this lifecycle; real Web start and safe-failure evidence still require separate adapter integration and admission. **Further clarified:** no valid composer/attachment entry means no disappearance; classified failure rebirths as an ordinary clickable screenshot; no extra success Toast because the user sees the attachment in the ChatGPT draft; clearing queue never remotely removes attachments. Faster repeated clicks are conditional on reliability; hold-to-drag is only under consideration.
- Never automatically send a ChatGPT message.

The **Screenshot Rift** name appears in the dated original studies; **Riftlet** is the present repository name. Initial repository wording about clipboard content and arbitrary applications is not an approved V1 requirement; those are potential later extensions.

## Start here

| Subject | Document |
| --- | --- |
| User product requirements | [docs/PRODUCT.md](docs/PRODUCT.md) |
| Implemented upload-start interface and isolated demo | [docs/UPLOAD_STARTED_CONTRACT_V1.md](docs/UPLOAD_STARTED_CONTRACT_V1.md) |
| Latest fast-swallow / ephemeral-rift contract | [docs/INTERACTION_CONTRACT_2026-10-27.md](docs/INTERACTION_CONTRACT_2026-10-27.md) |
| First-use implementation and real-Mac acceptance | [docs/FIRST_USE_ACCEPTANCE.md](docs/FIRST_USE_ACCEPTANCE.md) |
| Consumer release UX baseline | [docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md](docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md) |
| Pro focused feasibility review brief | [docs/PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md](docs/PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md) |
| Pro feasibility conclusions and implementation handoff (research, not acceptance) | [docs/PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md](docs/PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md) |
| Decided vs. proposed | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Executable engineering plan | [docs/ENGINEERING_PLAN.md](docs/ENGINEERING_PLAN.md) |
| Autonomous parallel work queue | [docs/EXECUTION_BOARD.md](docs/EXECUTION_BOARD.md) |
| Exact implemented reuse and licenses | [docs/REUSE_IMPLEMENTATION.md](docs/REUSE_IMPLEMENTATION.md) |
| Code, CI and remaining acceptance evidence | [docs/VERIFICATION.md](docs/VERIFICATION.md) |
| Current visual design brief | [docs/DESIGN_BRIEF.md](docs/DESIGN_BRIEF.md) |
| Archived art direction and offline visual sample | [design/explorations/art-direction-2026-10-26/README.md](design/explorations/art-direction-2026-10-26/README.md) |
| All archived visual studies | [design/README.md](design/README.md) |
| Platform and upload research | [docs/TECHNICAL_BASELINE.md](docs/TECHNICAL_BASELINE.md) |
| Reusable source research | [docs/REUSE_CANDIDATES.md](docs/REUSE_CANDIDATES.md) |
| Questions that remain | [docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) |
| Full Pro response | [research/PRO_REVIEW_REPLY_2026-10-26.md](research/PRO_REVIEW_REPLY_2026-10-26.md) |
| Full 23-page Pro PDF **text extraction** | [research/PRO_REVIEW_PDF_TEXT_2026-10-26.txt](research/PRO_REVIEW_PDF_TEXT_2026-10-26.txt) |
| Codex first experiment evidence | [research/CODEX_EXPERIMENT_STATUS_2026-10-26.md](research/CODEX_EXPERIMENT_STATUS_2026-10-26.md) |
| Original sources, limits | [research/SOURCES.md](research/SOURCES.md) |

**Engineering proceeds on an isolated Draft PR; no unreviewed merge or release.** Please do not commit real user screenshots, private chats, credentials, unrelated project files or test browser profiles to this public repository.

## Build the native foundation (macOS 13+)

```bash
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
open build/Riftlet.app --args --simulate
```

Simulation uses only synthetic images in its own data directory and never connects to ChatGPT. Run without `--simulate` to collect actual system screenshot files; the production upload adapter remains disabled, so clicks retain the screenshot. This is an engineering build with an ad-hoc signature, not a notarized release. [Real Mac acceptance](docs/MAC_ACCEPTANCE.md) lists the remaining GUI checks.

The separate **Web acceptance mode** uses the real native bridge, generated images and an isolated queue. Its inherited page scope is the observed Chinese Home/ordinary Chat form and bounded PNG input; this increment does not broaden that scope or add a start/failure profile. See [the exact startup and acceptance steps](docs/MAC_ACCEPTANCE.md#w2-integrated-web-acceptance-entry--available-live-test-not_run). It never sends a message or retries an UNKNOWN input, and its development completion profile cannot consume system screenshots. Local Codex owns the next live test from the formal checkpoint; this remains a development-only adapter.


## Prelaunch website (2026-10-27)

The first prelaunch brand site has been prepared as a static GitHub Pages candidate: [index.html](index.html). It contains a wholly **simulated** screenshot-to-draft interaction. The website does **not** upload real screenshots, connect to ChatGPT, or offer a working app download. Neither the visual direction nor the product adapter has final user acceptance.

See [website/README.md](website/README.md) for publication instructions and evidence boundaries. GitHub Pages and the custom domain `riftlet.com` must be configured through repository settings and the domain's DNS provider; committing files alone does not prove a live site.
