# Riftlet website — product-first hero revision

Date: 2026-10-27. Baseline: `3f5248d6b1c0d32ad80141cbdee4ee16945e6f7b`.

## Authorization and scope

The user selected the review's recommendation to make the homepage hero explain the screen-edge screenshot interaction, then instructed: “做”. This change implements that hero improvement only. It does not redesign the selected teal R icon, alter native-client code, modify product branches, change DNS/hosting, create a release, or change the archived design studies.

The existing near-white/teal/apricot palette, Chinese serif headline and restrained spacing remain. The static tilted artwork is replaced by a synthetic desktop scene: a capture source, fixed partially exposed edge thumbnails, and an unsent draft. The Chinese hero kicker no longer suggests clipboard history is a shipped first-release feature. Release availability remains unchanged.

## Runtime

- `index.html` now loads `website-hero.css` and `website-hero.js`, both cache-versioned `hero-1`.
- Existing `website-product.css` and `website-product.js` remain byte-identical; the lower demonstration is independent.
- The content after the hero, beginning with `section.principle`, is byte-identical to the baseline.
- `favicon.svg` and every use of the selected icon remain unchanged.
- One finite introduction plays when sufficiently visible, unless reduced motion is requested. It does not loop. Playback can be paused or replayed, and direct interaction takes over.
- Manual capture adds the new sample without clearing existing attachments. Replaying the synthetic scenario clears demo attachments but preserves visitor-entered draft text.
- Attachment placeholders and simulated readiness are distinct. Only simulated readiness consumes the edge item. Clicks are serialized and repeated clicks cannot duplicate an attachment.
- Pointer/keyboard interaction preserves edge positions until the interaction leaves the queue.
- The site does not capture the real screen, read the clipboard, connect to ChatGPT, upload files or send messages. The source and draft are explicitly marked as web illustrations, not real client evidence.

## Verification actually performed

The exact deployed baseline was obtained through the existing GitHub Pages artifact, associated with the baseline commit; file Git blob hashes were checked. Direct local file navigation was blocked by the browser environment. No browser security settings were changed. The website's authorized source bytes were instead rendered in an in-memory Chromium document, with local CSS/JS inlined and all network requests blocked.

- JavaScript syntax checks passed.
- Existing `node website/test-product.cjs`: 11 unit scenarios passed.
- New `website/test-hero.py`: 23 browser checks passed, including Chinese/English layouts at 320, 390, 768, 1024, 1440 and 1920 CSS px; pending/ready separation; duplicate clicks; ordered multi-item insertion; pause/replay cancellation; draft preservation; keyboard interaction; independent lower demo; reduced motion; finite autoplay; and no-JavaScript fallback.
- Actual in-memory Chromium screenshots were inspected at desktop and mobile widths. Screenshot reference sizes include 1440 × 1000 and 390 × 844 CSS viewport, DPR 1; full-page mobile captures are taller than the viewport. Font rendering uses the test environment's local font stacks, not a claimed macOS/Safari match.

Run the browser checks with Python Playwright and a Chromium installation:

```sh
CHROMIUM_EXECUTABLE=/usr/bin/chromium python website/test-hero.py
```

These checks are browser fixture evidence, not a live CDN byte-readback, native macOS test, physical iPhone test or real ChatGPT upload verification. GitHub Pages deployment status must be checked separately after the commit is published.
