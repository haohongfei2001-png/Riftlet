# Riftlet — Passage / 隙入

Design candidate, 2026-10-30. No adoption or production replacement is implied.

## Main assets

| File | Purpose |
|---|---|
| `mark.svg` | Regular one-color mark in forest ink, 256-unit viewBox |
| `mark-light.svg` | Warm white mark for dark backgrounds |
| `mark-mono.svg` | Pure black, transparent mark |
| `mark-small.svg` | Optical master for 16/32px; stronger edge and a wider opening |
| `menu-bar.svg`, `menu-bar-light.svg` | Transparent monochrome small master; no tile, shading or border |
| `wordmark.svg`, `wordmark-light.svg` | Seven independently editable outlined glyphs; no font load required |
| `lockup.svg`, `lockup-light.svg` | Main horizontal symbol + wordmark |
| `app-icon.svg` | Editable 1024×1024 master, mint tile and dark symbol |
| `app-icon-forest.svg` | Alternate dark tile and warm-white symbol |
| `app-icon-{16,32,64,128,256,512,1024}.png` | Raster exports from the vector, with optical source for 16/32 |
| `AppIcon.iconset/`, `app-icon.icns` | Prepared macOS icon files; real Dock integration has not been tested |
| `favicon.svg`, `favicon.ico` | Small optical symbol, mint container; ICO includes 16/32/48 |
| `direction-a.svg`, `direction-c.svg` | Editable reserve/eliminated candidate marks |
| `directions-board.svg`, `directions-board.png` | Comparison of three directions |
| `passage-preview.svg`, `passage-preview.png` | Main brand mark and App Icon presentation |
| `scale-check.png`, `scale-512.png` | Rendered scale evidence |

The matching `site/assets/mark.svg`, `mark-light.svg`, `app-icon.svg` and `favicon.svg` are generated from these same masters. Do not independently alter their geometry.

## The construction

The mark contains two named, editable paths: `content-plane` and `screen-edge`. The plane has a gently sloping upper edge, a long, almost vertical left edge, a restrained lower slope and a shallow concavity near the fixed right boundary. It is an abstraction of a passage, not a literal screenshot frame or an assertion that thumbnails distort at rest.

The first vector review showed that symmetric top/bottom slopes resembled a speaker at small sizes. The second revision lengthened the left edge and flattened the bottom. The boundary tips were rounded instead of retaining the generated concept's blade-like points. The final main master is intentionally different from the AI concept image: the editable geometry is the source of truth.

The mark is meant to gain meaning from the product demonstration: an image at a quiet edge, deliberately chosen by the user. It is not a pictographic promise that a viewer will infer the entire product from the isolated symbol.

## Color

| Token | Value | Role |
|---|---|---|
| Forest ink | `#123E38` | Main mark, type, dark sections |
| Mint | `#46D1B1` | Primary identity accent and App Icon tile |
| Warm paper | `#F4F1E8` | Light page and reversed mark |
| Sand | `#D7A482` | Sparing warm secondary accent |

Use the flat mark for navigation, documents and menus. Material effects belong only to the App Icon tile. Do not add glows, animated particles or an extra container around the menu-bar symbol. Do not recolor actual screenshots to match the brand.

## Spacing and size

- Keep the two paths in their fixed relationship. Never use the content plane or the screen edge alone as the primary logo.
- Preserve at least one edge-width of clear space outside the mark's visible bounds; more is preferable in large editorial layouts.
- Use the dedicated small master at 16/32px instead of shrinking the regular master.
- Check transparency and contrast against the real placement background. Use a reversed mark on dark surfaces.
- App Icon master has 72px external inset on a 1024px canvas, an 880px tile and an 8px restrained rim. The outside remains transparent.
- The prepared ICNS contains PNG-backed sizes. Finder/Dock appearance, macOS asset catalog integration and system template rendering remain adoption-stage checks.

## Wordmark and rights

The symbol paths and candidate compositions were constructed specifically for this project. The wordmark uses outlined DejaVu Sans glyphs, with explicit optical tracking; see `FONT-LICENSE.txt`. No font binary is bundled. The outline remains editable, and text labels elsewhere may use local system fonts.

Generated concept images are separate exploration material. They are not traced font sources or substitutes for these vector masters. No competitor visual assets are included. Preliminary visual review does not constitute trademark clearance.

## Reproduction

From the candidate root, run `tools/build-brand.cjs` with Node and `sharp` available through `NODE_PATH`. It invokes `tools/build-wordmark.py`, which requires Python `fontTools` and DejaVu Sans at the documented system path. `RIFTLET_WORDMARK_FONT` can point to the exact same licensed source font elsewhere. Preserve `FONT-LICENSE.txt`.

The generated SVGs, PNGs and ICO/ICNS can be used without Node, Python, fontTools or any network connection. Scripts are build-time tools only.

## Validation performed

Rendered and inspected actual 16, 32, 64, 128, 256, 512 and 1024 pixel exports, transparent monochrome small marks, the comparison board and the regular flat mark. The gap remains visible in the smallest optical version. The 16px version necessarily communicates the silhouette and two-part relationship; fine concavity is not a useful detail at that size.

This is a visual asset check, not a claim of real macOS Dock testing, legal clearance, commercial adoption or user recall testing.
