#!/usr/bin/env python3
"""Editable synthetic desktop/native-window review boards. No App or real capture.

Python standard library creates vector SVG; Inkscape creates 1 px : 1 logical pt
review PNGs. Font binaries are not distributed. Native implementation uses SF /
system fonts; this Linux rendering uses Noto Sans CJK SC + DejaVu Sans.
"""
from pathlib import Path
import argparse, hashlib, html, json, math, os, re, subprocess

HERE = Path(__file__).resolve().parent
OUT = HERE / 'outputs'
OUT.mkdir(parents=True, exist_ok=True)
REPO = HERE.parents[2]
SOURCE = '1920e0562db893a3292af89a89270a26ddb46a5f'
MAIN = 'eba1a4fc77648a665e1d5c1f2609df1314c3b079'
LOGO_BYTES = subprocess.check_output(['git','show',f'{MAIN}:favicon.svg'],cwd=REPO)
LOGO = LOGO_BYTES.decode('utf-8').strip()
FONT = "'Noto Sans CJK SC','DejaVu Sans',sans-serif"
SEQ = 0
LIGHT = dict(bg='#F7F9F8',panel='#FFFFFF',text='#172521',sub='#65716B',accent='#087F73',
             border='#DCE4DF',soft='#EDF2EF',tint='#E1F2EA',glass='#F5F8F5')
DARK = dict(bg='#171E1C',panel='#222B27',text='#EEF4F0',sub='#A9B6AE',accent='#58CDB8',
            border='#3A4740',soft='#2B3630',tint='#24483D',glass='#2A3630')

def uid():
    global SEQ
    SEQ += 1
    return f'v{SEQ}'

def esc(s): return html.escape(str(s))

def rect(x,y,w,h,fill,rx=0,stroke=None,sw=1,opacity=1):
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{fill}" opacity="{opacity:g}"'+(f' stroke="{stroke}" stroke-width="{sw:g}"' if stroke else '')+'/>'

def line(x1,y1,x2,y2,col,sw=1,opacity=1):
    return f'<path d="M{x1:g} {y1:g}H{x2:g}" fill="none" stroke="{col}" stroke-width="{sw:g}" opacity="{opacity:g}"/>' if y1==y2 else f'<path d="M{x1:g} {y1:g}L{x2:g} {y2:g}" fill="none" stroke="{col}" stroke-width="{sw:g}" opacity="{opacity:g}"/>'

def text(x,y,s,size=13,col='#172521',weight=400,anchor='start',opacity=1):
    return f'<text x="{x:g}" y="{y:g}" font-family="{FONT}" font-size="{size:g}" font-weight="{weight}" fill="{col}" text-anchor="{anchor}" opacity="{opacity:g}">{esc(s)}</text>'

def dot(x,y,r,col,opacity=1):
    return f'<circle cx="{x:g}" cy="{y:g}" r="{r:g}" fill="{col}" opacity="{opacity:g}"/>'

def logo(x,y,size):
    return re.sub(r'<svg[^>]*>',f'<svg x="{x:g}" y="{y:g}" width="{size:g}" height="{size:g}" viewBox="0 0 112 112">',LOGO,count=1)

def icon(name,cx,cy,size=16,col='#172521',sw=1.4):
    paths={
      'camera':'M3 7h4l2-3h6l2 3h4v13H3Z M16 13a4 4 0 1 1-8 0a4 4 0 0 1 8 0',
      'window':'M3 5h18v14H3Z M3 9h18 M6 7h.01 M9 7h.01',
      'region':'M3 8V3h5 M16 3h5v5 M21 16v5h-5 M8 21H3v-5 M8 8h8v8H8Z',
      'full':'M3 8V3h5 M16 3h5v5 M21 16v5h-5 M8 21H3v-5',
      'x':'M6 6l12 12 M18 6L6 18',
      'check':'M4 12l5 5L20 6',
      'down':'M6 9l6 6l6-6',
      'left':'M15 5l-7 7l7 7',
      'right':'M9 5l7 7l-7 7',
      'search':'M16 10a6 6 0 1 1-12 0a6 6 0 0 1 12 0 M15 15l6 6',
      'folder':'M3 7V5h7l2 3h9v12H3Z',
      'pause':'M8 5v14 M16 5v14',
      'eye':'M2 12c5-9 15-9 20 0c-5 9-15 9-20 0Z M15 12a3 3 0 1 1-6 0a3 3 0 0 1 6 0',
      'clock':'M21 12a9 9 0 1 1-18 0a9 9 0 0 1 18 0 M12 7v6l4 2',
      'arrow':'M12 19V5 M6 11l6-6l6 6',
      'plus':'M12 4v16 M4 12h16',
      'bubble':'M3 4h18v13H8l-5 4Z',
      'shield':'M12 3l8 4v6c0 4-5 7-8 9c-3-2-8-5-8-9V7Z',
      'settings':'M4 7h16 M4 17h16 M8 4v6 M16 14v6',
      'share':'M12 16V3 M8 7l4-4l4 4 M5 11v10h14V11',
    }
    if name=='more':
        return ''.join(dot(cx+d,cy,1.1,col) for d in [-4,0,4])
    return f'<g transform="translate({cx-size/2:g} {cy-size/2:g}) scale({size/24:g})"><path d="{paths.get(name,paths["window"])}" fill="none" stroke="{col}" stroke-width="{sw*24/size:g}" stroke-linecap="round" stroke-linejoin="round"/></g>'

def button(x,y,w,label,T,primary=False,disabled=False,h=28):
    fill=T['accent'] if primary else T['panel']
    foreground='#FFFFFF' if primary else T['text']
    if T is DARK and primary: foreground='#10271F'
    if disabled: fill=T['soft']; foreground=T['sub']
    return rect(x,y,w,h,fill,6,None if primary else T['border'])+text(x+w/2,y+h/2+4,label,12,foreground,500,'middle')

