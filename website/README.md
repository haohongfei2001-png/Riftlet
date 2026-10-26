# Riftlet website — first prelaunch candidate

Date: 2026-10-27. Status: **design preview / not a released product**.

## Purpose

A self-contained, static editorial landing page built around the product's priority: **spatial memory > content outline > labels**. It shows three small screenshots held at a consistent screen edge and demonstrates simulated one-click insertion into an unsent chat draft.

The site can be hosted without a server build, database, login, form handler, analytics, or external fonts. Root assets: `index.html`, `site.css`, `site.js`, `favicon.svg`, `site.webmanifest`, `robots.txt`, `sitemap.xml`, `CNAME`, `.nojekyll`.

## Visual choices — not final brand approval

Near-white `#F7F8F4`, ink `#26312D`, teal `#19B7A4`, interaction teal `#087C70`, pale teal `#D6EBE1`, and apricot `#F1CDB5`. The page takes direction from the archived 2026-10-26 exploration without freezing that exploration as approved Logo or UI.

All screenshot art is synthetic SVG drawn in source. The R-like mark is a temporary design study, **not the approved app icon**. Fonts come from local system stacks and may render differently across systems.

## Honest status

- Riftlet app **not yet released**. No actual download buttons are shown.
- ChatGPT integration, system screenshot capture, per-file READY evidence, Windows support, clipboard history, and other targets are **not demonstrated** by this website.
- The demo is browser-local; it cannot read the system screenshot folder, clipboard, or real chat. It never sends messages or performs network requests.
- READY / FAILED / UNKNOWN are simulated. UNKNOWN retains the item; simulated READY alone removes it from the pending edge. Previously typed draft text is left unchanged by simulated attachment insertion.
- Normal preview starts with three samples; new samples may be added and the demo reset. This is not a shipped product UI specification.

## Deployment via GitHub Pages (no Vercel/Cloudflare)

1. In the `Riftlet` repository, open **Settings → Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**, branch **main**, folder **/(root)**, then Save.
3. In **Custom domain**, add `riftlet.com` and Save (verify the domain on GitHub beforehand where available).
4. At the Tencent Cloud DNS provider, add GitHub Pages apex A records according to [current GitHub documentation](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site). Configure `www` only if desired, using the official CNAME target and avoiding wildcard records.
5. After DNS is valid, enable **Enforce HTTPS** in GitHub Pages settings and verify the actual public content.

The `CNAME` file is provided as the intended branch-source domain, but **it does not by itself activate Pages, update DNS, or prove deployment success**.

## Verification performed / not performed

Performed offline: HTML parse, unique IDs, linked asset existence, CSS top-level token parse, JavaScript syntax parse, translation key coverage, and static project scope review.

**Not performed**: Chromium/Playwright GUI checks. The execution environment blocked both local HTTP and file URL navigation with `ERR_BLOCKED_BY_ADMINISTRATOR`. Do not treat static validation as browser/visual acceptance. Once Pages is enabled, test 1440×900 and 390×844, actual demo click states, existing draft preservation, keyboard focus, reduced motion, and overflow.

Sources: [Riftlet product specification](../docs/PRODUCT.md), [visual exploration archive](../design/explorations/art-direction-2026-10-26/README.md).
