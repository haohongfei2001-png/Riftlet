# Riftlet website

The public homepage is a product website, not a design report. This revision follows the user's explicit request to use the teal rounded-square R icon and remove palette/identity research from the live site.

## Active files

- `index.html`: product introduction, interactive demo, principles and release status.
- `website-product.css`: archived first-screen composition plus product-page layout and responsive rules.
- `website-product.js`: Chinese/English copy and browser-local synthetic demonstration.
- `favicon.svg`: the user-selected teal square and original split-R geometry, used in navigation, release block and footer.
- `site.webmanifest`: the same brand icon.

The previous `site.css`, `site.js` and `website-locale.js` are not loaded by the current page. They are retained to avoid unrelated deletion. Original design studies under `design/` remain unchanged.

## Product honesty

The homepage is the official public product page. The desktop application is not offered for download by this page. macOS is the first planned release; clipboard, Windows and more targets are future directions, not shipped functionality.

The demonstration uses synthetic SVG artwork only. It never reads the visitor's screenshots, clipboard or chats, performs file uploads, or sends messages. It appends to a local demo draft. Unknown outcomes retain the item and do not re-dispatch. Reset and language switching preserve visitor-entered draft text. Nothing is stored beyond the page session.

## Deployment

Existing GitHub Pages branch-source deployment remains unchanged: `main`, repository root, custom domain `riftlet.com`. No hosting, DNS, CNAME or deployment-workflow configuration is modified by this revision.

## Verification

Run `node --check website-product.js` and `node website/test-product.cjs`.

The test suite uses a small DOM double with controlled timers. It verifies 11 scenarios, including pending/ready separation, duplicate-click suppression, serial ordering, failure/retry, unknown preservation, stale completion after reset, pointer-slot stability, locale/draft preservation and attachment removal. These are unit tests, not browser rendering or real-platform evidence.

Static checks cover HTML IDs, anchor targets, local asset existence, stylesheet syntax, script syntax, manifest JSON, absence of public design-report sections, and exact source-SVG geometry.

Real Chromium navigation was blocked by the environment (`ERR_BLOCKED_BY_ADMINISTRATOR`). No policy was changed and no bypass was attempted. Desktop/mobile pixel-level rendering and a fresh public-site interaction check remain unverified in this environment. Responsive rules and local font stacks are inherited from the original composition; fonts may differ across systems.

