# Riftlet

**Riftlet** is a proposed tiny, native macOS screenshot-to-chat bridge: **take a system screenshot, then click its micro-thumbnail once**. The intended result is an image appended to the correct ChatGPT draft—not a sent message.

**Status (2026-10-27): Active native development.** This branch contains automatic screenshot-source rebinding, durable capture/queue/rift modules, isolated Web/Mac adapter foundations, on-demand storage diagnostics and a synthetic GUI acceptance helper. There is no approved final visual design or admitted production ChatGPT adapter yet. **Native tests, release build, app packaging/signature and synthetic executable self-checks pass on macOS14 ARM64.** Exact tested commits/counts and remaining real-environment cases are in [the verification record](docs/VERIFICATION.md); [the execution board](docs/EXECUTION_BOARD.md) is the continuation checkpoint.

**Execution update:** routine engineering now proceeds autonomously with parallel module ownership and independent technical review; no per-increment user approval is required. The [v2 dependency plan](docs/ENGINEERING_PLAN.md) separates implementation from real-evidence admission, and the [live execution board](docs/EXECUTION_BOARD.md) identifies ready work, scoped waits and the next concrete actions. Production attachment profiles remain disabled until their evidence gates pass.

**Latest functional increment:** the real Codex Web source/evidence handoff is now archived and integrated. Commit `97f10b0` adds the bundled ChatGPT page program and explicit native `--web-acceptance` mode with generated test images. It passes 139 native tests, 9 page-program VM regressions and relocated App resource self-checks on macOS CI. The registered interactive Mac is offline, so the integrated live upload/GUI/two-operation loop remains untested; the ordinary screenshot mode still cannot upload or swallow real images.

## The distinctive interaction
- Extremely fine vertical **spatial rift** at the screen edge; tiny, aspect-ratio-preserving, roughly coin-sized screenshots protrude partly from it.
- Oldest at top. Everyday pending queue is normally **2–3 images**, occasionally 10+; each screenshot shows only the image and a simple number.
- Normal use takes **exactly two user actions**: macOS screenshot; click its thumbnail. No upload shortcut, drag-and-drop, file picker, extra confirmation or manual paste.
- On **positive evidence that this screenshot actually started uploading to the current click-time ChatGPT draft**, it **swallows and disappears very quickly**—without waiting for verified READY. Only explicit or extremely high-confidence actual failure makes it reappear. UNKNOWN after start is retained in internal local history without blind re-upload or indefinite visible queue blockage. Zero visible screenshots means **no visible rift**. Stale screenshots auto-archive; users can remove one or many. This is the latest **desired** behavior, not yet implemented in the engineering build.
- Never automatically send a ChatGPT message.

The **Screenshot Rift** name appears in the dated original studies; **Riftlet** is the present repository name. Initial repository wording about clipboard content and arbitrary applications is not an approved V1 requirement; those are potential later extensions.

## Start here

| Subject | Document |
| --- | --- |
| User product requirements | [docs/PRODUCT.md](docs/PRODUCT.md) |
| Latest fast-swallow / ephemeral-rift contract | [docs/INTERACTION_CONTRACT_2026-10-27.md](docs/INTERACTION_CONTRACT_2026-10-27.md) |
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

The separate **Web acceptance mode** uses the real native bridge, generated images and an isolated queue. Its current page scope is ChatGPT Home/Chat with the observed Chinese UI and PNG. See [the exact startup and acceptance steps](docs/MAC_ACCEPTANCE.md#w2-integrated-web-acceptance-entry--available-live-test-not_run). It never sends a message or retries an UNKNOWN input, and its development completion profile cannot consume system screenshots. This is the next live-test entry point, not an admitted production adapter.


## Prelaunch website (2026-10-27)

The first prelaunch brand site has been prepared as a static GitHub Pages candidate: [index.html](index.html). It contains a wholly **simulated** screenshot-to-draft interaction. The website does **not** upload real screenshots, connect to ChatGPT, or offer a working app download. Neither the visual direction nor the product adapter has final user acceptance.

See [website/README.md](website/README.md) for publication instructions and evidence boundaries. GitHub Pages and the custom domain `riftlet.com` must be configured through repository settings and the domain's DNS provider; committing files alone does not prove a live site.
