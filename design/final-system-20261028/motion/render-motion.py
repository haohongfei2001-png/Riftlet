#!/usr/bin/env python3
"""Riftlet design films. Original synthetic scenes; no screen capture or upload.

One pure timing model drives PNG/SVG frames and 60 fps H.264 films. Pillow is
used only as a deterministic vector-style renderer, not for editing user images.
Run: python3 render-motion.py [--stills-only]
"""
from __future__ import annotations

import argparse
import fcntl
from functools import lru_cache
import hashlib
import html
import json
import math
from pathlib import Path
import subprocess
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
W, H, FPS, SCALE = 1440, 900, 60, 2
EDGE, ENTRY_X, ENTRY_Y, FIRST_Y, PITCH = 1426.0, 1408.0, 164.0, 230.0, 60.0
FONT = next((p for p in [Path('/tmp/riftlet-NotoSansCJKsc-Regular.otf'),
    Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
    Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')] if p.exists()))
INK, SECONDARY, PAPER, LINE, ACCENT = '#26313b', '#64717a', '#fbfcfd', '#26323b', '#365ec8'


def save_png(image: Image.Image, path: Path) -> None:
    temporary=path.with_name(path.name+'.partial')
    image.save(temporary,format='PNG',optimize=True)
    with Image.open(temporary) as check:
        check.verify()
    temporary.replace(path)


def clamp(x: float, low: float = 0, high: float = 1) -> float:
    return max(low, min(high, x))


def smooth(x: float) -> float:
    x = clamp(x)
    return x * x * x * (x * (x * 6 - 15) + 10)


def out_cubic(x: float) -> float:
    return 1 - (1 - clamp(x)) ** 3


def lerp(a: float, b: float, p: float) -> float:
    return a + (b - a) * p


@lru_cache(maxsize=50)
def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), round(size * SCALE))


def rgba(color: str, opacity: float = 1) -> tuple[int, int, int, int]:
    value = color.lstrip('#')
    return tuple(int(value[i:i+2], 16) for i in (0, 2, 4)) + (round(255 * clamp(opacity)),)


class Canvas:
    def __init__(self, image: Image.Image | None = None, svg: bool = False):
        self.image = image.copy() if image is not None else Image.new('RGBA', (W*SCALE, H*SCALE), '#e5e9e7')
        self.draw = ImageDraw.Draw(self.image)
        self.vector = [] if svg else None
        self.clip_count = 0

    def add(self, value: str) -> None:
        if self.vector is not None:
            self.vector.append(value)

    def rect(self, x: float, y: float, w: float, h: float, fill: str, radius: float = 0,
             opacity: float = 1, stroke: str | None = None, width: float = 1) -> None:
        if w <= 0 or h <= 0 or opacity <= 0:
            return
        bounds = (round(x*SCALE), round(y*SCALE), round((x+w)*SCALE), round((y+h)*SCALE))
        target = self.image
        translucent = opacity < 1
        if translucent:
            target = Image.new('RGBA', self.image.size)
        d = ImageDraw.Draw(target)
        params = {'fill': rgba(fill, opacity)}
        if stroke:
            params.update(outline=rgba(stroke, opacity), width=max(1, round(width*SCALE)))
        if radius:
            d.rounded_rectangle(bounds, radius=round(radius*SCALE), **params)
        else:
            d.rectangle(bounds, **params)
        if translucent:
            self.image.alpha_composite(target)
            self.draw = ImageDraw.Draw(self.image)
        self.add(f'<rect x="{x:.4f}" y="{y:.4f}" width="{w:.4f}" height="{h:.4f}" rx="{radius:.4f}" fill="{fill}" opacity="{opacity:.5f}"'
                 + (f' stroke="{stroke}" stroke-width="{width}"' if stroke else '') + '/>')

    def line(self, points: Iterable[tuple[float, float]], color: str, width: float = 1, opacity: float = 1) -> None:
        points = list(points)
        if len(points) < 2 or opacity <= 0:
            return
        pad=max(2,math.ceil(width*SCALE))
        bx=max(0,math.floor(min(x for x,y in points)*SCALE)-pad)
        by=max(0,math.floor(min(y for x,y in points)*SCALE)-pad)
        ex=min(W*SCALE,math.ceil(max(x for x,y in points)*SCALE)+pad+1)
        ey=min(H*SCALE,math.ceil(max(y for x,y in points)*SCALE)+pad+1)
        if ex<=bx or ey<=by:return
        target = self.image if opacity == 1 else Image.new('RGBA', (ex-bx,ey-by))
        d = ImageDraw.Draw(target)
        dx,dy=(0,0) if opacity==1 else(bx,by)
        d.line([(round(x*SCALE)-dx, round(y*SCALE)-dy) for x, y in points], fill=rgba(color, opacity), width=max(1, round(width*SCALE)), joint='curve')
        if opacity < 1:
            self.image.alpha_composite(target,dest=(bx,by))
            self.draw = ImageDraw.Draw(self.image)
        self.add('<polyline points="' + ' '.join(f'{x:.4f},{y:.4f}' for x, y in points)
                 + f'" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" opacity="{opacity:.5f}"/>')

    def ellipse(self, x: float, y: float, w: float, h: float, fill: str, opacity: float = 1) -> None:
        bx,by=math.floor(x*SCALE)-1,math.floor(y*SCALE)-1
        target = self.image if opacity == 1 else Image.new('RGBA', (math.ceil(w*SCALE)+3,math.ceil(h*SCALE)+3))
        dx,dy=(0,0)if opacity==1 else(bx,by)
        ImageDraw.Draw(target).ellipse((round(x*SCALE)-dx,round(y*SCALE)-dy,round((x+w)*SCALE)-dx,round((y+h)*SCALE)-dy), fill=rgba(fill, opacity))
        if opacity < 1:
            self.image.alpha_composite(target,dest=(bx,by))
            self.draw = ImageDraw.Draw(self.image)
        self.add(f'<ellipse cx="{x+w/2:.4f}" cy="{y+h/2:.4f}" rx="{w/2:.4f}" ry="{h/2:.4f}" fill="{fill}" opacity="{opacity:.5f}"/>')

    def text(self, x: float, y: float, value: str, size: float = 13, color: str = INK) -> None:
        self.draw.text((round(x*SCALE), round(y*SCALE)), value, font=font(size), fill=rgba(color))
        # SVG uses actual text, not embedded bitmap. Font fallback is disclosed.
        numeric=' style="font-variant-numeric:tabular-nums"'if value.isdecimal()else''
        self.add(f'<text x="{x:.4f}" y="{y+size*1.12:.4f}" fill="{color}" font-family="Noto Sans CJK SC, PingFang SC, sans-serif" font-size="{size}"{numeric}>{html.escape(value)}</text>')

    def polygon(self, points: list[tuple[float, float]], fill: str, stroke: str | None = None, width: float = 1) -> None:
        self.draw.polygon([(round(x*SCALE), round(y*SCALE)) for x,y in points], fill=rgba(fill))
        if stroke:
            self.line(points+[points[0]], stroke, width)
        self.add('<polygon points="'+' '.join(f'{x:.3f},{y:.3f}' for x,y in points)+f'" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{width}"' if stroke else '')+'/>')

    def snapshot(self) -> Image.Image:
        return self.image.resize((W,H), Image.Resampling.LANCZOS).convert('RGB')

    def svg(self) -> str:
        return '<?xml version="1.0" encoding="UTF-8"?>\n' + f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Riftlet 设计模拟，非真实上传">\n' + '\n'.join(self.vector or []) + '\n</svg>\n'


