#!/usr/bin/env python3
"""Export licensed DejaVu Sans glyphs as editable SVG paths; no font runtime needed."""
from pathlib import Path
import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

root = Path(__file__).resolve().parents[1]
out = root / 'brand'
font_path = Path(os.environ.get('RIFTLET_WORDMARK_FONT', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
font = TTFont(font_path)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
scale = 150 / font['head'].unitsPerEm
cursor = 12
parts = []
for i, ch in enumerate('Riftlet'):
    name = cmap[ord(ch)]
    pen = SVGPathPen(glyphs)
    transform = TransformPen(pen, (scale, 0, 0, -scale, cursor, 153))
    glyphs[name].draw(transform)
    parts.append(f'<path id="letter-{i}-{ch}" d="{pen.getCommands()}"/>')
    cursor += font['hmtx'][name][0] * scale - 3.2
width = round(cursor + 9, 3)
body = ''.join(parts)
svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="190" viewBox="0 0 {width} 190" role="img" aria-labelledby="title"><title id="title">Riftlet wordmark</title><metadata>Outlined DejaVu Sans. See FONT-LICENSE.txt. Optical tracking -3.2 at 150px.</metadata><g fill="#123E38">{body}</g></svg>\n'
(out / 'wordmark.svg').write_text(svg)
(out / 'wordmark-light.svg').write_text(svg.replace('fill="#123E38"', 'fill="#F4F1E8"'))
license_path = Path('/usr/share/doc/fonts-dejavu-core/copyright')
if license_path.exists():
    license_text = license_path.read_text().split('Files: debian/*')[0].strip()
    (out / 'FONT-LICENSE.txt').write_text('Riftlet wordmark glyph source: DejaVu Sans. Original font not bundled. Glyph outlines distributed under the following notice.\n\n' + license_text + '\n')
print(f'wordmark.svg: {width} × 190, seven independently editable glyph paths')
