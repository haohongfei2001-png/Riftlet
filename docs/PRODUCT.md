# Riftlet — user-approved product specification

**Phase (2026-10-27):** formal engineering authorized; foundation implementation in progress. Exact appearance and attachment admission remain unfrozen. This phase update supersedes the old research-only restriction without changing the product contract below.

## Product
An independent macOS tool that automatically collects the result of the **existing system screenshot**, places a tiny thumbnail at the screen edge, and transfers it to the currently intended ChatGPT composer on **one click**. It appends an **unsent attachment**, not a message.

## Required everyday operation
**Exactly two user actions:** (1) take the normal macOS screenshot; (2) click the screenshot in the rift. The product must not require a separate keyboard shortcut, drag/drop, paste, file picker, extension button, conversation chooser or repeated confirmation. One-time installation/permissions are outside the everyday two-step cycle.

## Rift layout and behavior
- Extremely thin **vertical spatial rift** on a screen edge, with screenshots appearing partially swallowed/protruding.
- **Roughly coin-sized** thumbnail; preserve original aspect ratio. Show only image and minimal numeric label; naming/dates belong to a separate optional application window.
- **Oldest pending screenshot at top**, next screenshots below. On consumption the image disappears and lower items smoothly move up.
- Normally **2–3** pending screenshots; sometimes 4–8, rarely more than 10. Do not optimize around indefinite screenshot accumulation.
- A newly captured screenshot should remain easily accessible even in an atypically longer queue.
- No requirement to hover-expand before clicking, and no large traditional shelf or toolbar.
- The user intends pending screenshots to stay available until used or closed/removed. The precise semantics of close versus archive/delete remain **undecided**.

## Result states (must not be conflated)
| Event / result | Product response |
| --- | --- |
| Click dispatched | Immediate lightweight interaction response; preserve item identity |
| Attach operation begun or placeholder appears | Still pending; **not sufficient** to consume item |
| Exact image **verified READY in the correct draft** | Complete swallow animation; remove from pending queue; shift later items upward |
| **Explicit failure** | Reverse/restore thumbnail in its original queue position |
| **UNKNOWN** (navigation, timeout, lost reply, crash) | Preserve screenshot and reconcile; **no blind re-upload** |

The target draft is fixed at click time; background window/tab changes must not lead to a wrong chat. Preserve previously typed text and existing attachments.

## First target and scope
First discussed destinations: ChatGPT **web and macOS app** (new desktop and Classic may need separate verification). Support for other AI apps, arbitrary app input and generic clipboard collection is **possible future work**, not a fixed launch promise.

No standalone screenshot engine, OCR, image editor, AI tagging, cloud sync, broad file management or automated message sending in the initial concept.
