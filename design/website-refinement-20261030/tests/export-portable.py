"""Export the modular candidates as self-contained pages. No network access."""
from pathlib import Path
from bs4 import BeautifulSoup
import base64
ROOT=Path(__file__).resolve().parents[1]
for variant in ('A','B'):
    source=ROOT/f'{variant}.html'
    doc=BeautifulSoup(source.read_text(encoding='utf-8'),'html.parser')
    doc.body['class']=['candidate-'+variant.lower()]
    for tag in doc.select('link[rel=stylesheet]'):
        style=doc.new_tag('style')
        style.string=(ROOT/tag['href'].split('?')[0]).read_text(encoding='utf-8')
        tag.replace_with(style)
    for tag in doc.select('script[src]'):
        script=doc.new_tag('script')
        script.string=(ROOT/tag['src']).read_text(encoding='utf-8')
        tag.decompose();doc.body.append(script)
    for tag in doc.select('img[src]'):
        path=ROOT/tag['src'].split('?')[0]
        tag['src']='data:image/svg+xml;base64,'+base64.b64encode(path.read_bytes()).decode()
    for tag in doc.select('link[rel=icon],link[rel=manifest]'):
        tag.decompose()
    output=ROOT/f'Riftlet-{variant}.html'
    output.write_text(str(doc),encoding='utf-8')
    print(output.name,output.stat().st_size)
