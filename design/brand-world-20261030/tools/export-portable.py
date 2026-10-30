"""Export offline, self-contained website pages and a bilingual review experience."""
from pathlib import Path
import base64, json, mimetypes, re

ROOT=Path(__file__).resolve().parents[1]
SITE=ROOT/'site'
OUT=SITE/'downloads'
OUT.mkdir(exist_ok=True)

def data_uri(path):
    mime=mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
    return 'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()

def local_path(base,ref):
    if ref.startswith(('http:','https:','data:','#','mailto:')): return None
    p=(base/ref.split('?')[0]).resolve()
    if p.is_file() and p.is_relative_to(ROOT): return p
    return None

def embed_images(html,base):
    def img(m):
        p=local_path(base,m[2])
        return m[1]+(data_uri(p) if p else m[2])+m[3]
    html=re.sub(r'(<img\b[^>]*\bsrc=")([^"]+)(")',img,html)
    def icon(m):
        tag=m[0]
        href=re.search(r'href="([^"]+)"',tag)
        if href:
            p=local_path(base,href[1])
            if p:tag=tag.replace(href[0],'href="'+data_uri(p)+'"')
        return tag
    html=re.sub(r'<link\b[^>]*rel="icon"[^>]*>',icon,html)
    html=re.sub(r'<link\b[^>]*rel="(?:manifest|alternate)"[^>]*>','',html)
    return html

def website(locale,embedded=False):
    file=SITE/('zh/index.html' if locale=='zh' else 'index.html')
    html=embed_images(file.read_text(),file.parent)
    html=re.sub(r'<link rel="stylesheet" href="([^"]+)">',lambda m:'<style>'+local_path(file.parent,m[1]).read_text()+'</style>',html)
    scripts=[]
    for match in re.finditer(r'<script src="([^"]+)"[^>]*></script>',html):
        p=local_path(file.parent,match[1]);code=p.read_text()
        if p.name=='website.js':
            new='var sample='+json.dumps({f'shot-{n}':data_uri(SITE/'assets'/f'sample-{shape}.svg') for n,shape in [(1,'landscape'),(2,'portrait'),(3,'wide')]})+';'
            code=re.sub(r"var sample=\{[^;]+;",lambda m:new,code,count=1)
        scripts.append('<script>'+code+'</script>')
    html=re.sub(r'<script src="[^"]+"[^>]*></script>','',html)
    html=re.sub(r'data-assets="[^"]*"','data-assets=""',html)
    other='en' if locale=='zh' else 'zh'
    for href in ['zh/index.html','../index.html']:
        html=html.replace('href="'+href+'"','href="'+('__riftlet_'+other+'__' if embedded else 'Riftlet-Website-'+other.upper()+'.html')+'"')
    for href in ['review.html','../review.html']:
        html=html.replace('href="'+href+'"','href="'+('__riftlet_review__' if embedded else 'Riftlet-Review.html')+'"')
    html=re.sub(r'<meta property="og:image"[^>]*>','',html)
    if embedded:
        scripts.append("<script>document.addEventListener('click',function(e){var a=e.target.closest('a');if(a&&/^__riftlet_(en|zh|review)__$/.test(a.getAttribute('href'))){e.preventDefault();parent.postMessage({riftletPreview:a.getAttribute('href')},'*');}});</script>")
    return html.replace('</body>',''.join(scripts)+'</body>')

for lang in ['en','zh']:
    (OUT/f'Riftlet-Website-{lang.upper()}.html').write_text(website(lang))

review=embed_images((SITE/'review.html').read_text(),SITE)
def review_link(m):
    href=m[2];p=local_path(SITE,href)
    if p and p.suffix in ['.svg','.png','.ico','.icns']:
        return m[1]+data_uri(p)+m[3]+' download="'+p.name+'"'
    if href=='baseline/index.html':href='https://github.com/haohongfei2001-png/Riftlet/blob/eba1a4fc77648a665e1d5c1f2609df1314c3b079/index.html'
    elif href=='review.html':href='#'
    elif href.startswith('og-preview.html'):return m[1]+data_uri(SITE/'assets'/'og-zh.png')+m[3]+' download="Riftlet-OG-ZH.png"'
    return m[1]+href+m[3]
review=re.sub(r'(<a\b[^>]*href=")([^"]+)(")',review_link,review)

