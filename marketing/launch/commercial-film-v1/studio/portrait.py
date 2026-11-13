"""15 s portrait conform of the approved master, sharing original art and state clock."""
from PIL import Image,ImageDraw
from film import encode,subtitle,brandbug,on_disk,lower_shade
from sets import Set,ART,ROOT,IVORY,INK,txt,mark,font,viewport,s,ease,mix
from chrome.composer import draw_window

SIZE=(1080,1920)
SHORT_CAPTIONS=[
    (0,1.55,'Mac 截图，一点就到 ChatGPT 草稿。'),
    (1.55,3.03,'用 Mac 截下想问的画面。'),
    (3.03,4.07,'骑手这张，已进入托盘。'),
    (4.07,4.83,'再截一张。'),
    (4.83,6.60,'第二张也在手边。'),
    (6.60,7.75,'点选骑手这张。'),
    (7.75,9.55,'已附加到 Chrome 中的 ChatGPT 草稿。'),
    (9.55,12.00,'接着写下问题。'),
    (12.00,15.00,'截屏、点选、继续。'),
]

# Source in-points are from the main picture edit. Arrival, press and
# registration are distinct. No extra user input is created by the conform.
CLOCK=[
 (0.,0.),(1.55,2.83),(2.53,5.1),(3.03,5.55),(4.07,7.2),
 (4.43,8.10),(4.83,8.55),(6.6,10.98),(7.01,11.94),(7.54,13.20),
 (7.75,13.45),(8.72,14.70),(9.55,17.71),(9.60,17.80),(11.2,20.65),
 (12.,24.85),(15.,30.),
]

def source_time(t):
    for (a,x),(b,y) in zip(CLOCK,CLOCK[1:]):
        if t<b:return mix(x,y,(t-a)/(b-a))
    return 30.

def photo(im,pic,t,begin,shutter):
    # This is the same complete selection, held within a full-width portrait mat.
    x,y,w,h=52,603,976,651
    frame=pic.resize((w,h),Image.Resampling.LANCZOS);im.paste(frame,(x,y))
    q=ImageDraw.Draw(im)
    for xx,signx in ((x,-1),(x+w,1)):
        for yy,signy in ((y,-1),(y+h,1)):
            q.line((xx+4*signx,yy,xx+18*signx,yy),fill='#777D72',width=2)
            q.line((xx,yy+4*signy,xx,yy+18*signy),fill='#777D72',width=2)
    if t<=shutter:
        k=s(t,begin,shutter-.04)
        block=Image.new('RGBA',(w,h),(0,0,0,71))
        dr=ImageDraw.Draw(block)
        dr.rectangle((0,0,max(1,w*k),max(1,h*k)),fill=(0,0,0,0),outline='white',width=3)
        im.paste(block,(x,y),block)
    if shutter<=t<shutter+.12:im=Image.blend(im,Image.new('RGB',SIZE,IVORY),.42*(1-(t-shutter)/.12))
    return im

def draw_portrait(st,t):
    mt=source_time(t);w,h=SIZE
    if t<1.55:
        # A cropped view of the physical screen with an independent mobile title safe.
        im=st.physical(mt,SIZE,(mix(779,776,s(t,0,1.55)),431),mix(560,675,s(t,0,1.55)))
        lower_shade(im,.95)
        brandbug(im,62,91,58,True)
        txt(im,(59,1357),'Keep the thought.',119,'serif',IVORY,'lt')
        txt(im,(65,1500),'Mac screenshots to ChatGPT in Chrome.',42,'medium',IVORY,'lt')
    elif t<3.03 or 4.07<=t<4.83:
        b=t>=4.07
        im=Image.new('RGB',SIZE,'#E1E7E7' if b else '#F6F2E9')
        brandbug(im,62,99,55)
        txt(im,(60,350),'The inner line.' if b else 'Capture.',120 if b else 169,'serif',INK,'lt')
        im=photo(im,st.b if b else st.a,t,4.07 if b else 1.55,4.43 if b else 2.53)
        txt(im,(62,1328),'Track study   /   02' if b else 'Shift + Command + 4',42,'medium',INK,'lt')
    elif t<6.60:
        im=viewport(st.empty,2690,952,590,(w,h))
        title='Both here.' if t>=4.83 else 'At hand.'
        brandbug(im,65,101,54,True)
        txt(im,(60,330),title,165,'serif',IVORY,'lt')
        txt(im,(68,532),'Riftlet screenshot tray',43,'medium',IVORY,'lt')
        plate=st.tray.render(mt)
        scale=3.28+.07*s(t,3.03,6.6)
        p=plate.resize((round(330*scale),round(296*scale)),Image.Resampling.LANCZOS)
        on_disk(im,p,(w-330*scale)/2,1150-180*scale)
    elif t<7.01:
        im=viewport(st.finger,935,485,614,SIZE)
        lower_shade(im,.85)
        txt(im,(59,1350),'One click.',160,'serif',IVORY,'lt')
    elif t<9.55:
        # Two synchronized reframings of the same desktop, in editorial split screen.
        # The upper lens stays with the chosen tile; the lower lens presents ONLY
        # the existing window. The native tray is never physically moved over Chrome.
        im=Image.new('RGB',SIZE,IVORY)
        top=st.world_view(mt,1340,469,288,(w,792))
        im.paste(top,(0,0))
        txt(im,(57,857),'Your draft.' if mt<13.45 else 'Attached.',112,'serif',INK,'lt')
        native=draw_window(mt,st.a,scale=2)
        im.paste(native.crop((0,140,1280,1040)).convert('RGB').resize((1080,759),Image.Resampling.LANCZOS),(0,1015))
    elif t<12:
        im=Image.new('RGB',SIZE,IVORY)
        txt(im,(62,293),'Continue.',166,'serif',INK,'lt')
        win=draw_window(mt,st.a,scale=2)
        # Preserve the first question and appended sentence, the full-width
        # edit field, attachment and idle send arrow in the same portrait view.
        out=win.resize((1000,875),Image.Resampling.LANCZOS)
        on_disk(im,out,40,595)
        txt(im,(60,1530),'No file hunt. No dragging.',55,'serif',INK,'lt')
    else:
        im=Image.new('RGB',SIZE,IVORY)
        a=s(t,12,12.37)
        tile=mark(156);on_disk(im,tile,(w-156)/2,535+(1-a)*28)
        txt(im,(540,755),'Riftlet',205,'serif',INK,'mt')
        p=s(t,12.30,12.75)
        col=tuple(round(mix(v,b,p)) for v,b in zip((252,251,248),(27,52,45)))
        txt(im,(540,1042),'Capture. Click. Continue.',64,'sans',col,'mt')
        q=s(t,12.8,13.16)
        col=tuple(round(mix(v,b,q)) for v,b in zip((252,251,248),(36,91,76)))
        txt(im,(540,1350),'riftlet.com',64,'medium',col,'mt')
        txt(im,(540,1447),'Download for macOS  ·  Public Beta',35,'sans',col,'mt')
    for a,b,label in SHORT_CAPTIONS:
        if a<=t<b:subtitle(im,label,portrait=True);break
    return im

if __name__=='__main__':
    encode(draw_portrait,Set(),450,SIZE,ART/'score-vertical.wav',ROOT/'films/riftlet-vertical.mp4')
