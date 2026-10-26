# Riftlet website — original art direction restored

Date: 2026-10-27. Status: **prelaunch design preview; not a released client**.

## Current visual source

The user explicitly asked to restore the design they had previously requested be archived, rather than continue redesigning the first published landing page.

Source: [`design/explorations/art-direction-2026-10-26/Riftlet_Art_Direction.html`](../design/explorations/art-direction-2026-10-26/Riftlet_Art_Direction.html), original Git blob `900d0b13f076aae9fd2e2d00c32f5984aa4ee796`.

The root `index.html` now derives directly from that original HTML, not from the alternate composition introduced in `5a3ab5d`.

Restored: the capitalized Riftlet wordmark and gap-shaped R study; off-white background and dark/teal Chinese serif headline; original left/right proportions and whitespace; pale teal curved plane; original apricot print, white note and teal card; the vertical occluding plane and “A little space.”; original section order, colour study and small-scale interaction demo.

The four original SVG symbols, hero-art DOM and inline demo script are unchanged. CSS declarations and responsive media queries match the original; one adjacent `.principle p` colour declaration is regrouped without changing its value or cascade. No screenshot is substituted for real page markup.

## Publication adaptations

Only the publication title/SEO metadata, favicon reference, honest prelaunch notices, development link and footer language switch are added or adjusted. `website-locale.js` is a text-only Chinese/English enhancement; it does not replace the artwork, reset the simulation or modify the editable draft. Chinese is the initial language to preserve the supplied reference.

The restored stylesheet and simulation are inline in `index.html`, just as in the archived source. The previous root `site.css` and `site.js` are retained for history but **not loaded** by the current page. Do not reattach them: their selectors and layout belong to the superseded composition.

Fonts remain local system stacks. No font files are copied, bundled or uploaded. Rendering can differ across operating systems. The R mark remains a design study rather than a final application icon.

## Product and privacy boundaries

The website demonstrates intended screenshots/clipboard positioning, not shipped capabilities. The client is not available for download. The interactive demo uses three synthetic images and simulated ready/failure/unknown outcomes. It does not connect to ChatGPT, inspect the system clipboard, collect real screenshots or send messages. A simulated ready consumes an item, failure restores it, unknown preserves it without replay. Existing draft text is not overwritten.

No app source, product requirements, archived designs, DNS, CNAME, Pages settings or hosting provider are changed by this restoration.

## Validation and limits

Performed: source hash check against the archived HTML; original SVG/hero-art/demo comparisons; stylesheet declaration equivalence; HTML parse, unique IDs and internal anchor checks; JavaScript syntax checks; Node VM tests using a minimal DOM stand-in for duplicate clicks, ready-only consumption, held positions, compaction, draft preservation, failure retry, unknown replay prevention, serial processing and reset-generation isolation; translation pure-function checks.

**Not performed:** screenshot comparison of the newly rendered site, real-browser interaction tests, mobile-device visual acceptance, or real ChatGPT insertion. Chromium local-file navigation returned `ERR_BLOCKED_BY_ADMINISTRATOR`; no policy or browser-security changes were attempted. The public web reader also could not access the domain during this task. Static and simulated-DOM checks are not browser visual acceptance.

See [the restoration receipt](RESTORE_ART_DIRECTION_2026-10-27.md).

## Existing deployment

Continue the already configured GitHub Pages publication from `main`, repository root, with `riftlet.com`. Do not repeat DNS setup or provision another platform. A main-branch commit may trigger the existing Pages workflow; confirm its result separately from whether the current public page has been independently read back.
