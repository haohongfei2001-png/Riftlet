"""Build an offline viewer of existing WindowServer captures. No generated UI images."""
import argparse, hashlib, html, json, shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

a=argparse.ArgumentParser()
for name in ("windows","desktop","old-settings","old-tray","out","boards"):
    a.add_argument("--"+name,type=Path,required=True)
args=a.parse_args()
args.out.mkdir(parents=True,exist_ok=True); args.boards.mkdir(parents=True,exist_ok=True)
assets=args.out/"原始实拍";assets.mkdir(exist_ok=True)
titles={"settings-0":"外观与布局","settings-1":"截图","settings-2":"使用与历史","settings-3":"权限与帮助","save-error":"设置保存失败与重试","intro-capture":"首用 · 截图","intro-connect":"首用 · 连接","intro-place":"首用 · 位置","history-list":"历史 · 列表","history-grid":"历史 · 图像网格","history-unknown":"历史 · 待核实","control":"控制中心 · 正在收录","control-paused":"控制中心 · 已暂停","control-hidden":"控制中心 · 已隐藏","control-both":"控制中心 · 暂停并隐藏","permission":"权限恢复","feedback":"反馈"}
groups=[("设置",["settings-"+str(i) for i in range(4)]+["save-error"]),("首用",["intro-capture","intro-connect","intro-place"]),("历史",["history-list","history-grid","history-unknown"]),("菜单栏",["control","control-paused","control-hidden","control-both"]),("权限和反馈",["permission","feedback"])]
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
receipts=json.loads((args.windows/"receipts.json").read_text())
assert {(r["style"],r["scene"]) for r in receipts["windows"]}=={(k,s) for k in ("light","dark") for s in titles}
for r in receipts["windows"]:
    f=args.windows/r["file"];assert sha(f)==r["sha256"]
    shutil.copyfile(f,assets/r["file"])
frames={"prev-settings":("上一版设置",args.old_settings),"prev-tray":("上一版托盘 · build 13",args.old_tray),"tray":("截图托盘 · 1920 pt 横屏",args.desktop/"tray-primary/closed-3.png"),"open":("展开菜单 · 同一横屏",args.desktop/"tray-primary/expanded-3.png"),"portrait":("截图托盘 · 800 pt 竖屏",args.desktop/"tray-portrait/closed-3.png"),"portrait-open":("展开菜单 · 同一竖屏",args.desktop/"tray-portrait/expanded-3.png"),"micro":("微缝 · 右边缘",args.desktop/"micro-primary/closed-3.png")}
for key,(title,f) in frames.items():shutil.copyfile(f,assets/(key+".png"))
groups.append(("桌面",["tray","open","portrait","portrait-open","micro"]))
groups.append(("新旧对照",["prev-settings","settings-0","prev-tray","tray"]))
titles.update({k:v[0] for k,v in frames.items()})
def photo(key):
    named=key not in frames
    stem=("light-" if named else "")+key
    file="原始实拍/"+stem+".png"
    return f'<figure><figcaption>{html.escape(titles[key])}</figcaption><a href="{file}" target="_blank"><img alt="{html.escape(titles[key])}" src="{file}" data-scene="{key if named else ""}" loading="lazy"></a></figure>'
