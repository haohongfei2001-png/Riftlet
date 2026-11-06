"""Build review assets and an offline prototype from the actual design sources.

No web requests and no generated replacement for native screenshots.
Run from any cwd. Optional --inline writes a conversation-only fragment.
"""
from pathlib import Path
from io import BytesIO
import argparse
import base64
import hashlib
import json
import re
import zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'prototype'
E = ROOT / 'evidence'
OUT = ROOT / 'exports'
OUT.mkdir(exist_ok=True)

def data_image(im, width=None):
    im = im.copy()
    if width:
        im = im.resize((round(width), round(im.height * width / im.width)), Image.Resampling.LANCZOS)
    b = BytesIO()
    im.save(b, 'WEBP', quality=90, method=6)
    return 'data:image/webp;base64,' + base64.b64encode(b.getvalue()).decode()

def native(name, trim=False):
    im = Image.open(E / 'native' / name)
    if trim:
        im = im.crop(im.getbbox())
    size = [im.width / 2, im.height / 2]
    return data_image(im, min(960, im.width / 2)), size

def after(name, size):
    im = Image.open(E / 'prototype' / name)
    return data_image(im, min(960, size[0])), size

sources = [
    ('settings-display', '位置与显示 · 浅色', 'settings-light-display.png', False,
     'settings-display-light-crop.png', [780, 584],
     '原生内容宽960pt；重复框体、较大的位置示意和常驻保存区域。',
     '建议780×584pt；六位置与示意结合，参数以行组织，编辑时才出现应用栏。'),
    ('control', '菜单栏控制中心 · 浅色', 'control-light.png', True,
     'control-light-crop.png', [304, 348],
     '原生336pt内容宽；隔离审核字样与禁用控件不是产品缺陷。',
     '建议304pt内容宽；当前状态并入标题，常用动作集中，低频入口下沉。'),
    ('history', '截图历史 · 深色', 'history-real-isolated-records.png', False,
     'history-dark-crop.png', [828, 582],
     '原生三栏、以状态和文字列表为主要组织；合成隔离记录。',
     '按时间浏览图像，六筛选与搜索保留；右侧详情随选择出现。'),
    ('onboarding', '首次使用 · 浅色', 'onboarding-light-1.png', False,
     'onboarding-light-crop.png', [620, 516],
     '原生652×608pt；三步介绍、补充说明和主操作分布在多个区域。',
     '建议620×516pt；连贯的三步示意，权限和位置分步解释。')
]
baselines = {}
for key, title, before_name, trim, after_name, after_size, bn, an in sources:
    bi, bs = native(before_name, trim)
    ai, ass = after(after_name, after_size)
    baselines[key] = dict(title=title, before=bi, after=ai, beforeSize=bs, afterSize=ass,
                         beforeNote=bn, afterNote=an,
                         source='Before：a5aefd3d原生隔离审核；其UI/App源码与正式main 71d726c5一致。After：独立Mac Chrome实际渲染的设计原型。所有样例均非用户真实截图。')
(P / 'baselines.js').write_text('/* Real captured images with explicit provenance. */\nwindow.RiftBaselines=' + json.dumps(baselines, ensure_ascii=False, separators=(',', ':')) + ';\n')

css = '\n'.join((P / n).read_text() for n in ['app.css', 'settings.css'])
js = '\n'.join((P / n).read_text() for n in ['samples.js', 'baselines.js', 'settings.js', 'app.js'])
favicon = 'data:image/svg+xml;base64,' + base64.b64encode((P / 'assets/riftlet.svg').read_bytes()).decode()
document = (P / 'index.html').read_text()
document = document.replace('href="assets/riftlet.svg"', 'href="' + favicon + '"')
document = document.replace('<link rel="stylesheet" href="app.css">', '<style>\n' + css + '\n</style>')
document = document.replace('  <link rel="stylesheet" href="settings.css">\n', '')
document = document.replace('<script src="samples.js"></script>', '<script>\n' + js + '\n</script>')
for n in ['baselines.js', 'settings.js', 'app.js']:
    document = document.replace('  <script src="' + n + '"></script>\n', '')
(OUT / 'Riftlet-Experience-Prototype.html').write_text(document)

def font(size):
    candidates = [Path('/workspace/scratch/782909c86400/fonts/NotoSansCJKsc-Regular.otf'),
                  Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
                  Path('/System/Library/Fonts/PingFang.ttc')]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)