def pill(x,y,label,T,kind='neutral'):
    width=max(54,len(label)*11+20)
    fill=T['tint'] if kind=='accent' else T['soft']
    col=T['accent'] if kind=='accent' else T['sub']
    return rect(x,y,width,22,fill,5)+text(x+width/2,y+15,label,11,col,400,'middle')

def toggle(x,y,on,T):
    return rect(x,y,30,18,T['accent'] if on else T['border'],9)+dot(x+(21 if on else 9),y+9,7,'#FFFFFF')

def asset(kind,x,y,w,h):
    """Source-proportional synthetic content, all vector, never a colored card placeholder."""
    kinds=['architecture','editorial','chart','tall','wide','plan','photo','notes']
    kind=kinds[kind%len(kinds)] if isinstance(kind,int) else kind
    dims={'architecture':(1440,900),'editorial':(900,1200),'chart':(1600,900),'tall':(280,2240),'wide':(2400,300),'plan':(1000,1000),'photo':(900,1200),'notes':(1400,900)}
    sw,sh=dims[kind]
    s=[]
    if kind=='architecture':
        s+=[rect(0,0,sw,sh,'#D8E3DE'),rect(0,560,sw,340,'#AEBAB0'),rect(140,220,1160,410,'#D9C9AF'),rect(260,315,220,315,'#B2A18A'),rect(520,250,360,380,'#EFE6D3'),rect(930,340,250,290,'#766A58')]
        s += [f'<path d="M520 630V410a180 180 0 0 1 360 0v220Z" fill="#485A50"/>',rect(580,420,240,210,'#263E34')]
        s += [f'<path d="M0 900L520 630H880l560 270Z" fill="#D9CCB6"/>',f'<path d="M140 220L520 250v380H140Z" fill="#C8B899"/>']
        for i in range(7): s.append(line(0,670+i*32,1440,670+i*32,'#89988A',4,.3))
        s+=[dot(1270,575,90,'#6C7D60'),rect(1260,590,12,125,'#5E6650')]
    elif kind=='editorial':
        s+=[rect(0,0,sw,sh,'#F2EEE4'),text(70,108,'FORM / FIELD',36,'#293B34',500),line(70,145,830,145,'#6B7E6E',3),text(70,260,'Light, held',92,'#253D31',500),text(70,360,'in a room.',92,'#253D31',500)]
        s+=[rect(70,430,760,440,'#B3C0AB'),f'<path d="M70 870V550l300-120l460 440Z" fill="#D4C3A4"/>',rect(410,480,220,390,'#6F7763'),f'<path d="M410 480L630 600V870H410Z" fill="#3C5045"/>']
        for i,a in enumerate([690,700,605,650,510]): s.append(rect(70,945+i*35,a,9,'#778175'))
        s.append(text(70,1150,'07     SPACES FOR LIVING',24,'#596B60'))
    elif kind=='chart':
        s+=[rect(0,0,sw,sh,'#F8FAF8'),text(100,120,'A quieter rhythm',55,'#203C31',500),text(100,175,'Weekly focus · October',28,'#728176')]
        for i in range(5): s.append(line(140,280+i*100,1480,280+i*100,'#DCE5DF',3))
        vals=[480,520,445,530,360,400,310,420,265,320,225]
        pts=' '.join(f'{140+i*130},{v}' for i,v in enumerate(vals))
        s+=[f'<polygon points="140,680 {pts} 1440,680" fill="#D4E9DF"/>',f'<polyline points="{pts}" fill="none" stroke="#397E6B" stroke-width="7" stroke-linejoin="round"/>']
        for i,n in enumerate(['MON','TUE','WED','THU','FRI']): s.append(text(140+i*320,755,n,25,'#68796E'))
        s.append(text(100,840,'24.6 h',55,'#244A3B',500))
    elif kind=='tall':
        s+=[rect(0,0,sw,sh,'#F3F0E7'),text(22,65,'FIELD NOTES',23,'#24483D',500)]
        for j in range(7):
            yy=120+j*295
            s+=[rect(22,yy,236,125,['#ADC6B6','#C8BAA0','#A9B9C5'][j%3]),text(22,yy+165,f'0{j+1}  Observation',16,'#294638')]
            for k in range(4): s.append(rect(22,yy+190+k*17,220-(k%3)*28,4,'#88988A'))
    elif kind=='wide':
        s.append(rect(0,0,sw,sh,'#EDF4F0'))
        for j in range(9):
            xx=40+j*265
            s+=[rect(xx,40,225,185,['#CADFD2','#E4D8C4','#C9D8DF'][j%3],12),text(xx+18,88,f'0{j+1}',25,'#436452')]
            s.append(line(xx+18,135,xx+190,135,'#70877A',5))
            s.append(line(xx+18,164,xx+155,164,'#70877A',4))
    elif kind=='plan':
        s.append(rect(0,0,sw,sh,'#F3F1E9'))
        for x1,y1,x2,y2 in [(120,120,850,120),(850,120,850,850),(850,850,120,850),(120,850,120,120),(450,120,450,620),(120,620,850,620),(650,620,650,850)]: s.append(line(x1,y1,x2,y2,'#778376',11))
        s+=[rect(500,210,270,160,'#D4DFD3'),rect(175,215,210,260,'#C6D4C9'),rect(200,700,320,80,'#DBCAB4'),dot(650,480,75,'#D9C8AE'),text(120,950,'COURTYARD / 02',28,'#687A6C')]
    elif kind=='photo':
        s+=[rect(0,0,sw,sh,'#D3DCCD'),rect(0,600,sw,600,'#9EAD9A'),rect(160,120,570,910,'#E1D7C1'),rect(260,230,360,800,'#8F9B85')]
        s+=[f'<path d="M260 1030V450a180 180 0 0 1 360 0v580Z" fill="#3B5747"/>',f'<path d="M160 120L260 230V1030H160Z" fill="#BAAC91"/>',rect(400,720,110,310,'#B1BDA8'),dot(680,930,140,'#839472')]
    else:
        s+=[rect(0,0,sw,sh,'#F7F8F3'),text(100,130,'Notes on the everyday',54,'#2D4536',500),text(100,200,'Small choices make a calmer space.',27,'#6A7C6E')]
        for j in range(8):
            s += [dot(110,290+j*60,6,'#7FAD98'),rect(145,280+j*60,930-(j%3)*120,13,'#ACB9AE')]
        s += [rect(100,810,300,8,'#38826A')]
    return f'<svg x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" viewBox="0 0 {sw} {sh}" preserveAspectRatio="none">'+''.join(s)+'</svg>'