def photo(c: Canvas, x: float, y: float, w: float, h: float, variant: int = 0, clip_edge: float | None = None) -> None:
    """Original geometric screenshot fixture; never user media."""
    # Render into a reusable transparent layer for exact static-plane clipping.
    start = len(c.vector) if c.vector is not None else 0
    before = c.image.copy() if clip_edge is not None else None
    palettes = [('#e7e3dc','#5a766e','#c1c9b8'),('#dde5ef','#677b95','#becbd9'),('#e9dfd5','#936c57','#ccb3a1')]
    bg, dark, mid = palettes[variant % 3]
    c.rect(x,y,w,h,bg)
    c.rect(x+w*.08,y+h*.12,w*.55,h*.055,dark)
    c.rect(x+w*.08,y+h*.22,w*.38,h*.025,dark)
    c.rect(x+w*.08,y+h*.33,w*.84,h*.47,mid)
    c.ellipse(x+w*.53,y+h*.39,w*.29,h*.36,dark)
    c.rect(x+w*.08,y+h*.88,w*.63,h*.018,dark)
    if clip_edge is not None:
        cut = round(clip_edge*SCALE)
        c.image.paste(before.crop((cut,0,W*SCALE,H*SCALE)),(cut,0))
        c.draw = ImageDraw.Draw(c.image)
        if c.vector is not None:
            items = c.vector[start:]
            del c.vector[start:]
            c.clip_count += 1
            key=f'plane-{c.clip_count}'
            c.add(f'<defs><clipPath id="{key}"><rect x="0" y="0" width="{clip_edge}" height="{H}"/></clipPath></defs><g clip-path="url(#{key})">'+''.join(items)+'</g>')


