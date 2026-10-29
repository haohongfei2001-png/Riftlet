#!/usr/bin/env python3
"""Build the offline design prototype; no dependencies or network."""
from pathlib import Path
import re, hashlib, json
root=Path(__file__).resolve().parent
html=(root/'index.html').read_text()
for name in ['app.css','windows.css']:
    html=html.replace(f'<link rel="stylesheet" href="{name}">','<style>\n'+(root/name).read_text()+'\n</style>')
for name in ['model.js','windows.js','app.js']:
    html=html.replace(f'<script src="{name}"></script>','<script>\n'+(root/name).read_text().replace('</script','<\\/script')+'\n</script>')
out=root/'dist';out.mkdir(exist_ok=True)
(out/'index.html').write_text(html)
(root.parent/'Riftlet-Product-Prototype.html').write_text(html)
manifest={'title':'Riftlet · 薄界 · 完整产品设计原型','status':'recommended-design-not-native-implementation','base':'1920e0562db893a3292af89a89270a26ddb46a5f','network':'none','data':'synthetic-in-memory-only','file':'Riftlet-Product-Prototype.html','bytes':len(html.encode()),'sha256':hashlib.sha256(html.encode()).hexdigest(),'sourceFiles':{n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in ['index.html','app.css','windows.css','model.js','windows.js','app.js']}}
(root/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
