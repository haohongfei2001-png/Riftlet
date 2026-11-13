# Riftlet website

The official public homepage is served at https://riftlet.com/ from the repository root on `main` through the existing GitHub Pages branch-source deployment.

## Current site state

- **Design baseline:** 2026-10-30 v2. The approved typography, composition, palette, artwork, responsive layout and interaction remain the active design.
- **Latest content update:** 2026-11-14. The homepage title, search/social metadata, supported-platform summary, one FAQ label and footer legal line were updated. No layout, artwork, stylesheet, demo logic, download destination, hosting or DNS changes were made.
- **Website source marker:** `2026-11-14-v2.1` in the `riftlet-website-version` meta tag.

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

Riftlet **0.3.5 (20) Public Beta** is publicly downloadable from the homepage. The universal Mac package supports macOS 13 or later on Apple silicon and Intel. The current one-click attachment target is an editable ChatGPT draft in Google Chrome. Other browsers, the ChatGPT desktop app and read-only chats are outside this Beta scope. Updates are manual. First use on a non-administrator account has not been fully verified.

The website's interactive demo is separate from the native app. It does not expand native support or claim real ChatGPT upload acceptance. Refer to the current [consumer support matrix](../docs/consumer/SUPPORT-MATRIX.md), [installation and permissions guide](../docs/consumer/INSTALL-AND-PERMISSIONS.md), and [release notes](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1) for the authoritative product details.

## Demo boundaries

The demo uses synthetic content only. It does not read the screen, clipboard or conversations, call external APIs, upload images, send messages or persist text. Deliberate GitHub links open the public project. Local static font and image requests are the only resources needed to render the page.

The illustrated handoff separates simulated upload-start evidence from final attachment readiness. A thumbnail clears after the synthetic positive start, while readiness arrives later. This is an illustration, not proof of native timing or failure handling. Existing draft text and the original example attachment are preserved. Empty queues hide the edge. The demo never sends a message.

## Deployment and rollback

Keep GitHub Pages on `main`, repository root, custom domain `riftlet.com`. Do not add a new hosting service or alter DNS to publish this static page. A website commit triggers the existing Pages build and deployment.

The 2026-11-14 update changes only `index.html` and this README; it does not change `website-v2.css`, `website-v2.js`, artwork, fonts, `CNAME`, DNS or Pages configuration. If rollback is needed, revert only the specific content commit in a new commit after checking the current mainline. Do not force-reset unrelated work or merge the native product branch to publish the website.

## Verification

The approved v2 design's browser QA covered desktop and 390/768 CSS-pixel responsive documents, font loading, Chinese/English switching, capture/attach/replay, scene switching, draft preservation, empty-edge behavior, FAQ and the release dialog. This historical QA was not physical-device, Safari, VoiceOver, native Mac app or real ChatGPT upload acceptance.

The 2026-11-14 content-only update was checked for:
- Chinese SEO description and page title;
- Open Graph and Twitter title/description;
- Chinese/English FAQ label consistency;
- balanced FAQ disclosure tags;
- removal of the requested footer line;
- preservation of the existing Public Beta DMG URL and primary demo action.

The Pages deployment for the content commit must complete successfully before considering the live site updated. Verify the live domain's `riftlet-website-version` marker and current metadata after deployment.

See [RELEASE_2026-10-30.md](RELEASE_2026-10-30.md) for the original v2 design release scope and asset provenance.