page="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Riftlet · 原生视觉审阅</title><style>
:root{color-scheme:light dark;--paper:#f5f7f6;--ink:#202d29;--line:#cbd6d1;--accent:#087c70}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0 auto;max-width:1320px;padding:30px 4vw 80px;background:var(--paper);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,sans-serif}body.dark{--paper:#182220;--ink:#edf3f1;--line:#41504a;--accent:#7adfd1}h1{font-size:clamp(34px,5vw,60px);margin:0;letter-spacing:-.045em}header p{max-width:780px}small,figcaption{font-weight:650}nav{display:flex;flex-wrap:wrap;align-items:center;gap:7px 16px;border-block:1px solid var(--line);padding:12px 0}a{color:var(--accent);text-decoration:none}button{border:1px solid var(--line);border-radius:6px;padding:5px 12px;color:var(--ink);background:transparent;font:inherit}section{padding:20px 0;border-bottom:1px solid var(--line)}section h2{margin:0 0 14px}.layout{display:grid;grid-template-columns:1fr 1fr;gap:22px 20px}figure{min-width:0;margin:0}figcaption{margin-bottom:6px}img{display:block;max-width:100%;height:auto;border-radius:10px}figure a{display:flex;align-items:flex-start}footer{padding-top:22px}@media(max-width:850px){.layout{grid-template-columns:1fr}} </style>
<header><small>RIFTLET ／ PR 58</small><h1>原生界面审阅</h1><p>这些是实际 macOS 窗口的照片。点击可打开原始像素。设置、首用、历史和控制中心来自隔离的 AppKit 审阅 App；桌面照片来自实际产品渲染器。示例图片和权限状态均不取自生产数据。</p></header>"""
page+='<nav>'+''.join(f'<a href="#s{i}">{n}</a>' for i,(n,_) in enumerate(groups))+'<button id="mode" type="button" aria-pressed="false">切换至深色实拍</button></nav>'
for i,(n,keys) in enumerate(groups):
    page+=f'<section id="s{i}"><h2>{n}</h2>'
    if n=="桌面":page+='<p>横屏 240 / 1920 pt；竖屏 100 / 800 pt。均为 12.5%，开合不改变宽度。风铃缺少经确认的原始设计，没有对应实拍。</p>'
    if n=="新旧对照":page+='<p>旧设置来自 Beta 2 原生实拍，旧托盘来自 PR #57 签名 build 13。窗口构图与显示比例可能不同；桌面宽度以 WindowServer 点值为准。</p>'
    page+='<div class="layout">'+''.join(map(photo,keys))+'</div></section>'
page+="""<footer>PR #58 · 视觉裁决候选。未安装、未公开发布；这组照片不证明真实 ChatGPT 接收。</footer><script>const mode=document.querySelector('#mode');mode.onclick=()=>{let dark=document.body.classList.toggle('dark');mode.textContent=dark?'切换至浅色实拍':'切换至深色实拍';mode.setAttribute('aria-pressed',String(dark));for(const img of document.querySelectorAll('img[data-scene]')){if(!img.dataset.scene)continue;const src='原始实拍/'+(dark?'dark':'light')+'-'+img.dataset.scene+'.png';img.src=src;img.parentNode.href=src}}</script></html>"""
(args.out/"原生视觉审阅.html").write_text(page)
shutil.copyfile(args.windows/"receipts.json",args.out/"窗口回执.json")
font=ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc",32)
small=ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc",23)
def board(slug,title,keys):
    w,h=1680,600
    out=Image.new("RGB",(w,h*((len(keys)+1)//2)+98),"#f1f4f2");d=ImageDraw.Draw(out)
    d.text((40,22),title,fill="#183a34",font=font)
    for i,(key,stem) in enumerate(keys):
        x=(i%2)*w//2+32;y=(i//2)*h+100
        d.text((x,y),key,fill="#23443e",font=small)
        with Image.open(assets/(stem+".png")) as src:
            im=ImageOps.contain(src.convert("RGBA"),(w//2-64,h-74),Image.Resampling.LANCZOS)
            out.paste(im,(x+(w//2-64-im.width)//2,y+48),im.getchannel("A"))
    out.save(args.boards/(slug+".jpg"),quality=92,optimize=True)
board("settings","Riftlet  /  设置中心",[("01   外观与布局","light-settings-0"),("02   截图","light-settings-1"),("03   使用与历史","light-settings-2"),("04   权限与帮助","light-settings-3")])
board("surfaces","Riftlet  /  从首次使用到日常操作",[("首用引导","light-intro-capture"),("历史 · 列表","light-history-list"),("菜单栏 · 暂停并隐藏","light-control-both"),("权限恢复 · 深色","dark-permission")])
board("desktop","Riftlet  /  桌面原生对照",[("PR #57   旧版  ·  约 14.7%","prev-tray"),("PR #58   横屏  ·  12.5%","tray"),("PR #58   展开后仍为两行","open"),("PR #58   微缝","micro")])
