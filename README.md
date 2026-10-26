# Riftlet

**Riftlet** is a proposed tiny, native macOS screenshot-to-chat bridge: **take a system screenshot, then click its micro-thumbnail once**. The intended result is an image appended to the correct ChatGPT draft—not a sent message.

**Status (2026-10-27): Formal engineering started.** This branch contains the native capture/queue/rift foundation and an isolated synthetic demo. There is no approved final visual design or admitted production ChatGPT attachment adapter yet. Read [the executable engineering plan](docs/ENGINEERING_PLAN.md) and [actual verification record](docs/VERIFICATION.md).

## The distinctive interaction
- Extremely fine vertical **spatial rift** at the screen edge; tiny, aspect-ratio-preserving, roughly coin-sized screenshots protrude partly from it.
- Oldest at top. Everyday pending queue is normally **2–3 images**, occasionally 10+; each screenshot shows only the image and a simple number.
- Normal use takes **exactly two user actions**: macOS screenshot; click its thumbnail. No upload shortcut, drag-and-drop, file picker, extra confirmation or manual paste.
- Only a **verified ready attachment in the correct draft** triggers final swallow and queue shift. A definitive failure reverses/recreates the thumbnail; an unknown result preserves it and never blindly re-uploads.
- Never automatically send a ChatGPT message.

The **Screenshot Rift** name appears in the dated original studies; **Riftlet** is the present repository name. Initial repository wording about clipboard content and arbitrary applications is not an approved V1 requirement; those are potential later extensions.

## Start here

| Subject | Document |
| --- | --- |
| User product requirements | [docs/PRODUCT.md](docs/PRODUCT.md) |
| Decided vs. proposed | [docs/DECISIONS.md](docs/DECISIONS.md) |
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


## Prelaunch website (2026-10-27)

The first prelaunch brand site has been prepared as a static GitHub Pages candidate: [index.html](index.html). It contains a wholly **simulated** screenshot-to-draft interaction. The website does **not** upload real screenshots, connect to ChatGPT, or offer a working app download. Neither the visual direction nor the product adapter has final user acceptance.

See [website/README.md](website/README.md) for publication instructions and evidence boundaries. GitHub Pages and the custom domain `riftlet.com` must be configured through repository settings and the domain's DNS provider; committing files alone does not prove a live site.