def rift(c: Canvas, rows: list[dict], line: bool = True) -> None:
    if not rows:
        return
    for row in rows:
        cy, variant, index = row['y'], row.get('variant',0), row.get('number',1)
        w,h = row.get('size',(72,45))
        offset = row.get('offset',0)
        photo(c,EDGE-w*.75+offset,cy-h/2,w,h,variant,clip_edge=EDGE)
        number_right=EDGE-w*.75-8
        if row.get('number_visible',True):
            number(c,number_right,cy,index)
        if row.get('waiting',False):
            c.line([(number_right-6,cy+10),(number_right,cy+10)],ACCENT,1)
    if line:
        top=min(r['y']-r.get('size',(72,45))[1]/2 for r in rows)-8
        bottom=max(r['y']+r.get('size',(72,45))[1]/2 for r in rows)+8
        c.line([(EDGE,top),(EDGE,bottom)],LINE,.5,.57)


def number(c: Canvas, right: float, cy: float, value: int) -> None:
    label=str(value)
    ink_right=font(11).getbbox(label)[2]/SCALE
    c.text(right-ink_right,cy-7,label,11,SECONDARY)


def glyph(c: Canvas, name: str, cx: float, cy: float, opacity: float = 1) -> None:
    def ln(p): c.line([(cx+x,cy+y) for x,y in p],INK,1.2,opacity)
    if name=='x':
        ln([(-4.3,-4.3),(4.3,4.3)]);ln([(-4.3,4.3),(4.3,-4.3)])
    elif name=='more':
        for x in [-5,0,5]: c.ellipse(cx+x-.8,cy-.8,1.6,1.6,INK,opacity)
    elif name=='region':
        for p in [[(-7,-2),(-7,-6),(-3,-6)],[(3,-6),(7,-6),(7,-2)],[(7,2),(7,6),(3,6)],[(-3,6),(-7,6),(-7,2)]]:ln(p)
    elif name=='full':
        ln([(-7,-6),(7,-6),(7,4),(-7,4),(-7,-6)]);ln([(0,4),(0,7)]);ln([(-4,7),(4,7)])
    elif name=='window':
        ln([(-7,-6),(7,-6),(7,6),(-7,6),(-7,-6)]);ln([(-7,-2),(7,-2)])
        for x in [-4,-1]:c.ellipse(cx+x-.5,cy-4.5,1,1,INK,opacity)
    else:
        ln([(-7,-4),(-3,-4),(-2,-6),(2,-6),(3,-4),(7,-4),(7,6),(-7,6),(-7,-4)])
        n=20
        ln([(math.cos(i/n*math.tau)*3,math.sin(i/n*math.tau)*3+1)for i in range(n+1)])


def entry(c: Canvas, expansion: float = 0, cover: float = 0, glyph_alpha: float = 1, glass_alpha: float = 1, expanded: bool = False) -> None:
    bottom=ENTRY_Y+18
    height=36+96*expansion
    # Stylized material reference. No claim that these pixels are AppKit's blur.
    c.rect(ENTRY_X-18,bottom-height+3,36,height,'#253143',10+2*expansion,glass_alpha*.07)
    c.rect(ENTRY_X-18,bottom-height,36,height,'#f4f6fa',10+2*expansion,glass_alpha*.82,'#ffffff',.75)
    before=c.image.copy()
    vector_start=len(c.vector) if c.vector is not None else 0
    if expanded and expansion>0:
        c.rect(ENTRY_X-15,ENTRY_Y-15-cover*32,30,30,'#d9dfe9',8,glass_alpha*.56)
    if not expanded:
        glyph(c,'camera',ENTRY_X,ENTRY_Y,glyph_alpha)
    else:
        active = round(cover)
        for i,name in enumerate(['window','region','full','more']):
            center=ENTRY_Y-32*i
            # Hide whichever fixed icon is covered by the actual moving cover.
            if abs(i-cover)<.45 and i<3:
                continue
            glyph(c,name,ENTRY_X,center,glyph_alpha)
        glyph(c,'x',ENTRY_X,ENTRY_Y-32*cover,glyph_alpha)
    # The growing material owns the reveal mask; upper icons/cover never float
    # outside it during an interrupted opening or retraction.
    top=round((bottom-height)*SCALE)
    c.image.paste(before.crop((0,0,W*SCALE,top)),(0,0))
    c.draw=ImageDraw.Draw(c.image)
    if c.vector is not None:
        nodes=c.vector[vector_start:];del c.vector[vector_start:]
        c.clip_count+=1;key=f'entry-mask-{c.clip_count}'
        c.add(f'<defs><clipPath id="{key}"><rect x="{ENTRY_X-18}" y="{bottom-height}" width="36" height="{height}" rx="{10+2*expansion}"/></clipPath></defs><g clip-path="url(#{key})">'+''.join(nodes)+'</g>')


