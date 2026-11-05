"""Build revision 2 independently. The first-version HTML and sources are read-only."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent
first_version = root.parent.parent / 'Riftlet-Settings-Prototype.html'
first_sha = 'aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf'
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert digest(first_version) == first_sha, 'First-version HTML must remain immutable'
subprocess.run(['node', '--check', str(root / 'app.js')], check=True)
helpers = (root / 'inherited-helpers.js').read_text()
app = (root / 'app.js').read_text()
css = (root / 'style.css').read_text()
js = "(function(){\n'use strict';\n" + helpers + '\n' + app + '\n})();\n'
(root / 'bundle.js').write_text(js)
html = ('<!doctype html>\n<html lang="zh-CN">\n<head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="light dark">'
        '<title>Riftlet · 设置与控制中心 · 修正版 2</title>\n<style>\n' + css +
        '\n</style></head>\n<body><div id="riftlet-design"></div><script>\n' + js +
        '\n</script></body>\n</html>\n')
output = root.parent / 'Riftlet-Settings-Prototype.html'
output.write_text(html)
names = ['inherited-helpers.js', 'style.css', 'app.js', 'index.html', 'build.py', 'bundle.js']
manifest = {
    'schema': 'riftlet-settings-prototype-build-v2',
    'baseMain': 'b61fc46cf931bdbd14deec1b47d077e92db61e16',
    'inheritedDesignCommit': '6372bcf3fbeb71cb7ad2d930cad18528e2d54796',
    'firstVersion': {'path': '../Riftlet-Settings-Prototype.html', 'sha256': first_sha},
    'scope': 'Synthetic design interaction corrections and limited visual refinements only',
    'files': {name: digest(root / name) for name in names},
    'output': {'path': output.name, 'bytes': output.stat().st_size, 'sha256': digest(output)},
}
(root / 'build-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
assert digest(first_version) == first_sha
print(json.dumps(manifest['output'], ensure_ascii=False))