overlay='''<div id="portable-view" hidden role="dialog" aria-modal="true" aria-label="Riftlet website preview"><div class="portable-toolbar"><button id="portable-close" type="button">← 返回品牌评审</button><div><button type="button" data-preview-lang="zh">中文</button><button type="button" data-preview-lang="en">English</button></div><label>画幅 <select id="portable-width"><option value="auto">自适应</option><option value="390">390</option><option value="768">768</option><option value="1024">1024</option></select></label><span>完整官网 · 本地模拟</span></div><div class="portable-frame-wrap"><iframe id="portable-frame" title="Riftlet 完整交互官网"></iframe></div></div>'''

style='''[hidden]{display:none!important}#portable-view{position:fixed;inset:0;z-index:1000;background:#dfe6db}.portable-toolbar{height:62px;padding:10px 25px;display:flex;gap:25px;align-items:center;background:#f4f1e8;border-bottom:1px solid #bccdbe;font:12px system-ui;color:#123e38}.portable-toolbar button,.portable-toolbar select{font:inherit;color:inherit;background:transparent;border:1px solid #b6cabd;border-radius:18px;padding:7px 12px}.portable-toolbar>span{margin-left:auto;font-size:11px}.portable-toolbar label{display:flex;align-items:center;gap:8px}.portable-frame-wrap{height:calc(100dvh - 62px);overflow:auto;display:flex;justify-content:center}#portable-frame{height:100%;width:100%;max-width:100%;border:0;background:#f4f1e8;flex-shrink:0}@media(max-width:600px){.portable-toolbar{gap:9px;padding:8px 10px;height:58px}.portable-toolbar>span,.portable-toolbar label{display:none}.portable-toolbar button{font-size:10px;padding:7px 9px}.portable-toolbar>div{margin-left:auto}.portable-frame-wrap{height:calc(100dvh - 58px)}}'''

data=json.dumps({lang:website(lang,True) for lang in ['en','zh']},ensure_ascii=False).replace('<','\\u003c')
script='''(function(){'use strict';var pages=JSON.parse(document.getElementById('portable-pages').textContent),view=document.getElementById('portable-view'),frame=document.getElementById('portable-frame'),width=document.getElementById('portable-width'),close=document.getElementById('portable-close'),review=document.querySelector('body>.wrap'),lastFocus=null;function open(lang,w,reduced){lastFocus=lastFocus||document.activeElement;view.hidden=false;review.inert=true;document.body.style.overflow='hidden';width.value=['390','768','1024'].includes(w)?w:'auto';frame.style.width=width.value==='auto'?'100%':width.value+'px';frame.srcdoc=reduced?pages[lang].replace('<body ','<body class="motion-off" '):pages[lang];close.focus();}function exit(){frame.srcdoc='';view.hidden=true;review.inert=false;document.body.style.overflow='';if(lastFocus)lastFocus.focus();lastFocus=null;}document.addEventListener('click',function(e){var a=e.target.closest('a');if(!a)return;var h=a.getAttribute('href');if(h==='index.html'||h==='zh/index.html'){e.preventDefault();open(h==='index.html'?'en':'zh');}else if(h&&h.startsWith('qa.html?')){e.preventDefault();var q=new URLSearchParams(h.split('?')[1]);open(q.get('locale')==='zh'?'zh':'en',q.get('width'),q.get('motion')==='reduced');}});document.querySelectorAll('[data-preview-lang]').forEach(function(b){b.addEventListener('click',function(){open(b.dataset.previewLang,width.value);});});close.addEventListener('click',exit);width.addEventListener('change',function(){frame.style.width=this.value==='auto'?'100%':this.value+'px';});document.addEventListener('keydown',function(e){if(e.key==='Escape'&&!view.hidden)exit();});window.addEventListener('message',function(e){if(e.source!==frame.contentWindow||!e.data)return;var m=e.data.riftletPreview;if(m==='__riftlet_review__')exit();else if(m==='__riftlet_en__'||m==='__riftlet_zh__')open(m==='__riftlet_en__'?'en':'zh',width.value);});})();'''

review=review.replace('</head>','<style>'+style+'</style></head>').replace('</body>',overlay+'<script type="application/json" id="portable-pages">'+data+'</script><script>'+script+'</script></body>')
(OUT/'Riftlet-Review.html').write_text(review)
for p in OUT.glob('*.html'):print(p.name,p.stat().st_size)