def pointer(c: Canvas, x: float, y: float, pressed: bool = False) -> None:
    points=[(x,y),(x+1,y+17),(x+5,y+13),(x+9,y+20),(x+12,y+18),(x+8,y+12),(x+14,y+11)]
    c.polygon(points,'#20262d','#ffffff',1)
    if pressed:c.ellipse(x-3,y-3,3,3,ACCENT)


def base(c: Canvas) -> None:
    c.rect(0,0,W,H,'#e6e9e6')
    # Quiet original desktop fields, geometrically authored, no borrowed wallpaper.
    c.polygon([(0,390),(390,200),(740,335),(1040,0),(1440,0),(1440,900),(0,900)],'#d9e2de')
    c.polygon([(0,690),(380,560),(700,650),(1130,390),(1440,470),(1440,900),(0,900)],'#c5d4ce')
    c.rect(0,0,W,28,'#f6f8f7',opacity=.72)
    c.text(18,4,'●',12);c.text(47,4,'Chrome',12);c.text(114,4,'文件   编辑   查看   历史记录   窗口   帮助',12)
    c.text(1140,4,'Riftlet     10月28日 周三  16:20',11)
    # Authored browser window at ordinary 100% logical desktop scale.
    c.rect(170,94,1080,690,'#b9c6c1',13)
    c.rect(170,85,1080,690,PAPER,12)
    c.rect(170,85,1080,74,'#f2f4f5',12)
    c.rect(170,122,1080,37,'#f2f4f5')
    for i,color in enumerate(['#ee766b','#e4be5d','#6fb983']):c.ellipse(186+i*20,101,11,11,color)
    c.rect(275,94,213,28,'#ffffff',7)
    c.text(292,99,'ChatGPT  ·  设计讨论',11)
    c.text(192,132,'‹     ›',14,SECONDARY)
    c.line([(259+5*math.cos(a),140+5*math.sin(a)) for a in [i*.18 for i in range(29)]],SECONDARY,1)
    c.line([(260,134),(264,135),(263,139)],SECONDARY,1)
    c.rect(283,128,835,24,'#e8ebee',6)
    c.text(302,131,'chatgpt.com/c/design-reference',11,SECONDARY)
    c.rect(170,159,190,616,'#f3f5f6')
    c.text(190,183,'ChatGPT',16)
    c.text(190,224,'＋ 新聊天',13)
    c.text(190,264,'今天',11,SECONDARY)
    c.rect(181,289,168,35,'#e4e9ec',7)
    c.text(191,297,'桌面界面的空间与节奏',12)
    c.text(191,340,'写作中的留白',12,SECONDARY)
    c.text(386,182,'ChatGPT',15)
    c.text(455,268,'让内容留在手边，',27)
    c.text(455,310,'让动作自然地发生。',27)
    c.text(455,374,'我们正在比较三个界面的比例与层次。',14,SECONDARY)
    c.text(455,404,'附件和草稿在这里保持原样；消息不会自动发送。',14,SECONDARY)
    c.rect(439,604,727,130,'#ffffff',18,stroke='#d9dfe3',width=.8)
    c.rect(455,617,62,38,'#e6e8ef',4)
    c.text(463,627,'已有附件',9,SECONDARY)
    c.text(455,672,'请帮我比较这两个版面的节奏。',14)
    c.text(455,706,'＋',20,SECONDARY)
    c.ellipse(1126,696,27,27,'#dce2e7')
    c.text(1133,697,'↑',17,SECONDARY)
    c.text(582,747,'此桌面、窗口、草稿和图片全部为原创合成设计素材。',10,SECONDARY)
    # Small system dock illustration, background only.
    c.rect(586,841,268,46,'#ecf0ed',12,opacity=.75,stroke='#f9fcfa',width=.7)
    for i,(label,color) in enumerate([('F','#75a4c8'),('N','#ddb966'),('S','#709dbb'),('C','#83a68b'),('R','#c1cad0'),('T','#c2c3bc')]):
        c.rect(597+i*41,850,29,29,color,7);c.text(606+i*41,853,label,15,'#ffffff')


