# Riftlet website refinement · 2026-10-30

## Scope and baseline

The owner requested a more refined, lively website with the quality associated with Craft. This candidate develops the approved V2 visual language, based on `main` at `ea22efe25e080bd2e4a4ccf4538dbf2286c803a6`. Product truth was checked against PR #1 at `edbdc7aae45c35878694e9fa376757dac7b630a8`.

This is an isolated review candidate. Adoption and public deployment remain the owner's decision. There are no native-app, DNS, CNAME, hosting-provider or release changes.

## What changes

- Chinese headline: **截图之后，思路继续。** English: **A screenshot. A thought continued.** The supporting copy explains the screenshot, edge thumbnail and current ChatGPT draft directly.
- Retains the approved teal split-R mark, local Chinese serif and Instrument Serif fonts, warm paper, cool desktop surface, original glass artwork, and three concrete example scenes.
- A clean active `website-v3.css` replaces the accumulated V2 styling; the historical CSS remains available. It calibrates type, surfaces, shadows, spacing, desktop/mobile composition and legibility.
- Scene controls sit beside the demonstration. Capture visibly carries the same picture from its source into the edge; clicking the picture attaches it to the illustrated draft. A compact three-stage row communicates the progression.
- Capture is FIFO. The three-image cap is explicitly a website-demo limit, not a native-product capacity claim.
- Cancellation removes animation travellers and pending attachments and restores an unconfirmed image. Hand-typed text and the original example note are preserved. Language/resize/background interruption also preserves completed attachments.
- Narrow English headlines fit their columns; the narrow-tablet hero uses a portrait composition. The desktop edge has sufficient vertical space for three portrait/landscape examples.
- Local font preloading and metadata/manifest color are aligned with the new presentation. No new external asset dependency or framework is introduced.

## Verified

- JavaScript syntax; duplicate IDs and attributes; fragment/ARIA references; local HTML/CSS/JS/font/image paths; SVG XML; manifest JSON.
- Browser review of desktop, 390px and 768px responsive documents in Chinese and English. The English headline was additionally checked against the bundled font's actual metrics.
- Complete illustrated capture/attach sequence: ready state, one added attachment, no pending item or traveller.
- Switching language while a portrait-image capture is in progress clears the traveller, restores visible screenshots and preserves hand-typed draft text.
- Consuming the entire queue hides the edge, preserves the original note and typed text, and leaves two ready illustrative attachments. Replay restores the two-example queue.
- Detail empty/full toggle, FAQ expansion, and release-dialog open/close in the browser.
- Final desktop view: assets loaded, fonts loaded, document complete, no horizontal overflow.
- Independent source review of cancellation, reduced-motion handling, accessibility relationships, claims and static resource integrity.

Browser QA used a cloud Chromium session and responsive iframe documents, not physical iPhone/iPad/macOS, Safari or VoiceOver. The shared preview briefly changed to an unrelated project; final checks resumed after restoring this checkout. This was a preview-resource conflict, not a product-runtime failure. No native upload or latency claim is based on these synthetic animations.

## Product boundaries

The native Mac application remains in private testing, without a public download. Current testing focuses on ChatGPT in Chrome. The website demonstration does not read the screen/clipboard, persist entered text, call external APIs, upload files or send messages. The FAQ retains the distinction between local screenshot copies, deliberately attached images sent to ChatGPT, and voluntarily submitted feedback.

## Review and adoption

Active files: `index.html`, `website-v3.css`, `website-v2.js`, `site.webmanifest`, and the unchanged `website-assets/`.

A self-contained offline HTML preview is delivered separately for visual review. When adoption is authorized, publish only the website changes through the existing GitHub Pages root-on-main route. Preserve the exact website overlay when eventually integrating the native engineering branch.