def paste_fit(canvas, image, box):
    image = image.convert('RGBA')
    x, y, w, h = box
    image.thumbnail((w, h), Image.Resampling.LANCZOS)
    canvas.paste(image, (round(x + (w-image.width)/2), round(y + (h-image.height)/2)), image)

# Actual pixel captures arranged as an overview; no UI is redrawn here.
overview = Image.new('RGB', (2240, 1520), '#f3f2ef')
d = ImageDraw.Draw(overview)
d.text((72, 42), 'Riftlet', fill='#282b29', font=font(48))
d.text((280, 62), '让截图属于边缘，让工作继续。', fill='#686f69', font=font(25))
d.text((72, 124), '实际交互原型渲染 · 完整设计候选', fill='#686f69', font=font(20))
panels = [
    ('桌面边缘 / 2×细节', 'desktop-edge-2x.png', (72, 205, 405, 650)),
    ('控制中心', 'control-light-crop.png', (540, 205, 395, 650)),
    ('位置与显示', 'settings-display-light-crop.png', (1000, 205, 1168, 650)),
    ('截图历史 · 深色', 'history-dark-crop.png', (72, 935, 1034, 500)),
    ('首次使用', 'onboarding-light-crop.png', (1160, 935, 1008, 500))
]
for title, name, box in panels:
    x,y,w,h=box
    d.text((x,y-44), title, fill='#282b29', font=font(22))
    d.rounded_rectangle((x,y,x+w,y+h), radius=14, fill='#e9e8e3')
    paste_fit(overview, Image.open(E/'prototype'/name), (x+16,y+16,w-32,h-32))
d.text((72, 1463), '合成内容 / 不修改现有App、截图或聊天。原生Before与证据身份见交付文件。', fill='#686f69', font=font(18))
overview.save(OUT/'Riftlet-Design-Overview.png', optimize=True)

# A genuine same-logical-scale before/after plate for the main settings page.
plate = Image.new('RGB', (2160, 1060), '#f3f2ef')
d=ImageDraw.Draw(plate)
d.text((60,36), '位置与显示：真实原生基线 → 本轮设计', fill='#282b29', font=font(34))
d.text((60,100), '两侧采用相同逻辑比例。Before为隔离原生审核；After为实际网页渲染。', fill='#686f69', font=font(20))
d.text((60,170), 'Beta 2 · 原生截图', fill='#282b29', font=font(25))
d.text((1140,170), '设计候选 · 交互原型', fill='#282b29', font=font(25))
bi=Image.open(E/'native/settings-light-display.png').convert('RGBA')
ai=Image.open(E/'prototype/settings-display-light-crop.png').convert('RGBA')
bi=bi.resize((960,712),Image.Resampling.LANCZOS)
ai=ai.resize((780,584),Image.Resampling.LANCZOS)
plate.paste(bi,(60,235),bi)
plate.paste(ai,(1140,235),ai)
d.text((60,988), '来源：a5aefd3d（UI/App与main 71d726c5无差异）', fill='#686f69', font=font(18))
d.text((1140,988), '完整16项参数保留 · 非生产App已实现', fill='#686f69', font=font(18))
plate.save(OUT/'Riftlet-Before-After.png',optimize=True)

