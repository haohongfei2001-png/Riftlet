# Riftlet website

The official public homepage is served at https://riftlet.com/ from the repository root on `main` through the existing GitHub Pages branch-source deployment.

## Current site state

- **Design baseline:** 2026-10-30 v2. The approved typography, composition, palette, artwork, responsive layout and interaction remain the active design.
- **Latest content update:** 2026-11-14. The bilingual homepage and installation dialog identify Riftlet 1.0.1, with direct links to its versioned disk image and release notes.
- **Website source marker:** `riftlet-1.0.1` in the `riftlet-website-version` meta tag.

The 2026-10-30 design release record remains historical and documents the original v2 publication. It is not the current native-app release status.

## Active files

- `index.html`: Chinese/English product homepage, current SEO/Open Graph/Twitter metadata, release links and synthetic interaction demo.
- `website-v2.css`: approved responsive layout, local font definitions and reduced-motion styles.
- `website-v2.js`: synthetic capture, edge queue, draft attachments, scenes, locale and release dialog.
- `website-assets/`: approved artwork, logo, precise example SVGs, local fonts, OFL licenses and font source records.
- `site.webmanifest`: existing browser manifest.
- `favicon.svg`, `robots.txt`, `sitemap.xml`, `CNAME` and `.nojekyll`: retained production files.

Old `site.*`, `website-product.*`, `website-hero.*` and `website-locale.js` files are retained for history and are not loaded by the current homepage. Older `website/test-*` scripts target those historical implementations; they are not the v2 acceptance gate.

## Native product availability and support boundary

**Riftlet 1.0.1** is available from the homepage as `Riftlet-1.0.1.dmg`. The universal Mac package supports macOS 13 or later on Apple silicon and Intel. The current one-click attachment target is an editable ChatGPT draft in Google Chrome. A standard macOS user can install it in the Applications folder under their home directory. Users of 1.0.0 replace their app once using the disk image. Starting with 1.0.1, Riftlet checks daily by default and asks before installing. The menu bar also offers Check for Updates (检查更新…). Other browsers, the ChatGPT desktop app and read-only drafts are unsupported.

The website's interactive demo is separate from the native app. It does not expand native support or claim real ChatGPT upload acceptance. Refer to the current [consumer support matrix](../docs/consumer/SUPPORT-MATRIX.md), [installation and permissions guide](../docs/consumer/INSTALL-AND-PERMISSIONS.md), and [release notes](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.1) for the authoritative product details.

## Demo boundaries

The demo uses synthetic content only. It does not read the screen, clipboard or conversations, call external APIs, upload images, send messages or persist text. Deliberate GitHub links open the public project. Local static font and image requests are the only resources needed to render the page.

The illustrated handoff separates simulated upload-start evidence from final attachment readiness. A thumbnail clears after the synthetic positive start, while readiness arrives later. This is an illustration, not proof of native timing or failure handling. Existing draft text and the original example attachment are preserved. Empty queues hide the edge. The demo never sends a message.

## Deployment and rollback

Keep GitHub Pages on `main`, repository root, custom domain `riftlet.com`. Do not add a new hosting service or alter DNS to publish this static page. A website commit triggers the existing Pages build and deployment.

Publish the verified, immutable GitHub release before merging the reviewed homepage links and signed stable feed into main together. If distribution needs to be suspended, update the links in a new reviewed commit and preserve the original release artifact.

## Verification

Check the two download links, installation dialog, permissions FAQ, one-time upgrade from 1.0.0, in-app update instructions, feedback link and privacy contact in both languages. Check the static download links with JavaScript disabled. Verify the deployed `riftlet-website-version` marker, follow a link from the live homepage, then compare the downloaded file against the independently recorded SHA-256.

See [RELEASE_2026-10-30.md](RELEASE_2026-10-30.md) for the original v2 design release scope and asset provenance.
