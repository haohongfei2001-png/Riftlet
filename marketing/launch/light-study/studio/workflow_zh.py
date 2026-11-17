"""Chinese release film. The same two source crops persist through every state."""
from functools import lru_cache
from PIL import ImageFont
from art import (Art, PLATE, DARK, DETAIL, ANGLE, LIGHT, INK, MUTED, MINT,
                 clamp, corners, cursor, ease, face, grow_tray, mix,
                 page, tray)
from platforms import SONGTI

RATE = 24
DURATION = 32
OUTPUT = "brand-film.zh-CN"
PANE = (86, 166, 996, 541)
SELECT_A = (181, 490, 825, 935)
SELECT_B = (600, 419, 1312, 911)


@lru_cache(maxsize=60)
def font(size, serif):
    if serif:
        return ImageFont.truetype(str(SONGTI),size,index=3)
    return face("zh",size)


def text(a,x,y,words,size,color=INK,serif=False,anchor="lt"):
    a.d.text(a.points((x,y)),words,fill=color,font=font(round(size*a.s),serif),anchor=anchor)


def mast(a,slug):
    a.mark(70,47,40)
    a.txt(126,50,"Riftlet",30,"sans",INK)
    text(a,269,59,slug,22,MUTED)
    text(a,1528,60,"操作示意",21,MUTED,anchor="rt")


def specimen(a,plate,selection,progress):
    x,y,w,h=PANE
    a.box((x-2,y-41,x+w+2,y+h+4),"#d5d6cc",13)
    a.box((x,y-39,x+w,y+16),"#fffdf7",12)
    for i,color in enumerate(("#d47d6b","#d9b86f","#9ea988")):
        a.box((x+16+21*i,y-25,x+26+21*i,y-15),color,5)
    text(a,x+w/2,y-30,"玻璃折光研究",19,MUTED,anchor="mt")
    a.put(plate,x,y,w,h)
    l,top,r,b=selection
    rect=(x+l*w/plate.width,y+top*h/plate.height,x+r*w/plate.width,y+b*h/plate.height)
    if progress is not None:
        x1,y1,x2,y2=rect
        z=ease(progress)
        x2=mix(x1+7,x2,z); y2=mix(y1+7,y2,z)
        bounds=(x1,y1,x2,y2)
        a.d.rectangle(a.points(bounds),outline="#fbf9ee",width=max(1,round(a.s*1.5)))
        corners(a,bounds,"#ffffff",3,17)
        a.line((x2-9,y2,x2+9,y2),INK,2)
        a.line((x2,y2-9,x2,y2+9),INK,2)
    return rect


def caption(a,verb,rest):
    a.line((74,759,1528,759),"#c5cabe",1)
    text(a,76,790,verb,41,INK,True)
    text(a,1528,804,rest,27,MUTED,anchor="rt")


def collect(a,t):
    # Both source views are shown in the same specimen window, at a fixed scale.
    second=t>=6.9
    elapsed=t-6.9 if second else t
    a.full(paper())
    mast(a,"把 Mac 截图附到 ChatGPT 草稿")
    mark_at=.55 if second else 1.0
    land_at=2.05 if second else 3.05
    origin=specimen(a,DARK if second else PLATE,SELECT_B if second else SELECT_A,
                    (elapsed-mark_at)/1.05 if elapsed>=mark_at and elapsed<land_at+.25 else None)
    tx,bot,width=1171,598,345
    z=ease((elapsed-land_at)/.92)
    if second:
        grow_tray(a,tx,bot,width,(elapsed-land_at-.62)/.36)
    else:
        tray(a,tx,bot,width,"a" if z>=1 else ("-" if z>0 else ""))
    if 0<z<1:
        l,top,r,b=origin
        unit=width/246
        cell=(181.8 if second else 63.7)*unit
        tilew=107.8*unit
        photo=ANGLE if second else DETAIL
        th=tilew*photo.height/photo.width
        dest=(tx+cell-tilew/2,bot-(212 if second else 115)*unit+57*unit-th/2)
        a.put(photo,mix(l,dest[0],z),mix(top,dest[1],z),mix(r-l,tilew,z),mix(b-top,th,z))
    text(a,tx,bot+35,"截图托盘",25,MUTED)
    if second:
        caption(a,"再截一张侧面图。","托盘会把两次截图并排放好")
    elif elapsed>=3.85:
        caption(a,"交点图已经在手边。","下一张系统截图也会进入托盘")
    else:
        caption(a,"截下想问的那一处。","按 Shift + Command + 4，拖出选区")


@lru_cache(maxsize=1)
def paper():
    a=Art()
    page(a)
    return a.img


