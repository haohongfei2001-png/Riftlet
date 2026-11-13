# Riftlet website analytics / 官网访问与下载统计

## Status / 启用状态

The owner configured Umami Cloud for `riftlet.com` on 2026-11-14.
Public Umami site ID: `ad8d2189-7065-43cc-b23a-01598375b84b` (not a secret).
The production HTML carries the ID once, and `website-analytics.js` loads the official hosted tracker only on the HTTPS production domain. No additional tracking snippet is included. The first reliable statistics begin **after the website deploys**; no historical pageviews can be recovered.

## Metrics / 指标

- **Visitors, views, referrers and UTM campaigns**: https://cloud.umami.is/ → Riftlet website dashboard, under the owner's account. Visitors are estimates, not identifiable users.
- **Download click events**: Umami `download_dmg` with properties `placement=header` or `placement=primary`, and `version=1.0.1`. Event properties are strings; the two hyperlinks still point directly to the unchanged official DMG file.
- **Actual GitHub release requests**: `download_count` of the corresponding `.dmg` asset at https://github.com/haohongfei2001-png/Riftlet/releases. GitHub requests include local and repeated verification downloads; they do not equal unique users, successful installations or active users.
- **App installs, activation and retention**: not measured; do not infer any of these values from website downloads.

Sample UTM promotion links:

- X: `https://riftlet.com/?utm_source=x&utm_medium=social&utm_campaign=launch`
- Reddit: `https://riftlet.com/?utm_source=reddit&utm_medium=social&utm_campaign=launch`

## Verification

1. Run `node --test website/test-analytics.cjs`; it tests disabled/untrusted hosts and storage, DNT/GPC, one official tracker and both original DMG links.
2. On the published HTTPS site, inspect `<meta name="riftlet-umami-website-id">`: it must equal the configured public ID exactly once. The bootstrap should request `https://cloud.umami.is/script.js` exactly once on first load if tracking is allowed.
3. In the Umami Cloud dashboard, verify the pageview appears. Click each download link and check the `download_dmg` event has the correct `placement`. Events can be blocked by browser privacy tools or lost during fast cross-site navigation; do not claim every click is captured.
4. Compare live HTML and JS to reviewed GitHub Pages deployed source. Check site and downloads with JavaScript blocked, and the existing synthetic demo with JavaScript enabled.
5. Exclude developer testing in an individual browser/profile with `localStorage.setItem('umami.disabled', '1')` then refresh. This does not exclude the developer on other devices or private windows.

## Privacy and scope

No screenshot, file contents, clipboard, chat text, app installation status, email, account ID, persistent user ID, cookie or browser fingerprint is added by Riftlet's site code. Umami and underlying infrastructure may process connection metadata. The script respects available DNT/GPC and locally chosen opt-out and does not run off the production HTTPS domains. Umami is independent of the native Mac App. See `docs/consumer/PRIVACY.md`.

If the Umami service is unavailable, the existing download links continue to work. Keep GitHub Releases as the canonical source of DMG download request counts.
