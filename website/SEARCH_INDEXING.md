# Riftlet search discovery / 搜索发现

Official website: https://riftlet.com/
Canonical and sitemap: https://riftlet.com/sitemap.xml
Public IndexNow host key: https://riftlet.com/bf099d245e4947c8908a2d8f6d5e5994.txt
IndexNow key (public): `bf099d245e4947c8908a2d8f6d5e5994`

## Automated website preparation
- `robots.txt` permits crawling and references the canonical sitemap
- The sitemap points to exactly the HTTPS homepage and contains `lastmod=2026-11-14`
- Home page title and JSON-LD explicitly identify the Mac screenshot-to-ChatGPT product, avoiding conflation with similarly spelled AI context tools
- Root GitHub README links to the canonical domain

## First notification and updates

After deploying the public key file, make one real HTTPS request to:

```text
https://api.indexnow.org/indexnow?url=https%3A%2F%2Friftlet.com%2F&key=bf099d245e4947c8908a2d8f6d5e5994&keyLocation=https%3A%2F%2Friftlet.com%2Fbf099d245e4947c8908a2d8f6d5e5994.txt
```

A `200` or `202` response means submitted or accepted for processing by participating engines; it **does not prove crawling or indexing**. Record the actual result separately. Do not repeatedly submit unchanged pages. For future significant homepage changes, reuse this key and submit only after Pages successfully deploys the changed URL.

Google's general Search Console indexing remains **separate**. Google no longer accepts anonymous sitemap ping submissions; request indexing / submit sitemap via an authenticated, verified Search Console property. If owner identity verification is unavailable, do not invent a Google verification token or claim success.

## Google / Bing manual verification once the respective account is authorized

- Google Search Console: `URL Inspection → https://riftlet.com/ → Test Live URL → Request Indexing`, then `Sitemaps → sitemap.xml`
- Bing Webmaster Tools: validate site ownership (IndexNow key may be separately verified); inspect the URL and submitted IndexNow notifications
- Use Google/Bing `site:riftlet.com` searches as a weak public observation, not proof of all index states