def caption(c: Canvas, name: str, phase: str, time_ms: int, detail: str) -> None:
    c.text(40,800,name,20,INK)
    c.text(40,831,detail,12,SECONDARY)
    c.text(40,859,'设计模拟 · 非真实上传',12,INK)
    c.text(1015,812,phase,14,INK)
    c.text(1015,837,f'{time_ms:04d} ms  ·  60 fps  ·  100% 逻辑比例',11,SECONDARY)


def magnet(c: Canvas, t: float) -> dict:
    cycle=min(2,int(t/2.2));local=t-cycle*2.2-.70
    u=clamp(local/.56)
    phase='等待合成 assetReady'
    if local>=0:
        # The seam exists as soon as this asset has a visible queue identity.
        c.line([(EDGE,FIRST_Y-30.5),(EDGE,FIRST_Y+30.5)],LINE,.5,.57)
        sx,sy=840.0,350.0
        final_w,final_h=72.,45.
        if local<.123:
            p=out_cubic(local/.123);w=lerp(240,58,p);h=w/1.6;cx,cy=sx,sy
            phase='凝缩  0–123 ms'
            photo(c,cx-w/2,cy-h/2,w,h,clip_edge=EDGE)
        elif local<.224:
            p=(local-.123)/.101
            vx,vy=EDGE+36-sx,FIRST_Y-sy;length=math.hypot(vx,vy)
            oscillation=math.sin(p*math.tau*1.5)*math.sin(math.pi*p)*(1-p)*1.2
            cx,cy=sx+oscillation*vx/length,sy+oscillation*vy/length
            photo(c,cx-29,cy-18.125,58,36.25,clip_edge=EDGE)
            phase='定向微颤  123–224 ms'
        elif local<.484:
            p=(local-.224)/.260;q=p**2.25
            cx,cy=lerp(sx,EDGE+36,q),lerp(sy,FIRST_Y,q)
            w=lerp(58,final_w,q);h=w/1.6
            photo(c,cx-w/2,cy-h/2,w,h,clip_edge=EDGE)
            phase='连续加速  224–484 ms'
        else:
            p=out_cubic((local-.484)/.076)
            photo(c,EDGE-54*p,FIRST_Y-22.5,72,45,clip_edge=EDGE)
            phase='穿过固定边缘  484–560 ms' if local<.560 else '落位 · 可点击状态保持'
        # The fixed queue number is visible and actionable from assetReady,
        # independently of the decorative ghost's flight or occlusion progress.
        number(c,EDGE-54-8,FIRST_Y,1)
    caption(c,'01 / 磁力吸引',phase,round(max(0,local)*1000),f'原速重播 {cycle+1}/3 · assetReady 起固定编号即显即点；飞行副本不接鼠标。源坐标缺失时立即静态显示。')
    return {'cycle':cycle+1,'asset_time_ms':round(local*1000,3),'progress':u,'phase':phase}


def attachment(c: Canvas, index: int, progress: float, complete: bool) -> None:
    x=529+index*68
    photo(c,x,617,58,36.25,index)
    if not complete:
        c.rect(x,652,58,2,'#d4dbe1')
        c.rect(x,652,58*clamp(progress),2,ACCENT)


