"""Reproducible, credential-free source and standalone HTML package."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
root = Path(__file__).resolve().parent
paths = [root/'README.md', root/'build.mjs', root/'package-source.py']
paths += sorted((root/'src').glob('*'))
paths += sorted((root/'docs').glob('*.md'))
paths += sorted((root/'qa').glob('*.md')) + sorted((root/'qa').glob('*.cjs')) + sorted((root/'qa').glob('*.jpg'))
paths += [root/'dist/index.html']
output = root/'dist/Riftlet-Interactive-v1-Source.zip'
with ZipFile(output, 'w', ZIP_DEFLATED, compresslevel=9) as z:
    for p in paths:
        name = p.relative_to(root).as_posix()
        entry = ZipInfo(name, (2026, 10, 27, 0, 0, 0))
        entry.compress_type = ZIP_DEFLATED
        entry.external_attr = 0o644 << 16
        z.writestr(entry,p.read_bytes())
    standalone = ZipInfo('Riftlet-Interactive-v1.html', (2026, 10, 27, 0, 0, 0))
    standalone.compress_type = ZIP_DEFLATED
    standalone.external_attr = 0o644 << 16
    z.writestr(standalone,(root/'dist/index.html').read_bytes())
print(str(output))
