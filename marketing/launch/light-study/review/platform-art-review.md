# Social artwork · 2026-11-14

The five exports in `../platforms/` cover five destinations. X and Reddit share one dark landscape composition. The Product Hunt application icon retains the official SVG outline and colors with transparent corners. The campaign plate in the Chinese portrait is an AI-generated glass study. Its corner marks are a design treatment.

| Export | Delivered pixels | Visible content and editorial use |
| --- | --- | --- |
| `product-hunt-gallery.jpg` | 1270 × 760 | Cream landscape, official lockup, still-life study and a native two-thumbnail screenshot tray. The copy identifies the Chrome ChatGPT draft. |
| `product-hunt-icon.png` | 240 × 240 | Official jade-and-ink Riftlet mark, rasterized from the repository SVG at sixfold resolution. |
| `x-reddit-card.jpg` | 1600 × 900 | Dark glass, a grazing diagonal highlight, four editorial crop corners and a compact English introduction. |
| `xiaohongshu-cover.jpg` | 1080 × 1440 | Chinese Songti headline, “截下一束光。”, full-bleed glass detail, and one sentence naming the Chrome draft. |
| `bilibili-cover.jpg` | 1200 × 900 | Native two-image tray, a detail of the first thumbnail, and the public build number. |

## Pixel provenance

`../originals/native-tray-film-still.png` is frame index 294 (zero indexed, 9.800 s at 30 fps) from the 720-frame white-listed native tray movie. Its original QuickTime source has SHA-256 `9860c1cc99d745e102294b7cb6b51b278d1630e85334351d2a053e85af908aeb`. Decode with `ffmpeg -i tray-native.mov -vf 'select=eq(n\,294)' -frames:v 1 native-tray-film-still.png`. This output is RGB 652 × 608 with SHA-256 `1587dd7bb2c9ef9c34ec579480bf781c18f3192f7acd0da8eb838dc478e6b16f`. A byte-identical frame appeared at index 175 in an earlier take. Public Beta build 20 provided the real tray in the isolated native review session. Both original tide images and camera key appear as recorded. These pixels document the local tray only.

The campaign plates are `../originals/wedge.png` and `../originals/grazing-light.png`. The Illustrator-style crop marks are drawn by the artwork script. The official mark and OFL-licensed Instrument Serif are read directly from `website-assets/`. Helvetica Neue, Songti SC, and PingFang SC render on macOS; the output carries rasterized text. No system font is redistributed.

## Rebuild and inspection

From the repository root on macOS with Pillow, fonttools and Brotli installed, run `python3 marketing/launch/light-study/studio/platforms.py`. Each file embeds an sRGB profile. All five outputs were decoded and visually opened individually at their exported dimensions, with extra small-scale review. Revised the dark landscape for mobile contrast and replaced an unrelated glass inset in the Bilibili layout with a matching low-tide thumbnail detail. Verified Chinese characters, crop marks and corner transparency. Rebuilt the entire five-file set to a second directory and compared all bytes. No platform upload or feed rendering was performed.