ASPECTS=[(1440,900),(900,1200),(1600,900),(280,2240),(2400,300),(1000,1000),(900,1200),(1400,900)]

def thumb(n,plane,cy,T,waiting=False):
    aw,ah=ASPECTS[(n-1)%8]; scale=min(72/aw,56/ah); w,h=aw*scale,ah*scale; vis=w*.75
    left=plane-vis; top=cy-h/2; cid=uid()
    extreme=vis<24 or h<20
    q=[f'<defs><clipPath id="{cid}">{rect(left,top,vis,h,"#fff")}</clipPath></defs>',f'<g clip-path="url(#{cid})">',asset((n-1)%8,left,top,w,h),'</g>']
    if extreme:
        q += [rect(left-30,cy-12,22,24,T['glass'],5,T['border'],.6,.98),text(left-19,cy+4,str(n),11,T['sub'],400,'middle')]
    else:q += [text(left-8,cy+4,str(n),11,T['sub'],400,'end')]
    if waiting:q += [line(left-16,cy+9,left-8,cy+9,T['accent'],1)]
    return ''.join(q)

def rift(W,H,T,count=3,start=1,entry=True,expanded=False,waiting=False,active='region'):
    plane=W-14; bottom=H-88; first=230; cap=max(1,math.floor((bottom-28-first)/60)+1)
    overflow=count>cap
    if overflow:cap=max(1,math.floor((bottom-28-28-first)/60)+1)
    showing=min(count,cap); s=[]
    if showing:
        s.append(line(plane,first-36,plane,first+(showing-1)*60+36,'#182821' if T is LIGHT else '#E0EDE2',.5,.62 if T is LIGHT else .28))
        s += [thumb(start+i,plane,first+i*60,T,waiting and i==0) for i in range(showing)]
        if overflow:
            py=first+(showing-1)*60+28+8
            s += [rect(plane-65,py,65,20,T['glass'],6,T['border'],.6),icon('left',plane-54,py+10,10,T['sub']),text(plane-32,py+14,f'{start}–{start+showing-1}',9,T['sub'],400,'middle'),icon('right',plane-10,py+10,10,T['sub'])]
    if entry:
        cx=W-32; cy=164; eh=132 if expanded else 36; top=cy+18-eh
        s += [rect(cx-18,top+2,36,eh,T['text'],12,opacity=.045),rect(cx-18,top,36,eh,T['glass'],12 if expanded else 10,T['border'],.75,.94)]
        if expanded:
            # Default window mapping: base window, near region, far full, top more.
            slots=[('window',164),('region',132),('full',100),('more',68)]
            for name,y in slots:
                if name==active:s += [rect(cx-15,y-15,30,30,T['tint'],8),icon('x',cx,y,16,T['text'])]
                else:s.append(icon(name,cx,y,16,T['text']))
        else:s.append(icon('camera',cx,cy,16,T['text']))
    return ''.join(s)

def wallpaper(W,H,T,warm=False):
    g=uid(); cols=('#DFE8E0','#EAECE1','#C7D8CA') if T is LIGHT else ('#1A2923','#29362F','#485244')
    if warm:cols=('#E7E2D8','#ECE9E1','#C8D0C3')
    return f'<defs><linearGradient id="{g}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="{cols[0]}"/><stop offset=".55" stop-color="{cols[1]}"/><stop offset="1" stop-color="{cols[2]}"/></linearGradient></defs>'+rect(0,0,W,H,f'url(#{g})')+f'<path d="M{W*.40:g} {H:g}L{W*.82:g} 24H{W:g}V{H:g}Z" fill="{T["panel"]}" opacity=".10"/>'

def menubar(W,T,app='Chrome'):
    s=[rect(0,0,W,25,T['panel'],opacity=.55),text(20,17,app,12,T['text'],600)]
    x=98 if app=='Chrome' else 75
    for label in ['文件','编辑','显示','窗口','帮助']:
        s.append(text(x,17,label,11,T['text']));x+=44
    s += [icon('settings',W-235,12,12,T['text']),rect(W-208,7,22,10,'none',2,T['text'],1),rect(W-205,9,16,6,T['text'],1),rect(W-184,10,2,4,T['text'],1),text(W-16,17,'周三  22:36',11,T['text'],400,'end')]
    return ''.join(s)

def dock(W,H,T):
    x=W/2-146;y=H-64;s=[rect(x,y,292,51,T['glass'],14,T['border'],.7,.86)]
    names=['folder','bubble','window','clock','settings']
    colors=['#87B8CD','#6EAB92','#C7B490','#B7A3C3','#A9B3AC']
    for i,name in enumerate(names):
        bx=x+12+i*45;s += [rect(bx,y+8,34,34,colors[i],9),icon(name,bx+17,y+25,20,'#FFFFFF',1.5)]
    s += [line(x+240,y+12,x+240,y+38,T['sub'],.8,.3),logo(x+250,y+8,34)]
    return ''.join(s)

