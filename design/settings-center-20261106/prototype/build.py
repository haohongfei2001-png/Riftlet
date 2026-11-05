"""Build the dependency-free design prototype from inherited primitives and the supplement."""
from pathlib import Path
import hashlib,json

root=Path(__file__).resolve().parent
helpers=(root/'inherited-helpers.js').read_text()
app=(root/'app.js').read_text()
css=(root/'style.css').read_text()
js="(function(){\n'use strict';\n"+helpers+'\n'+app+'\n})();\n'
(root/'bundle.js').write_text(js)
html='<!doctype html>\n<html lang="zh-CN">\n<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><title>Riftlet · 设置与控制中心</title>\n<style>\n'+css+'\n</style></head>\n<body><div id="riftlet-design"></div><script>\n'+js+'\n</script></body>\n</html>\n'
output=root.parent/'Riftlet-Settings-Prototype.html'
output.write_text(html)
names=['inherited-helpers.js','style.css','app.js','index.html','build.py','bundle.js']
manifest={'schema':'riftlet-settings-prototype-build-v1','base':'b61fc46cf931bdbd14deec1b47d077e92db61e16','directlyInherited':'design/final-system-20261028/prototype/windows.js helper range: escape through frame','supplement':'six settings pages, control center, onboarding, dark mode and memory-state interactions','files':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names},'output':{'path':output.name,'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}}
(root/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest['output'],ensure_ascii=False))