def swallow(c: Canvas,t: float) -> dict:
    starts=[1.60,3.50,5.40]
    clicks=[.70,2.60,4.50]
    completes=[2.60,4.50,6.40]
    rows=[]
    for i in range(3):
        if t>=starts[i]+.120:
            continue
        cy=FIRST_Y+i*PITCH
        for j in range(i):
            cy-=PITCH*out_cubic((t-(starts[j]+.120))/.160)
        offset=0.
        waiting=clicks[i]<=t<starts[i]
        if clicks[i]<=t<clicks[i]+.060:
            offset=1.5*out_cubic((t-clicks[i])/.060)
        elif clicks[i]+.060<=t<clicks[i]+.140:
            offset=1.5*(1-out_cubic((t-clicks[i]-.060)/.080))
        if t>=starts[i]:offset=56*clamp((t-starts[i])/.120)**1.35
        rows.append({'y':cy,'variant':i,'number':i-sum(t>=s+.280 for s in starts[:i])+1,
                     'waiting':waiting,'offset':offset,'number_visible':t<starts[i]})
    rift(c,rows)
    for i,s in enumerate(starts):
        if t>=s:attachment(c,i,(t-s)/(completes[i]-s),t>=completes[i])
    active=min(2,max(0,sum(t>=s+.280 for s in starts)))
    if t<6.1:
        pointer(c,1390,FIRST_Y,any(abs(t-v)<.08 for v in clicks))
    phase='原点击前 · 三张待用图片'
    detail='正文、选区与已有附件保留。以下时钟只驱动合成演示。'
    for i in range(3):
        if clicks[i]<=t<starts[i]:
            phase=f'{i+1} / 已接受点击，等待真实开始'
            detail='轻按反馈后复位；等待期间仍显示微图。没有 start 就不会吞噬。'
        elif starts[i]<=t<starts[i]+.120:
            phase=f'{i+1} / 模拟严格 uploadStarted → 120 ms'
            detail='只有原资产、原操作的开始事件触发快速遮挡；与入缝设置无关。'
        elif starts[i]+.120<=t<starts[i]+.280:
            phase=f'{i+1} / 剩余队列补位 160 ms'
            detail='先向固定边缘吞噬，再稳定补位。编号在补位完成后更新。'
        elif starts[i]+.280<=t<clicks[min(i+1,2)] and i<2:
            phase='后台独立确认附件内容'
            detail='完成仅后台记录；Riftlet不出现成功Toast。'
    if t>=5.52:
        phase='零可见图片 → 裂缝彻底消失'
        detail='最后一张仍在后台核对；界面消失不等于最终成功。'
    if t>=6.40:
        phase='最终完成：后台 succeeded / used'
        detail='ChatGPT草稿内附件完成；没有额外成功弹窗或自动发送。'
    caption(c,'02 / 严格开始后的快速吞噬',phase,round(t*1000),detail)
    return {'time_ms':round(t*1000,3),'visible_count':len(rows),'phase':phase,
            'starts_ms':[round(x*1000) for x in starts], 'completions_ms':[round(x*1000)for x in completes]}


def entry_pointer(t: float) -> tuple[float,float]:
    if t<1.0:
        p=smooth((t-.1)/.9);return lerp(630,ENTRY_X,p),lerp(510,ENTRY_Y,p)
    if t<2.1:return ENTRY_X,ENTRY_Y
    if t<4:return ENTRY_X,ENTRY_Y-32
    if t<5.6:return ENTRY_X,ENTRY_Y-64
    if t<6.4:return ENTRY_X+3,ENTRY_Y+2
    p=smooth((t-6.4)/1.0);return lerp(ENTRY_X+3,180,p),lerp(ENTRY_Y+2,590,p)


def optics_samples(frames: int) -> list[tuple[float,float]]:
    # Independent envelopes with the inherited 18/170 and 96/150 ms clocks.
    ga=sa=gm=sm=0.;out=[]
    for i in range(frames):
        t=i/FPS;px,py=entry_pointer(t);d=math.hypot(px-ENTRY_X,py-ENTRY_Y)
        def field(full,enter,exit=1):return 1-smooth((d-full*W)/(enter*W*exit-full*W))
        gm=max(field(.35,.60),min(gm,field(.35,.60,1.5)))
        sm=max(field(.08,.46),min(sm,field(.08,.46,1.5)))
        opened=1.1<=t<5.6
        g,s=(1.,1.)if opened else(gm,sm)
        dt=1000/FPS
        def step(v,goal,rise,fall,up,down):
            rising=goal>v
            delta=(goal-v)*(1-math.exp(-dt/(rise if rising else fall)))
            cap=up if rising else down
            return clamp(v+max(-cap,min(cap,delta)))
        ga=step(ga,g,18,170,.26,.08);sa=step(sa,s,96,150,.065,.06)
        out.append((ga,sa))
    return out


ENTRY_ALPHAS=optics_samples(round(8.4*FPS))