parser=argparse.ArgumentParser()
parser.add_argument('--inline', type=Path)
args=parser.parse_args()
if args.inline:
    import tinycss2
    # Product-specific, root-scoped CSS. Do not inherit host utility geometry.
    inline_css=re.sub(r'\bbtn', 'rf-btn', css)
    inline_css=inline_css.replace('min-height:100vh;', 'min-height:0;')
    inline_css=inline_css.replace('cursor:pointer','cursor:inherit')
    def scoped_rules(rules):
        out=[]
        for rule in rules:
            if rule.type=='qualified-rule':
                selectors=tinycss2.serialize(rule.prelude)
                ss=[]
                for selector in selectors.split(','):
                    selector=selector.strip()
                    if selector in ['html','body']:
                        selector='#riftlet-design'
                    elif not selector.startswith('#riftlet-design'):
                        selector='#riftlet-design '+selector
                    ss.append(selector)
                out.append(','.join(ss)+'{'+tinycss2.serialize(rule.content)+'}')
            elif rule.type=='at-rule' and rule.content is not None and rule.lower_at_keyword in ['media','supports','layer']:
                out.append('@'+rule.at_keyword+' '+tinycss2.serialize(rule.prelude)+'{'+scoped_rules(tinycss2.parse_rule_list(rule.content))+'}')
            else:
                out.append(tinycss2.serialize([rule]))
        return '\n'.join(out)
    inline_css=scoped_rules(tinycss2.parse_stylesheet(inline_css))
    inline_css+='\n#riftlet-design{background:transparent;padding:16px 0;min-height:0;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC",sans-serif}#riftlet-design .viewer-top-actions{margin-right:90px}#riftlet-design .brand-mark img{width:22px;height:22px}#riftlet-design .scene-meta{gap:10px}#riftlet-design .review-footer{margin-bottom:0}@media(max-width:600px){#riftlet-design .viewer-top-actions{margin-right:0}}'
    inline_js=re.sub(r'\bbtn', 'rf-btn', js)
    icon_start=inline_js.index(' const paths={')
    icon_end=inline_js.index(' const I=',icon_start)
    icon_names={'settings':'sliders-horizontal','display':'monitor','monitor':'monitor','motion':'move','help':'circle-help','external':'square-arrow-out-up-right','info':'info','shield':'shield-check','x':'x','refresh':'rotate-ccw','arrows':'move-horizontal','back':'chevron-left','more':'ellipsis','arrow':'arrow-up','expand':'maximize','window':'app-window','volume':'volume-2'}
    icon_code=' const iconNames='+json.dumps(icon_names)+';\n window.icon=(name,size=16)=>`<i data-lucide="${iconNames[name]||name}" aria-hidden="true" style="width:${size}px;height:${size}px"></i>`;\n'
    inline_js=inline_js[:icon_start]+icon_code+inline_js[icon_end:]
    logo_start=inline_js.index(' const logo=')
    logo_end=inline_js.index('\n',logo_start)
    inline_js=inline_js[:logo_start]+' const logo=(size=20)=>`<img src="'+favicon+'" width="${size}" height="${size}" alt="">`;'+inline_js[logo_end:]
    inline_js=inline_js.replace("document.body.style.background=state.theme==='dark'?'#1c1f1e':'#f5f4f1'",'')
    inline_js=inline_js.replace("theme:params.get('theme')==='dark'?'dark':'light'", "theme:(params.get('theme')|| (matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light'))")
    inline_js=inline_js.replace("appearance:params.get('theme')||'light'", "appearance:params.get('theme')||'system'")
    inline_js+='\n(()=>{const r=document.getElementById("riftlet-design");const enhance=()=>{r.querySelectorAll("button,select,input[type=checkbox],input[type=range]").forEach(e=>e.classList.add("cursor-interaction"));if(r.querySelector("i[data-lucide]")&&window.lucide)lucide.createIcons({attrs:{width:16,height:16}})};new MutationObserver(enhance).observe(r,{childList:true,subtree:true});enhance()})();\n'
    shell=(ROOT/'tools/inline-shell.html').read_text()
    fragment=shell.replace('/* RIFTLET_INLINE_CSS */',inline_css).replace('/* RIFTLET_INLINE_JS */',inline_js)
    assert len(fragment.encode()) < 1_000_000, len(fragment.encode())
    args.inline.write_text(fragment)
    print('Inline bytes:',len(fragment.encode()))

manifest=[]
for path in sorted(ROOT.rglob('*')):
    if path.is_file() and path.name not in ['MANIFEST.json','Riftlet-Design-Handoff.zip']:
        manifest.append({'path':str(path.relative_to(ROOT)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(ROOT/'MANIFEST.json').write_text(json.dumps({'baseCommit':'71d726c5d6416346b84e1ac93047af5bb321d925','files':manifest},ensure_ascii=False,indent=2)+'\n')
with zipfile.ZipFile(OUT/'Riftlet-Design-Handoff.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path in sorted(ROOT.rglob('*')):
        if path.is_file() and path.name!='Riftlet-Design-Handoff.zip':
            z.write(path,'Riftlet-Design/'+str(path.relative_to(ROOT)))
print('Offline bytes:',(OUT/'Riftlet-Experience-Prototype.html').stat().st_size)
print('Bundle bytes:',(OUT/'Riftlet-Design-Handoff.zip').stat().st_size)