def chrome(a,count,typed):
    x,y,w,h=85,138,1002,562
    a.box((x,y+5,x+w,y+h+5),"#d8d9ce",20)
    a.box((x,y,x+w,y+h),"#fffcf6",20,"#c4c9bd")
    a.box((x+1,y+1,x+w-1,y+85),"#ecece3",18)
    a.line((x+1,y+83,x+w-1,y+83),"#d1d4ca")
    for i,c in enumerate(("#cb7969","#d9ba75","#98ad93")):
        a.box((x+19+19*i,y+18,x+29+19*i,y+28),c,5)
    a.txt(x+110,y+11,"ChatGPT",23)
    a.box((x+99,y+47,x+w-26,y+73),"#fafaf5",13)
    a.txt(x+126,y+48,"chatgpt.com",18,"sans",MUTED)
    text(a,x+42,y+111,"当前对话",23,MUTED)
    text(a,x+48,y+170,"玻璃折光研究",42,INK,True)
    # The editable draft retains its text and both attachments have stable identities.
    l,top,r,b=x+38,y+262,x+w-38,y+h-29
    a.box((l,top,r,b),"#ffffff",24,"#cdd1c7",2)
    if count:
        for i,pic in enumerate([DETAIL,ANGLE][:count]):
            a.put(pic,l+28+i*148,top+17,133,92)
    text(a,l+27,top+128,"这两束光为什么会交叉？",32)
    continuation="请对照两张图看一下。"[:typed]
    if continuation:
        text(a,l+27,top+176,continuation,29)
    a.txt(l+27,b-49,"+",29,"sans",MUTED)
    a.box((r-65,b-55,r-25,b-15),INK,20)
    a.line((r-45,b-25,r-45,b-43),LIGHT,2)
    a.line((r-52,b-37,r-45,b-44,r-38,b-37),LIGHT,2)


def in_draft(a,t):
    a.full(paper())
    mast(a,"Google Chrome 网页版  /  ChatGPT")
    click_a,receive_a=3.85,4.30
    click_b,receive_b=9.60,10.05
    count=int(t>=receive_a)+int(t>=receive_b)
    chrome(a,count,0)
    tx,bot,w=1160,593,355
    state=("ab","b","")[count]
    prior=("ab","ab","b")[count]
    start=(0,receive_a,receive_b)[count]
    fade=ease((t-start-.04)/.15)
    if count and fade<1: tray(a,tx,bot,w,prior)
    tray(a,tx,bot,w,state,fade if count else 1)
    text(a,tx,bot+36,"截图托盘",25,MUTED)
    px,py=tx+89,bot-223
    if t<click_b-1.65:
        q=ease((t-1.55)/1.55)
        xx,yy=mix(874,px,q),mix(623,py,q)
    else:
        q=ease((t-click_b+1.65)/1.0)
        xx,yy=px,mix(py,bot-86,q)
    if t<receive_b+.5:
        pulse=max(1-abs(t-click_a)/.22,1-abs(t-click_b)/.22,0)
        cursor(a,xx,yy,pulse)
        if pulse>0:
            radius=8+11*(1-pulse)
            a.d.ellipse(a.points((xx-radius,yy-radius,xx+radius,yy+radius)),outline="#186657",width=max(1,round(2*a.s)))
    if t<2.2:
        caption(a,"回到 Chrome 里的草稿。","打开能添加图片的 ChatGPT 对话")
    elif t<receive_a:
        caption(a,"点一下交点图。","选托盘左上角的第一张")
    elif t<7.2:
        caption(a,"草稿开始接收，微图收起。","问题还在，侧面图还在托盘里")
    elif t<receive_b:
        caption(a,"再点一下侧面图。","第二张也附到同一份草稿")
    elif t<11.65:
        caption(a,"两张图，都在问题旁边。","每次点击只附加选中的一张")
    else:
        caption(a,"接着写，由你发送。","图片已经附到这份草稿里")


def compare(a,t):
    """Cut in on the draft once both originals have been selected."""
    a.full(paper())
    mast(a,"ChatGPT 草稿")
    text(a,79,202,"两张图，",63,INK,True)
    text(a,79,294,"同一个问题。",63,INK,True)
    text(a,82,450,"继续补充想问的细节。",29,MUTED)
    x,y,w,h=594,155,928,520
    a.box((x,y+5,x+w,y+h+5),"#d6d8ce",26)
    a.box((x,y,x+w,y+h),"#fffefa",26,"#c6cbbf")
    a.txt(x+41,y+32,"ChatGPT",28)
    a.line((x+1,y+88,x+w-1,y+88),"#dadfd4")
    for i,img in enumerate((DETAIL,ANGLE)):
        a.put(img,x+41+i*236,y+125,212,147)
    text(a,x+41,y+315,"这两束光为什么会交叉？",42)
    words="请对照两张图看一下。"[:round(10*clamp((t-.28)/1.85))]
    text(a,x+41,y+390,words,34)
    if int(t*2)%2==0:
        length=a.d.textlength(words,font=font(round(34*a.s),False))/a.s
        a.line((x+43+length,y+389,x+43+length,y+428),MUTED,2)
    a.txt(x+40,y+h-50,"+",28,"sans",MUTED)
    bx,by=x+w-65,y+h-58
    a.box((bx,by,bx+42,by+42),INK,21)
    a.line((bx+21,by+29,bx+21,by+12),LIGHT,2)
    a.line((bx+14,by+18,bx+21,by+11,bx+28,by+18),LIGHT,2)
    caption(a,"想好了，再发送。","原来的文字和两张附件都保留在草稿里")


def frame(t,scale=1.2):
    a=Art(scale=scale)
    if t<11.5:
        collect(a,t)
    elif t<23.5:
        in_draft(a,t-11.5)
    elif t<28.5:
        compare(a,t-23.5)
    else:
        a.full(DARK,1.04-.025*ease((t-28.5)/3.5))
        a.mark(79,92,72)
        a.txt(76,220,"Riftlet",141,"serif",LIGHT)
        text(a,82,421,"从 Mac 截图，到 ChatGPT 草稿。",46,LIGHT,True)
        a.txt(84,535,"riftlet.com",31,"sans",MINT)
    return a.img