def capture_entry(c: Canvas,t: float) -> dict:
    expanded=1.1<=t<5.6
    if t<1.1:p=0
    elif t<1.28:p=smooth((t-1.1)/.18)
    elif t<5.6:p=1
    elif t<5.78:p=1-smooth((t-5.6)/.18)
    else:p=0
    cover=0
    if t>=2.1:cover=smooth((t-2.1)/.1)
    if t>=4:cover=1+smooth((t-4)/.1)
    ga,sa=ENTRY_ALPHAS[min(len(ENTRY_ALPHAS)-1,round(t*FPS))]
    entry(c,p,cover,ga,sa,expanded or p>0)
    rows=[]
    if t>=2.8:rows.append({'y':FIRST_Y,'variant':0,'number':1})
    if t>=4.6:rows.append({'y':FIRST_Y+PITCH,'variant':1,'number':2})
    rift(c,rows)
    px,py=entry_pointer(t);pointer(c,px,py,any(abs(t-v)<.075 for v in [1.1,2.1,4.,5.6]))
    if t<1.1:
        phase='线条先稳定，玻璃随后显现'
        detail='两个独立透明度通道；只有靠近时显现。无截图时无裂缝。'
    elif t<1.28:
        phase='180 ms 向上展开'
        detail='一个玻璃面，原入口不移动；点击不等待动画完成。'
    elif t<2.1:
        phase='默认窗口 · 原槽成为取消'
        detail='从下到上固定为窗口、区域、全屏、三点。'
    elif t<2.8:
        phase='100 ms 取消盖片迁移'
        detail='区域动作立即生效；窗口与全屏图标不交换位置。'
    elif t<4:
        phase='截图出现 · 仍保持区域会话'
        detail='成功截图不收回、不重排；可以继续截取或点击队列。'
    elif t<5.6:
        phase='全屏槽固定 · 连续捕获'
        detail='第二次截图后仍展开。三种模式一直可达。'
    elif t<6.4:
        phase='主动取消 → 回到原入口'
        detail='取消后附近仍显；不闪灭、不跳位。'
    else:
        phase='远离后渐隐 · 截图仍保留'
        detail='入口与队列分开：收回入口不会移除截图或更改上传状态。'
    caption(c,'03 / 预测式入口与固定槽位',phase,round(t*1000),detail)
    return {'time_ms':round(t*1000,3),'phase':phase,'expanded':expanded,'expansion':p,
            'cover_slot':cover,'glyph_alpha':ga,'glass_alpha':sa,'visible_count':len(rows)}


CLIPS={
    '01-magnetic-arrival':{'duration':6.6,'render':magnet,'stills':[.70,.823,.924,1.16,1.184,1.26]},
    '02-upload-start-swallow':{'duration':7.2,'render':swallow,'stills':[.40,1.20,1.65,1.90,5.60,6.60]},
    '03-predictive-entry':{'duration':8.4,'render':capture_entry,'stills':[.20,.80,1.28,2.15,3.20,4.90,5.85,7.80]},
}


