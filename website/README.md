# Riftlet website

> **Review branch — 2026-10-30 refinement:** this branch uses `website-v3.css` and the updated `website-v2.js`. It is an isolated candidate; the live website remains the approved V2 described below. See [the refinement review](REFINEMENT_2026-10-30.md).

The official public homepage is served at https://riftlet.com/ from the repository root on `main` through the existing GitHub Pages branch-source deployment.

## Current version: 2026-10-30 v2

The owner explicitly approved the second design and authorized publication. This release retains the approved typography, composition, color, artwork and interaction. Production preparation only changes asset paths, removes the design-preview footer label and restores public-page metadata.

### Active files

- `index.html`: Chinese/English product homepage and synthetic interaction demo.
- `website-v2.css`: approved responsive layout, local font definitions and reduced-motion styles.
- `website-v2.js`: synthetic capture, edge queue, draft attachments, scenes, locale and release dialog.
- `website-assets/`: approved artwork, logo, precise example SVGs, local fonts, OFL licenses and font source records.
- `site.webmanifest`: existing browser manifest, with the page background/theme colors updated.
- `favicon.svg`, `robots.txt`, `sitemap.xml`, `CNAME` and `.nojekyll`: retained existing production files.

Old `site.*`, `website-product.*`, `website-hero.*` and `website-locale.js` files are retained for history and are not loaded by the current homepage. Older `website/test-*` scripts target those historical implementations; they are not the v2 acceptance gate.

## Product and demo boundaries

The website is public; the native Mac app remains in private testing with no public download offered. Current testing focuses on ChatGPT in Chrome. This website does not expand native support or claim real-upload acceptance.

The demo uses synthetic content only. It does not read the screen, clipboard or conversations, call external APIs, upload images, send messages or persist text. Deliberate GitHub links open the public project. Local static font and image requests are the only resources needed to render the page.

The illustrated handoff separates simulated upload-start evidence from final attachment readiness. A thumbnail clears after the synthetic positive start, while readiness arrives later. This is an illustration, not proof of native timing or failure handling. Existing draft text and the original example attachment are preserved. Empty queues hide the edge. The demo never sends a message.

## Deployment and rollback

Keep GitHub Pages on `main`, repository root, custom domain `riftlet.com`. Do not add a new hosting service or alter DNS to publish this static page. A website commit triggers the existing Pages build and deployment.

A rollback can restore only this release's changed paths from the pre-release base `eba1a4fc77648a665e1d5c1f2609df1314c3b079` in a new commit. Do not force-reset unrelated work or merge the native product branch to publish the website.

## Verification

Run `node --check website-v2.js`. Static validation covers duplicate IDs, anchor targets, local image/script/style/font references, JSON and SVG parsing. Browser QA of the approved design covered desktop and 390/768 CSS-pixel responsive documents, font loading, Chinese/English switching, capture/attach/replay, scene switching, draft preservation, empty-edge behavior, FAQ and the release dialog.

Production validation must check a successful Pages deployment for the published commit and the actual domain's new version marker and asset responses. The earlier browser QA was not physical-device, Safari, VoiceOver, native Mac app or real ChatGPT upload acceptance.

See `RELEASE_2026-10-30.md` for this release's scope and asset provenance.