def chrome(x,y,w,h,T,draft=True):
    clip=uid(); sidebar=190;s=[rect(x,y+7,w,h,'#15281E',12,opacity=.08),rect(x,y,w,h,T['panel'],10,T['border'],.7),f'<defs><clipPath id="{clip}">{rect(x,y,w,h,"white",10)}</clipPath></defs><g clip-path="url(#{clip})">',rect(x,y,w,76,T['soft'])]
    for i,c in enumerate(['#ED7167','#E6BD56','#6BBE7C']):s.append(dot(x+20+i*18,y+18,5,c))
    s += [rect(x+88,y+9,220,26,T['panel'],7),text(x+106,y+27,'ChatGPT',12,T['text']),icon('x',x+290,y+22,9,T['sub']),icon('left',x+21,y+56,12,T['sub']),icon('right',x+48,y+56,12,T['sub']),rect(x+80,y+42,w-136,26,T['panel'],6),text(x+w/2,y+60,'chatgpt.com',11,T['sub'],400,'middle')]
    s += [rect(x,y+76,sidebar,h-76,T['bg']),text(x+20,y+112,'ChatGPT',15,T['text'],600),icon('plus',x+165,y+108,16,T['sub']),text(x+20,y+154,'新聊天',12,T['sub']),text(x+20,y+188,'搜索聊天',12,T['sub']),text(x+20,y+222,'资料库',12,T['sub']),text(x+20,y+277,'今天',10,T['sub']),rect(x+10,y+291,170,34,T['soft'],6),text(x+20,y+313,'空间与日常',12,T['text']),text(x+20,y+352,'一段安静的工作时间',12,T['sub']),text(x+20,y+392,'产品体验笔记',12,T['sub'])]
    cx=x+sidebar+36;cw=w-sidebar-72
    s += [text(cx,y+111,'ChatGPT',15,T['text'],500),icon('down',cx+79,y+106,11,T['sub']),icon('share',x+w-60,y+106,16,T['sub']),icon('more',x+w-28,y+106,16,T['sub'])]
    # Intentionally synthetic conversation, clear content density at desktop scale.
    bodyx=cx+max(10,(cw-650)/2);bw=min(cw-20,650)
    s += [rect(bodyx+110,y+161,bw-110,57,T['soft'],18),text(bodyx+128,y+185,'我在整理一个小型庭院的参考。',13,T['text']),text(bodyx+128,y+205,'想保留自然材料，也想让光线成为空间的一部分。',13,T['text'])]
    s += [text(bodyx,y+270,'先看光线，再看形状。',21,T['text'],500),text(bodyx,y+306,'这几张图共有的不是一种风格，而是对留白的处理：',13,T['text'])]
    for j,(title,body) in enumerate([('边界更轻','用材料的衔接表达空间，不需要额外的装饰轮廓。'),('节奏更慢','保留大片平面，让少量明暗变化有足够的余地。'),('细节更近','把手会接触的位置做好，让日常动作自然发生。')]):
        yy=y+350+j*62;s += [text(bodyx,yy,f'0{j+1}',11,T['sub']),text(bodyx+30,yy,title,13,T['text'],500),text(bodyx+30,yy+22,body,12,T['sub'])]
    if draft:
        dy=y+h-132;s += [rect(bodyx-10,dy,bw+20,108,T['bg'],20,T['border'],.8),asset(0,bodyx+5,dy+12,58,36),text(bodyx+76,dy+34,'庭院参考.png',11,T['sub']),text(bodyx+8,dy+69,'把这两张图的光线与构图放在一起比较。',13,T['text']),icon('plus',bodyx+10,dy+91,16,T['sub']),dot(bodyx+bw-14,dy+86,14,T['text']),icon('arrow',bodyx+bw-14,dy+86,14,T['panel'])]
    s.append('</g>');return ''.join(s)

def notes(x,y,w,h,T):
    s=[rect(x,y+7,w,h,'#000000',12,opacity=.08),rect(x,y,w,h,T['panel'],10,T['border'],.7),rect(x,y,w,40,T['soft'],10),rect(x,y+31,w,9,T['soft'])]
    for i,c in enumerate(['#ED7167','#E6BD56','#6BBE7C']):s.append(dot(x+20+i*18,y+20,5,c))
    s += [text(x+w/2,y+25,'日常观察',12,T['sub'],400,'middle'),rect(x,y+40,190,h-40,T['bg']),text(x+20,y+82,'我的笔记',13,T['text'],500),rect(x+10,y+106,170,58,T['soft'],7),text(x+22,y+129,'留白与边界',12,T['text'],500),text(x+22,y+149,'今天 22:28',10,T['sub']),text(x+22,y+196,'材料的触感',12,T['sub']),text(x+22,y+234,'十月的阅读',12,T['sub'])]
    bx=x+224;s += [text(bx,y+100,'留白与边界',25,T['text'],500),text(bx,y+132,'October 28 · Notes from a working day',11,T['sub'])]
    lines=['好的工具，让注意力停留在正在做的事情上。','','有时需要的并不是更多信息，','而是让已经看见的东西，暂时留在手边。','','一条细线，一张图，一次自然的动作。','当它完成自己的任务，就安静地退场。']
    for i,st in enumerate(lines):s.append(text(bx,y+184+i*27,st,14,T['text']))
    s += [line(bx,y+414,x+w-34,y+414,T['border']),text(bx,y+448,'留给下一次观察',12,T['sub'])]
    return ''.join(s)