def make_contact(name: str, images: list[tuple[Path,dict]]) -> Path:
    # Right-edge crops are preserved 1:1 at 320×520; no size-review zoom.
    count=len(images);cols=4;rows=math.ceil(count/cols)
    sheet=Image.new('RGB',(1440,95+rows*590),'#f4f6f6');d=ImageDraw.Draw(sheet)
    localfont=lambda size:ImageFont.truetype(str(FONT),size)
    d.text((30,20),name.replace('-',' '),font=localfont(22),fill=INK)
    d.text((30,55),'100% 逻辑尺寸右缘裁片 · 设计模拟 · 非真实上传 · 完整画面见同名 MP4 / SVG',font=localfont(13),fill=SECONDARY)
    for i,(path,meta) in enumerate(images):
        image=Image.open(path).convert('RGB');crop=image.crop((1120,48,1440,568))
        x=24+(i%cols)*354;y=96+(i//cols)*590
        sheet.paste(crop,(x,y));d.rectangle((x,y,x+320,y+520),outline='#d7dddf')
        d.text((x,y+528),f"{meta['sample_time_ms']:.1f} ms",font=localfont(13),fill=INK)
        phase=meta['phase']
        d.text((x,y+549),phase[:22],font=localfont(11),fill=SECONDARY)
    path=ROOT/f'{name}-contact-sheet.png';save_png(sheet,path)
    # Separate whole-desktop overview: deliberately labelled 31.7%, never used
    # to judge actual target size. The original PNG/SVG frames remain 1:1.
    overview=Image.new('RGB',(1440,95+math.ceil(count/3)*340),'#f4f6f6');od=ImageDraw.Draw(overview)
    od.text((30,20),name.replace('-',' ')+' / 全桌面时间线',font=localfont(22),fill=INK)
    od.text((30,55),'31.7%构图总览，不用于尺寸裁决 · 100%请打开 frames 中原图 · 设计模拟，非真实上传',font=localfont(13),fill=SECONDARY)
    for i,(frame,meta) in enumerate(images):
        thumb=Image.open(frame).convert('RGB').resize((456,285),Image.Resampling.LANCZOS)
        x=20+(i%3)*480;y=95+(i//3)*340;overview.paste(thumb,(x,y))
        od.text((x,y+290),f"{meta['sample_time_ms']:.1f} ms  /  {meta['phase']}",font=localfont(11),fill=INK)
    save_png(overview,ROOT/f'{name}-overview.png')
    return path


def main() -> None:
    parser=argparse.ArgumentParser();parser.add_argument('--stills-only',action='store_true');parser.add_argument('--clip',choices=list(CLIPS));args=parser.parse_args()
    ROOT.mkdir(parents=True,exist_ok=True)
    run_lock=(ROOT/'.render.lock').open('w')
    fcntl.flock(run_lock,fcntl.LOCK_EX | fcntl.LOCK_NB)
    (ROOT/'frames').mkdir(exist_ok=True)
    base_canvas=Canvas();base(base_canvas);back=base_canvas.image
    results=[]
    for name,config in CLIPS.items():
        if args.clip and args.clip!=name:continue
        print(f'Rendering {name}',flush=True)
        frames=[]
        for index,at in enumerate(config['stills']):
            canvas=Canvas(svg=True);base(canvas);meta=config['render'](canvas,at)
            meta.update(sample_time_ms=round(at*1000,3),is_synthetic=True)
            stem=f'{name}-{index+1:02d}'
            path=ROOT/'frames'/f'{stem}.png';save_png(canvas.snapshot(),path)
            (ROOT/'frames'/f'{stem}.svg').write_text(canvas.svg(),encoding='utf-8')
            frames.append((path,meta))
        contact=make_contact(name,frames)
        info={'name':name,'duration_seconds':config['duration'],'fps':FPS,'width':W,'height':H,
              'expected_frames':round(config['duration']*FPS),'stills':[x[1]for x in frames],
              'contact_sheet':contact.name,'synthetic':True,
              'renderer_sha256_at_render':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        if not args.stills_only:
            output=ROOT/f'{name}.mp4'
            temporary_output=ROOT/f'{name}.partial.mp4'
            cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-f','rawvideo','-vcodec','rawvideo',
                 '-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264',
                 '-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(temporary_output)]
            process=subprocess.Popen(cmd,stdin=subprocess.PIPE)
            for frame in range(info['expected_frames']):
                canvas=Canvas(back);config['render'](canvas,frame/FPS)
                process.stdin.write(canvas.snapshot().tobytes())
            process.stdin.close()
            if process.wait()!=0:raise RuntimeError('ffmpeg failed')
            temporary_output.replace(output)
            measured=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-select_streams','v:0',
                '-show_entries','stream=codec_name,width,height,r_frame_rate,nb_read_frames,duration','-of','json',str(output)]))['streams'][0]
            assert measured['width']==W and measured['height']==H
            assert measured['r_frame_rate']=='60/1'
            assert int(measured['nb_read_frames'])==info['expected_frames']
            info['measured']=measured
            info['sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
            info['bytes']=output.stat().st_size
        results.append(info)
        print(f'Finished {name}',flush=True)
    path=ROOT/('verification-stills.json'if args.stills_only else'verification.json')
    if args.clip and path.exists():
        previous=json.loads(path.read_text(encoding='utf-8'))
        indexed={x['name']:x for x in previous.get('clips',[])}
        for item in indexed.values():
            item.setdefault('renderer_sha256_at_render',previous.get('renderer_sha256'))
        indexed.update({x['name']:x for x in results})
        results=[indexed[name]for name in CLIPS if name in indexed]
    manifest={'renderer':'render-motion.py','renderer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'logical_size':[W,H],'raster_scale':1,'working_supersampling':SCALE,
        'font_used':FONT.name,'generated_from':'original geometric fixture, no screen capture','clips':results,
        'boundaries':{'native_acceptance':False,'real_capture':False,'real_upload':False,'timings_are_design_recommendations':True}}
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    run_lock.close()
    (ROOT/'.render.lock').unlink(missing_ok=True)
    print(path,flush=True)


if __name__=='__main__':main()
