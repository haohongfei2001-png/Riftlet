# Original art-direction restoration receipt

User request: “没有很好的展现设计图，就是我让你写入的那个图，尝试还原一下”.

Baseline commit: `5a3ab5d7a761d5397f8bc15b6f40d761b29e58d2`.
Original reference: `design/explorations/art-direction-2026-10-26/Riftlet_Art_Direction.html` (Git blob `900d0b13f076aae9fd2e2d00c32f5984aa4ee796`) and the accompanying supplied 1440 × 1000 preview.

## Exact output identifiers

- Restored `index.html`: Git blob `33024b9d071ed517353ad604dd086018fddf46d4`.
- `website-locale.js`: Git blob `451ab3500e55129f4ccedf4de7ec3d818d09ea85`.
- The uploaded blob IDs were compared with hashes of the locally checked files before updating main.

## Preservation checks

- Original SVG symbol library: byte-identical.
- Hero artwork DOM: identical.
- Original inline demo JavaScript: byte-identical.
- CSS: all original declarations and media queries retained. The sole formatting difference splits `.principle p` colour into an immediately adjacent identical-selector rule; normalizing that grouping gives byte-identical CSS.
- Changes outside those areas: publication metadata, honest prelaunch notices, development link, footer locale control, matching favicon.

## Checks actually run

HTML/anchor/ID checks; stylesheet parsing; Node syntax checks. Node VM tests with a minimal DOM stand-in covered one-shot duplicate-click suppression, readiness-based consumption, pointer-held positions followed by compaction, preserved draft text, definitive failure and manual retry, unknown-state no-replay, three-item serial queue, and stale-generation cancellation after reset. A separate pure-function check covered static and dynamic translation strings (73 static entries).

These are not real-browser tests. Local Chromium navigation was blocked by an administrator policy (`ERR_BLOCKED_BY_ADMINISTRATOR`), and it was not bypassed. No screenshot of the restored live page or real Mac/Windows runtime evidence was produced. Font differences between local system stacks remain possible.

## Scope

No DNS or Pages-setting changes. No modification of `design/explorations/**`, product specifications, technical research, client code or other projects. No private screenshots, credentials, personal chats, font files, analytics or paid services added.