def finder(x,y,w,h,T):
    s=[rect(x,y+7,w,h,'#15281E',12,opacity=.08),rect(x,y,w,h,T['panel'],10,T['border'],.7),rect(x,y,w,43,T['soft'],10),rect(x,y+32,w,11,T['soft'])]
    for i,c in enumerate(['#ED7167','#E6BD56','#6BBE7C']):s.append(dot(x+20+i*18,y+21,5,c))
    s += [text(x+170,y+27,'参考资料',13,T['text'],500),icon('search',x+w-25,y+22,14,T['sub']),rect(x,y+43,150,h-43,T['bg']),text(x+18,y+78,'个人收藏',10,T['sub']),rect(x+8,y+95,134,30,T['tint'],6),text(x+35,y+116,'桌面',12,T['text']),text(x+35,y+152,'文稿',12,T['sub']),text(x+35,y+188,'下载',12,T['sub']),text(x+35,y+224,'截图',12,T['sub'])]
    for j,(label,ar) in enumerate([('courtyard',0),('light-study',1),('weekly-notes',2),('floor-plan',5),('field-notes',3),('material-map',6)]):
        xx=x+180+(j%3)*132;yy=y+76+(j//3)*155
        aw,ah=ASPECTS[ar];sc=min(102/aw,88/ah);tw,th=aw*sc,ah*sc
        s += [asset(ar,xx+(102-tw)/2,yy,tw,th),text(xx+51,yy+108,label,11,T['text'],400,'middle'),text(xx+51,yy+125,'PNG 图像',9,T['sub'],400,'middle')]
    s += [line(x+150,y+h-29,x+w,y+h-29,T['border']),text(x+165,y+h-10,'6 项',10,T['sub'])]
    return ''.join(s)

def native_icon(name,cx,cy,size=16,col='#172521',sw=1.4):
    # Same 20-unit glyph paths as prototype/windows.js, kept separate from desktop reconstruction icons.
    paths={
      'general':'<path d="M3 6h14M3 14h14M7 3v6M13 11v6"/>',
      'capture':'<path d="M3 6h4l2-2h4l2 2h2v11H3z"/><circle cx="10" cy="11" r="3"/>',
      'display':'<path d="M4 2v16M7 4h10v11H7z"/>',
      'privacy':'<path d="M10 2 3 5v5c0 4 7 8 7 8s7-4 7-8V5z"/><path d="m7 10 2 2 4-5"/>',
      'about':'<circle cx="10" cy="10" r="8"/><path d="M10 9v6M10 5v1"/>',
      'folder':'<path d="M2 5h6l2 2h8v10H2z"/>',
      'chrome':'<circle cx="10" cy="10" r="8"/><circle cx="10" cy="10" r="3"/><path d="m10 7 7 0M7 10 4 4M12 13 8 18"/>',
      'check':'<path d="m4 10 4 4 8-9"/>',
      'image':'<rect x="2" y="3" width="16" height="14" rx="2"/><circle cx="7" cy="8" r="1"/><path d="m3 15 5-4 3 2 3-5 3 7"/>',
      'clock':'<circle cx="10" cy="10" r="8"/><path d="M10 5v6l4 2"/>',
      'archive':'<path d="M3 6h14v12H3zM2 2h16v4H2zM8 10h4"/>',
      'removed':'<path d="M3 5h14M8 2h4M5 5l1 13h8l1-13M8 8v7M12 8v7"/>',
      'chevron':'<path d="m8 5 5 5-5 5"/>',
    }
    return f'<g transform="translate({cx-size/2:g} {cy-size/2:g}) scale({size/20:g})" fill="none" stroke="{col}" stroke-width="{sw*20/size:g}" stroke-linecap="round" stroke-linejoin="round">{paths[name]}</g>'

def native_frame(w,h,T,title,content,label='Riftlet'):
    cid=uid()
    s=[f'<defs><clipPath id="{cid}">{rect(0,0,w,h,"white",12)}</clipPath></defs>',f'<g clip-path="url(#{cid})">',rect(0,0,w,h,T['bg']),rect(0,0,w,44,T['bg']),line(0,44,w,44,T['border'],.6)]
    for i,c in enumerate(['#ED7167','#E6BD56','#6BBE7C']):s.append(dot(20+i*18,22,5,c))
    s += [text(w/2,27,title,12,T['sub'],500,'middle'),text(w-16,27,label,10,T['sub'],400,'end'),content,'</g>',rect(0,0,w,h,'none',12,T['border'],.8)]
    return ''.join(s)

def setup_window(T):
    # Faithful reconstruction of prototype/windows.js setup(state.onboardingStep=1).
    w,h=560,520;s=[]
    for i,(xx,label) in enumerate([(28,'认识 Riftlet'),(208,'连接与权限'),(400,'开始使用')]):
        current=i==1;done=i==0
        s += [dot(xx+8.5,75,8.5,T['accent'] if current else T['tint'] if done else T['bg'])]
        if not (current or done):s.append(f'<circle cx="{xx+8.5}" cy="75" r="8.5" fill="none" stroke="{T["border"]}" stroke-width="1"/>')
        if done:s.append(native_icon('check',xx+8.5,75,10,T['accent'],1))
        else:s.append(text(xx+8.5,78,str(i+1),10,T['panel'] if current else T['sub'],500,'middle'))
        s.append(text(xx+23,79,label,11,T['accent'] if current else T['sub']))
    s += [text(28,134,'连接你已经在用的工具',20,T['text'],500),text(28,165,'只在你主动操作时请求权限。',13,T['sub'])]
    rows=[('folder','系统截图位置','已连接当前截图位置（模拟）','桌面 · 本机保存','已连接',True),('chrome','Chrome 中的当前草稿','允许自动化连接，再由原点击核实目标。','还需允许来自 Apple 事件的 JavaScript','连接 Chrome…',False)]
    for i,(ic,title,sub,detail,btn,disabled_) in enumerate(rows):
        yy=188+i*104;s += [rect(28,yy,504,90,T['panel'],8,T['border'],.6),native_icon(ic,55,yy+37,23,T['accent']),text(82,yy+29,title,13,T['text'],500),text(82,yy+50,sub,11,T['sub']),text(82,yy+70,detail,10,T['sub']),button(411,yy+31,105,btn,T,disabled=disabled_)]
    s += [native_icon('about',36,409,16,T['sub']),text(53,412,'权限允许不等于页面已经可用。没有可验证的当前草稿时，',11,T['sub']),text(53,429,'图片会留在原处。',11,T['sub']),line(0,456,w,456,T['border'],.5),text(24,490,'权限在此原型中仅作模拟。',11,T['sub']),text(370,490,'稍后设置',12,T['sub'],400,'middle'),button(436,473,100,'下一步',T,True,h=30)]
    return native_frame(w,h,T,'开始使用',''.join(s),'内部候选')

def settings_window(T):
    # Same five-page navigation and display panel as windows.js; no extra archive row here.
    w,h=680,520;s=[rect(0,44,156,476,T['glass']),line(156,44,156,h,T['border'],.5),text(20,80,'Riftlet',16,T['text'],600),text(20,101,'让截图停在手边',10,T['sub'])]
    nav=[('运行状态','general'),('截图入口','capture'),('显示与动效','display'),('隐私与存储','privacy'),('关于与支持','about')]
    for i,(label,ico) in enumerate(nav):
        yy=122+i*39
        if i==2:s.append(rect(9,yy,138,36,T['tint'],6))
        s += [native_icon(ico,28,yy+18,16,T['accent'] if i==2 else T['sub']),text(45,yy+23,label,12,T['accent'] if i==2 else T['text'])]
    s += [dot(20,497,2,T['accent']),text(28,501,'内部候选 · 设计模拟',10,T['sub'])]
    x=180;s += [text(x,88,'显示与动效',20,T['text'],500),text(x,116,'动效只解释物体去哪里，不抢走注意力。',13,T['sub']),text(x,153,'截图入缝',13,T['text'],500)]
    for i,(lab,caption) in enumerate([('无','直接出现在裂缝中'),('磁力吸引','从源头收束，轻轻入缝')]):
        xx=x+i*243;sel=i==1
        s += [rect(xx,166,233,102,T['panel'],8,T['accent'] if sel else T['border'],1),line(xx+60,181,xx+60,215,T['sub'],.5,.6),rect(xx+(21 if sel else 36),189,24,21,'#87BAA7' if sel else '#AECBB9',1),text(xx+14,237,lab,12,T['text'],500),text(xx+14,257,caption,10,T['sub'])]
        s.append(f'<circle cx="{xx+218}" cy="181" r="6" fill="none" stroke="{T["accent"] if sel else T["sub"]}" stroke-width="1"/>')
        if sel:s.append(dot(xx+218,181,3,T['accent']))
        if sel:s.append(line(xx+47,199,xx+56,199,T['sub'],.7,.5))
    s += [text(x+1,289,'仅影响截图来到裂缝的过程。上传开始后的快速吞噬独立保留。',11,T['sub'])]
    s.append(rect(x,306,476,196,T['panel'],8,T['border'],.8))
    rows=[('外观','与桌面和窗口保持一致。','theme'),('减少动态效果','取消空间位移，以短淡变表达状态。','reduce'),('减少透明度','使用清晰、不透明的表面。','opaque'),('提高对比度','强化边界与文字。','contrast')]
    for i,(title,desc,kind) in enumerate(rows):
        yy=306+i*49
        if i:s.append(line(x+13,yy,x+463,yy,T['border'],.5))
        s += [text(x+13,yy+20,title,13,T['text']),text(x+13,yy+39,desc,11,T['sub'])]
        if kind=='theme':s += [button(x+370,yy+10,92,'浅色',T),icon('down',x+448,yy+24,9,T['sub'])]
        else:s.append(toggle(x+432,yy+16,False,T))
    return native_frame(w,h,T,'设置与运行状态',''.join(s))

def history_window(T,unknown=True):
    # 152 / 260 / 348 columns, direct counterpart of windows.js history().
    w,h=760,560;s=[rect(0,44,152,516,T['glass']),rect(152,44,260,516,T['panel']),line(152,44,152,h,T['border'],.5),line(412,44,412,h,T['border'],.5),text(21,79,'本机截图',10,T['sub'])]
    labels=[('全部截图','image','4'),('待核实','clock','1'),('已附加','check','1'),('已归档','archive','1'),('已移除','removed','0')]
    for i,(lab,ico,count) in enumerate(labels):
        yy=94+i*39
        if i==0:s.append(rect(9,yy,134,36,T['tint'],6))
        s += [native_icon(ico,27,yy+18,15,T['accent'] if i==0 else T['sub']),text(43,yy+23,lab,12,T['accent'] if i==0 else T['text']),text(133,yy+22,count,10,T['sub'],400,'end')]
    s += [text(18,541,'原图始终保留',10,T['sub']),rect(164,58,236,28,T['bg'],6,T['border'],.8),text(174,77,'搜索本页',11,T['sub'])]
    data=[(2,'截图 18','10/28 22:31','结果待核实'),(0,'截图 17','10/28 22:28','已附加'),(1,'截图 16','10/28 22:24','待附加'),(5,'截图 15','10/27 18:06','已归档')]
    for i,(a,lab,date,state) in enumerate(data):
        yy=97+i*65
        if i==0:s.append(rect(158,yy,248,64,T['tint'],6))
        s.append(rect(166,yy+10,56,44,T['bg'],3,T['border'],.5))
        aw,ah=ASPECTS[a];sc=min(56/aw,44/ah);tw,th=aw*sc,ah*sc
        s += [asset(a,166+(56-tw)/2,yy+10+(44-th)/2,tw,th),text(232,yy+19,lab,13,T['text'],500),text(232,yy+36,date,11,T['sub']),text(232,yy+53,state,11,('#9A7135' if T is LIGHT else '#D7B77B') if i==0 else T['sub'])]
    s += [line(152,526,412,526,T['border'],.5),text(166,548,'4 条 · 本页最多 200 条',11,T['sub'])]
    x=436;s += [rect(x,66,300,178,T['panel'],6,T['border'],.8),asset(2,x+13,78,274,154.125),text(x,278,'截图 18',14,T['text'],500),text(736,277,'结果待核实',11,'#9A7135' if T is LIGHT else'#D7B77B',400,'end')]
    for i,st in enumerate(['附加结果暂不能确认。图片与原操作保留，','不会自动再次附加，也不能从这里解锁重传。']):s.append(text(x,304+i*18,st,12,T['sub']))
    for i,(lab,value) in enumerate([('尺寸','1600 × 900'),('时间','10/28 22:31'),('格式','PNG · 合成样本')]):
        yy=358+i*23;s += [text(x,yy,lab,11,T['sub']),text(736,yy,value,11,T['text'],400,'end')]
    s += [button(x,434,136,'在 Finder 中显示',T,h=28),text(x,488,'原型只展示合成数据；不会访问 Finder。',10,T['sub'])]
    return native_frame(w,h,T,'截图历史',''.join(s))

def feedback_window(T):
    # Editor with two-option dropdown and existing draft/outbox semantics.
    w,h=600,540;s=[text(24,88,'哪里不顺手？',20,T['text'],500),text(24,115,'也欢迎告诉我们，你希望它变得怎样。',12,T['sub']),rect(464,68,112,24,T['bg'],5,T['border'],.7),native_icon('privacy',476,80,12,T['sub']),text(489,84,'仅保存在本机',9,T['sub'])]
    s += [rect(24,136,552,211,T['panel'],7,T['border'],.8),text(36,158,'发生了什么？你原本希望怎样？',11,T['sub']),button(462,145,104,'遇到问题',T,h=24),icon('down',555,157,8,T['sub']),text(36,193,'刚切换到一个对话时，截图没有附加。',13,T['text']),text(36,211,'我希望能更明确地知道它正在等待什么。',13,T['text']),text(36,335,'草稿会自动保存，关闭不会发送。',10,T['sub']),text(564,335,'36 / 4,000',10,T['sub'],400,'end')]
    s += [rect(24,362,12,12,T['panel'],2,T['border'],.8),text(42,374,'附带技术诊断',12,T['text']),text(132,374,'仅本次',9,T['sub']),text(576,374,'预览诊断',10,T['accent'],400,'end')]
    s += [rect(24,391,552,51,T['panel'],7,T['border'],.8),native_icon('clock',43,414,17,T['sub']),text(62,411,'接收服务尚未配置',12,T['text'],500),text(62,431,'可以保存待发送；当前不会上传或创建云端记录。',11,T['sub'])]
    s += [line(24,457,576,457,T['border'],.5),text(25,475,'本机反馈记录',11,T['text']),text(557,475,'0 条',10,T['sub'],400,'end'),native_icon('chevron',571,471,12,T['sub']),rect(592,364,3,104,T['sub'],1.5,opacity=.25)]
    s += [line(0,480,w,480,T['border'],.5),text(32,515,'清空草稿',12,T['sub']),button(337,496,110,'保存并关闭',T,h=30),button(455,496,121,'保存待发送',T,True,h=30)]
    return native_frame(w,h,T,'反馈与建议',''.join(s))


def label(W,H,T,subtitle):
    return rect(18,H-32,496,20,T['panel'],4,opacity=.80)+text(26,H-18,'设计场景重构 · 非 App 截图 · 100% 逻辑尺寸',10,T['sub'])+text(W-20,H-18,subtitle,10,T['sub'],400,'end')

def svg(W,H,body,title,desc=''):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img"><title>{esc(title)}</title><desc>{esc(desc or "Riftlet Quiet edge. All desktop, window and image content is synthetic design reconstruction. One exported pixel equals one model logical point; not native App screenshots or a physical macOS acceptance test.")}</desc>'+body+'</svg>'

def desk(name,W,H,T,kind,count,entry=True,expanded=False,waiting=False):
    s=[wallpaper(W,H,T,kind=='busy'),menubar(W,T,'备忘录' if kind=='notes' else'Finder' if kind=='busy' else'Chrome')]
    if kind=='chat':s.append(chrome(72,74,W-208,H-172,T))
    elif kind=='notes':
        s += [finder(82,94,720,448,T),notes(330,170,860,584,T)]
    elif kind=='busy':
        s += [notes(84,90,810,590,T),finder(262,190,720,430,T)]
    elif kind=='external':
        s += [chrome(160,124,1550,1040,T),notes(1570,304,760,660,T)]
    elif kind=='unknown':
        s += [chrome(72,74,W-208,H-172,T),f'<g transform="translate(334 164)">{history_window(T)}</g>']
    s += [dock(W,H,T),rift(W,H,T,count,entry=entry,expanded=expanded,waiting=waiting)]
    if waiting:
        tx=W-354;ty=213;s += [rect(tx,ty+2,266,62,T['text'],8,opacity=.045),rect(tx,ty,266,62,T['panel'],8,T['border'],.7),text(tx+14,ty+25,'已接收，等待附加',12,T['text'],500),text(tx+14,ty+46,'尚未开始上传，图片保持原位。',11,T['sub'])]
    s += [label(W,H,T,name)]
    return svg(W,H,''.join(s),name)

def native_board(name,w,h,fn,T):
    W=w+48;H=h+88;s=[rect(0,0,W,H,'#E7EDE8' if T is LIGHT else'#101713'),rect(24,30,w,h,'#071C10',12,opacity=.045),f'<g transform="translate(24 24)">{fn(T)}</g>',text(24,H-32,name,11,T['text'],500),text(24,H-14,f'设计重构 · 非 App 截图 · 窗口 {w} × {h} pt · 100% 逻辑尺寸',10,T['sub'])]
    return svg(W,H,''.join(s),name)

BOARDS=[
 ('01-light-chat-1440',1440,900,lambda:desk('浅色 / 日常三图',1440,900,LIGHT,'chat',3)),
 ('02-dark-notes-1440',1440,900,lambda:desk('深色 / 多窗口与混合比例',1440,900,DARK,'notes',3)),
 ('03-compact-finder-1280',1280,800,lambda:desk('紧凑桌面 / 12 张队列与溢出',1280,800,LIGHT,'busy',12)),
 ('04-external-2560',2560,1440,lambda:desk('外接屏 / 12 张与完整工作空间',2560,1440,LIGHT,'external',12)),
 ('05-empty-desktop-1440',1440,900,lambda:desk('空队列 / 指针远离 / 零裂缝',1440,900,LIGHT,'empty',0,entry=False)),
 ('06-entry-expanded-1440',1440,900,lambda:desk('固定模式槽 / 区域已选 / 三图仍可操作',1440,900,LIGHT,'chat',3,expanded=True)),
 ('07-waiting-before-start-1440',1440,900,lambda:desk('开始前等待 / 保留原位',1440,900,LIGHT,'chat',3,waiting=True)),
 ('08-unknown-history-1440',1440,900,lambda:desk('开始后待核实 / 隐藏于历史',1440,900,DARK,'unknown',2)),
 ('09-native-first-use',608,608,lambda:native_board('首次使用 / 第2步：连接与权限',560,520,setup_window,LIGHT)),
 ('10-native-settings',728,608,lambda:native_board('设置 / 显示与动效页 · 磁力为合成选择',680,520,settings_window,LIGHT)),
 ('11-native-history',808,648,lambda:native_board('内部截图历史 / 全部截图 · 待核实详情',760,560,history_window,LIGHT)),
 ('12-native-feedback',648,628,lambda:native_board('Feedback v0.1 / 编辑页 · 本机记录折叠',600,540,feedback_window,LIGHT)),
]

def main():
    p=argparse.ArgumentParser();p.add_argument('--svg-only',action='store_true');p.add_argument('--only',default='');args=p.parse_args()
    entries=[]
    for stem,w,h,fn in BOARDS:
        dest=OUT/f'{stem}.svg';dest.write_text(fn(),encoding='utf-8')
        entries.append({'id':stem,'svg':dest.name,'png':stem+'.png','width_px':w,'height_px':h,'logical_scale':1,'source_kind':'synthetic vector design reconstruction','sha256_svg':hashlib.sha256(dest.read_bytes()).hexdigest()})
    # Contact sheet is deliberately labelled reduced scale, never used to assess hit sizes.
    CW,CH=1500,1392;cards=[];cards.append(rect(0,0,CW,CH,'#F7F9F8'));cards+=[logo(28,23,31),text(71,46,'Riftlet · 薄界',22,'#172521',500),text(1472,46,'整套缩览 · 具体尺寸请打开各 100% 图稿',12,'#65716B',400,'end')]
    for i,e in enumerate(entries):
        col=i%3;row=i//3;x=24+col*492;y=78+row*324;bw=468;bh=264
        cards.append(rect(x,y,bw,bh,'#E8EEE9',8))
        src=(OUT/e['svg']).read_text();inner=re.sub(r'^<svg[^>]*>','',src);inner=re.sub(r'</svg>$','',inner)
        scale=min((bw-12)/e['width_px'],(bh-12)/e['height_px']);iw=e['width_px']*scale;ih=e['height_px']*scale
        cards.append(f'<svg x="{x+(bw-iw)/2:g}" y="{y+(bh-ih)/2:g}" width="{iw:g}" height="{ih:g}" viewBox="0 0 {e["width_px"]} {e["height_px"]}">{inner}</svg>')
        cards.append(text(x,y+285,f'{i+1:02d}  '+['浅色 / 日常三图','深色 / 多窗口','紧凑 / 长队列','外接屏 / 12张','空队列 / 完全退场','入口 / 固定槽','等待 / 不假吞噬','UNKNOWN / 内部历史','首次使用','设置','历史','Feedback'][i],12,'#172521',500))
        cards.append(text(x,y+305,f'{e["width_px"]} × {e["height_px"]} logical px   /   SVG 可编辑',10,'#65716B'))
    (OUT/'00-overview.svg').write_text(svg(CW,CH,''.join(cards),'Riftlet visual system overview — reduced-size review'),encoding='utf-8')
    if not args.svg_only:
        env=os.environ.copy()
        if Path('/tmp/riftlet-design-fontconfig.xml').exists():env['FONTCONFIG_FILE']='/tmp/riftlet-design-fontconfig.xml'
        for f in sorted(OUT.glob('*.svg')):
            if args.only and f.stem not in (args.only.split(',')+['00-overview']): continue
            subprocess.run(['inkscape',str(f),'--export-type=png',f'--export-filename={f.with_suffix(".png")}'],env=env,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    for e in entries:
        png=OUT/e['png']
        if png.exists():e['sha256_png']=hashlib.sha256(png.read_bytes()).hexdigest()
    manifest={'title':'Riftlet Quiet edge high-fidelity boards','date':'2026-10-28 Asia/Shanghai','formal_source':SOURCE,'brand_source':MAIN+':favicon.svg','brand_source_sha256':hashlib.sha256(LOGO_BYTES).hexdigest(),'status':'final recommended design, not user-approved native implementation','font_rendering':'Noto Sans CJK SC Regular/Medium + DejaVu Sans in Linux/Inkscape. Native target is macOS system font; no font binaries redistributed.','scale':'Each individual board exports one pixel per model logical point. Native window artboards include 24pt external review margin and separate caption area; actual window sizes remain560×520/680×520/760×560/600×540. Overview is explicitly reduced.','assets':'All wallpaper, application chrome, conversations and screenshot contents synthetic and editable SVG. No private screenshot or real app capture.','boards':entries}
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'boards':len(entries),'overview':'00-overview.png','output':str(OUT),'rendered':not args.svg_only},ensure_ascii=False))

if __name__=='__main__':main()
