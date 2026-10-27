# Riftlet — user-approved product specification

**Latest product contract (2026-10-27):** [fast swallow, ephemeral rift, archive and failure revival](INTERACTION_CONTRACT_2026-10-27.md). This supersedes the historical READY-only swallow / visible UNKNOWN requirements below; this document has been updated to reflect the latest user decision.

**Phase (2026-10-27):** formal engineering authorized; foundation implementation in progress. Exact appearance and attachment admission remain unfrozen. This phase update supersedes the old research-only restriction without changing the product contract below.

## Product
An independent macOS tool that automatically collects the result of the **existing system screenshot**, places a tiny thumbnail at the screen edge, and transfers it to the currently intended ChatGPT composer on **one click**. It appends an **unsent attachment**, not a message.

## Required everyday operation
**Exactly two user actions:** (1) take the normal macOS screenshot; (2) click the screenshot in the rift. The product must not require a separate keyboard shortcut, drag/drop, paste, file picker, extension button, conversation chooser or repeated confirmation. **Optional press-and-drag is only being considered, not approved, and must never slow normal one-click attachment.** One-time installation/permissions are outside the everyday two-step cycle.

## Rift layout and behavior
- Extremely thin **vertical spatial rift** on a screen edge, with screenshots appearing partially swallowed/protruding. **With zero visible screenshots, the rift is entirely absent (no persistent line).** A new screenshot emerges from the rift when it arrives.
- **Roughly coin-sized** thumbnail; preserve original aspect ratio. Show only image and minimal numeric label; naming/dates belong to a separate optional application window.
- **Oldest currently visible screenshot at top**, next screenshots below. On positive evidence of upload *starting*, the clicked image rapidly swallows into the rift and leaves the visible queue; lower items shift up. Do not wait for confirmed READY or upload completion to animate.
- Normally **2–3** pending screenshots; sometimes 4–8, rarely more than 10. Do not optimize around indefinite screenshot accumulation.
- A newly captured screenshot should remain easily accessible even in an atypically longer queue.
- No requirement to hover-expand before clicking, and no large traditional shelf or toolbar.
- The visible rift is a **short-lived working queue**, not permanent storage. A screenshot may be used, removed individually, removed in bulk, or automatically archived after a long idle period. These actions remove it from the visible queue without deleting the original system screenshot. An archive interval and permanent private-copy deletion rules remain unapproved.
- Consumed, uncertain and archived screenshots remain discoverable in a minimal internal local history rather than occupying the rift. A screenshot already inserted into the draft stays swallowed unless that upload is actually classified as failed; users who wish to find it again look in the original macOS screenshots or Riftlet's internal history.
- Single/bulk clear affects Riftlet visible queue only; **never remove existing attachments from ChatGPT's draft**.

## Result states (must not be conflated)
| Event / result | Product response |
| --- | --- |
| Click dispatched; upload start not yet evidenced | Immediate, very light press feedback. No false swallow while merely queued, performing preflight, or displaying a placeholder. |
| **Actual upload started** for the clicked asset in its original target, backed by positive evidence | **Very fast swallow and complete disappearance during the animation.** Remove from **visible queue** immediately; keep file and operation in internal local storage. Do **not** wait for verified READY or 100%. |
| Exact attachment later verified ready/successful | Record durable success in the background. **No success Toast/notification.** The user checks the attachment in the ChatGPT draft before deciding to send. |
| **Explicit or extremely high-confidence actual upload failure** | **Must rebirth as a normal, immediately clickable screenshot**, with ordinary later click/remove/idle-archive lifecycle. User clicks again to start a fresh attempt, never an automatic retry. Improve failure classification/eligibility evidence instead of showing unclickable reborn thumbnails. |
| **UNKNOWN after started upload** (navigation, timeout, lost reply, crash) | Stay swallowed in internal history/pending verification, **not** indefinitely visible or permanently blocking distinct later screenshots. Only reconcile the original operation; no blind re-upload. |
| **No available composer, no supported attachment entry, no valid current target, or input did not begin** | Thumbnail **does not swallow or disappear** after the click; never silently choose another window. |
| Long-unused visible screenshot | Archive automatically, leaving the original system screenshot untouched. Exact idle duration remains undecided. |

The only target is the **currently active, unambiguously identified supported ChatGPT window/draft at the instant of the click**; no pinned target, last-used target or intelligent guess. Freeze the click-time identity before asynchronous transfer; later window/tab changes must not redirect it. Preserve previously typed text and existing attachments.

**Swallowed visibility is not proof of successful attachment.** Actual upload start, eventual completion and safe retry are separate state/evidence decisions. On uncertain results after start, keep the asset internally and continue observation without a permanent visible queue lock. Only strong evidence of actual failure permits rebirth; **once reborn it must be clickable**. A timeout or lost observer alone does not establish failure. Optimize near-consecutive screenshot clicks only where stability and user experience are preserved. See the latest [interaction contract](INTERACTION_CONTRACT_2026-10-27.md).

## First target and scope
First discussed destinations: ChatGPT **web and macOS app** (new desktop and Classic may need separate verification). Support for other AI apps, arbitrary app input and generic clipboard collection is **possible future work**, not a fixed launch promise.

No standalone screenshot engine, OCR, image editor, AI tagging, cloud sync, broad file management or automated message sending in the initial concept.
