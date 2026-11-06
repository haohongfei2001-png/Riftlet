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
import platform
from importlib.metadata import version
from verify_delivery import expected_payloads, validate_html, check_javascript
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'prototype'
E = ROOT / 'evidence'
OUT = ROOT / 'exports'
OUT.mkdir(exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--inline', type=Path)
parser.add_argument('--font', type=Path, help='CJK font used only for text on composite export plates')
parser.add_argument('--node', default='node', help='Node executable for the required JavaScript syntax gate')
args = parser.parse_args()
font_candidates = ([args.font] if args.font else [
    Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
    Path('/System/Library/Fonts/PingFang.ttc'),
    Path('/System/Library/Fonts/STHeiti Medium.ttc'),
])
font_path = next((path for path in font_candidates if path.is_file()), None)
if font_path is None:
    parser.error('No CJK font found. Pass --font /path/to/a/CJK-font; do not silently export missing-glyph labels.')

def replace_once(text, marker, replacement):
    if text.count(marker) != 1:
        raise ValueError('Expected exactly one template marker: ' + marker)
    return text.replace(marker, replacement, 1)

def write_utf8(path, text):
    path.write_text(text, encoding='utf-8')


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
write_utf8(P / 'baselines.js', '/* Real captured images with explicit provenance. */\nwindow.RiftBaselines=' + json.dumps(baselines, ensure_ascii=False, separators=(',', ':')) + ';\n')

js, css, favicon = expected_payloads(P)
document = (P / 'index.html').read_text(encoding='utf-8')
document = replace_once(document, 'href="assets/riftlet.svg"', 'href="' + favicon + '"')
document = replace_once(document, '<link rel="stylesheet" href="app.css">', '<style>\n' + css + '\n</style>')
document = replace_once(document, '  <link rel="stylesheet" href="settings.css">\n', '')
document = replace_once(document, '<script src="samples.js"></script>', '<script>\n' + js + '\n</script>')
for n in ['baselines.js', 'settings.js', 'app.js']:
    document = replace_once(document, '  <script src="' + n + '"></script>\n', '')
# Validate BEFORE replacing the last good artifact. In particular, $$ must be
# preserved literally; the full source check also covers every other token.
validation = validate_html(document, P, args.node)
temporary = OUT / '.Riftlet-Experience-Prototype.html.tmp'
write_utf8(temporary, document)
temporary.replace(OUT / 'Riftlet-Experience-Prototype.html')

def font(size):
    return ImageFont.truetype(str(font_path), size)

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
d.text((72, 124), '历史原型实拍汇总 · 本轮新图见验证证据', fill='#686f69', font=font(20))
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
d.text((60,36), '位置与显示：原生基线 → 历史网页设计', fill='#282b29', font=font(34))
d.text((60,100), '两侧采用相同逻辑比例。保留历史 Before / After，不代表本轮新视觉验收。', fill='#686f69', font=font(20))
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
    check_javascript(inline_js, args.node)
    write_utf8(args.inline, fragment)
    print('Inline bytes:',len(fragment.encode()))

# Historical PNG captures are recomposed, not relabelled as new UI renders.
artifact_names = ['Riftlet-Experience-Prototype.html', 'Riftlet-Design-Overview.png', 'Riftlet-Before-After.png']
report = {
    'schemaVersion': 1, 'result': 'PASS', 'validation': validation,
    'runtime': {'python': platform.python_version(), 'Pillow': version('Pillow'), 'tinycss2': version('tinycss2')},
    'font': {'name': font_path.name, 'sha256': hashlib.sha256(font_path.read_bytes()).hexdigest()},
    'builderSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'validatorSHA256': hashlib.sha256((ROOT/'tools/verify_delivery.py').read_bytes()).hexdigest(),
    'originalBrandSHA256': hashlib.sha256((P/'assets/riftlet.svg').read_bytes()).hexdigest(),
    'artifacts': [{'path': 'exports/'+name, 'sha256': hashlib.sha256((OUT/name).read_bytes()).hexdigest()} for name in artifact_names],
    'imageScope': 'Composite plates retain historical captured UI pixels; regeneration is not new native or current-prototype visual acceptance.'
}
write_utf8(OUT/'build-report.json', json.dumps(report, ensure_ascii=False, indent=2)+'\n')

def delivery_files():
    return [path for path in sorted(ROOT.rglob('*')) if path.is_file()
            and '__pycache__' not in path.parts and path.name != '.DS_Store'
            and not path.name.endswith('.tmp') and path.name != 'Riftlet-Design-Handoff.zip']

manifest=[]
for path in delivery_files():
    if path.name != 'MANIFEST.json':
        manifest.append({'path':str(path.relative_to(ROOT)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
write_utf8(ROOT/'MANIFEST.json', json.dumps({'baseCommit':'71d726c5d6416346b84e1ac93047af5bb321d925','files':manifest},ensure_ascii=False,indent=2)+'\n')
# Stable order, timestamp and regular-file mode make an unchanged delivery
# byte-reproducible in the recorded dependency/font environment.
with zipfile.ZipFile(OUT/'Riftlet-Design-Handoff.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path in delivery_files():
        info = zipfile.ZipInfo('Riftlet-Design/'+str(path.relative_to(ROOT)), date_time=(1980,1,1,0,0,0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, path.read_bytes(), compresslevel=6)
print('Source-payload and JavaScript syntax gates: PASS')
print('Offline bytes:',(OUT/'Riftlet-Experience-Prototype.html').stat().st_size)
print('Bundle bytes:',(OUT/'Riftlet-Design-Handoff.zip').stat().st_size)
