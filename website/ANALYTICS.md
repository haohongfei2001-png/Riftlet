# Riftlet website analytics / 官网访问与下载统计

## Status

The code is integrated but **disabled until the owner supplies an actual Umami Cloud website ID**. The empty `<meta name="riftlet-umami-website-id" content="">` in root `index.html` is intentional. Never invent a site ID or register an analytics service under someone else's account.

## Activate (one-time account action)

1. Sign in to https://cloud.umami.is/ (Hobby/free as available), create a website named `Riftlet` with domain `riftlet.com`, and obtain the public `data-website-id` UUID from the website's Tracking code. No API token, login password, or private key is needed in this repository.
2. In `index.html`, set **only** `<meta name="riftlet-umami-website-id" content="THE_PUBLIC_UUID">` to the actual Umami site ID, via a reviewed website PR. Do not paste an entire tracking snippet in addition to the bootstrap; that would double-track pageviews.
3. The production-domain-only bootstrap in `website-analytics.js` loads `https://cloud.umami.is/script.js` with that ID, automatic pageviews, `data-domains` and Do Not Track. If the ID is absent/invalid or the host is not riftlet.com/www.riftlet.com, no analytics script or network request is sent. It never accesses page input contents.
4. Test on the real domain after GitHub Pages deploys; visit once and confirm an Umami pageview. Click the top and main download links with the browser developer console/network panel open and check events `download_dmg` with `placement=header` / `primary` and `version=1.0.0`. Events can be blocked by privacy tools and may not always be sent before external navigation.
5. Check the public [privacy statement](../docs/consumer/PRIVACY.md) before enabling. Existing download links and synthetic interactive demo must continue working with ad blockers and JavaScript disabled.

## Reporting and attribution

- **Visitors / views / sources / campaigns**: Umami Cloud dashboard. Visitors are estimated; no login or permanent person-level identifier exists.
- **Download link intent**: Umami event `download_dmg`, with `placement` and `version`. The two official DMG anchors share the same event name with distinct placements, so the event's total can be filtered and split.
- **DMG network downloads**: Public GitHub Releases asset `download_count` from `GET https://api.github.com/repos/haohongfei2001-png/Riftlet/releases`. This includes direct release downloads and release validations; it does **not** equal unique people or installs. These public API counters also contain activity before Umami activation, but cannot be retroactively attributed to campaigns.
- **Actual installs / active app users**: not tracked. Do not claim them from download events or download_count.

UTM launch link examples:
- X: `https://riftlet.com/?utm_source=x&utm_medium=social&utm_campaign=launch`
- Reddit: `https://riftlet.com/?utm_source=reddit&utm_medium=social&utm_campaign=launch`

Umami normally collects UTM parameters from the page URL; do not strip query parameters. No extra redirect service or click-intercepting code is used.

## Privacy and QA

No cookies, account identifiers, screenshot data, clipboard contents, chat messages, form values, persistent user identifiers, or browser fingerprinting are added by this site's code. The provider may process basic connection metadata. The bootstrap respects DNT/GPC where exposed, and skips if `localStorage.setItem('umami.disabled', '1')` has been executed in that browser. It performs no extra storage writes. **This flag excludes only that browser/profile**, not every computer the maintainer uses.

Run `node --test website/test-analytics.cjs`. Tests verify no tracker without ID, valid/invalid IDs, production origin gating, DNT/GPC/opt-out, single loader and exactly two original DMG anchors retaining their link URLs. Browser/Umami cloud receipt tests require the real site ID and cannot be simulated as live analytics.
