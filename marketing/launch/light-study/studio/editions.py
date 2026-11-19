"""Alternative aspect ratios are composed on their own canvases."""
from art import *


def short(which,t,scale=1):
    if which=="capture":
        a=Art(900,1600,scale)
        a.full(PLATE,1.04+.10*ease(t/8),(.27,.70))
        a.box((0,0,900,297),PAPER)
        a.mark(58,62,39)
        a.txt(111,66,"Riftlet",26)
        a.txt(54,128,"See the crossing.",81,"serif")
        z=ease((t-1.5)/1.9)
        # Locate the same optical crossing within the camera's moving crop.
        zoom=1.04+.10*ease(t/8)
        cw=PLATE.height*(900/1600)/zoom
        ch=PLATE.height/zoom
        left=(PLATE.width-cw)*.27
        top=(PLATE.height-ch)*.70
        px=(466-left)/cw*900
        py=(752-top)/ch*1600
        if t>1.50:
            corners(a,(px-144,py-103,px-144+288*z,py-103+206*z),LIGHT,3,22)
        if t>4.7:
            a.box((46,1368,855,1537),PAPER,23)
            tray(a,85,1500,195,"a")
            a.txt(332,1404,"Keep the detail.",57,"italic")
            a.txt(335,1480,"Screenshot tray on Mac",22,color=MUTED)
    elif which=="at-hand":
        a=Art(1000,1000,scale)
        page(a)
        a.mark(58,57,44)
        a.txt(118,62,"Riftlet",30)
        a.txt(54,146,"Two angles.",91,"serif")
        a.txt(56,239,"One tray.",92,"italic")
        z=ease((t-2.4)/1.05)
        grow_tray(a,296,811,530,z)
        if t>4.35:
            x=mix(897,408,ease((t-4.35)/1.45))
            y=mix(868,481,ease((t-4.35)/1.45))
            cursor(a,x,y)
        a.line((58,890,942,890),"#c8cbbf",1)
        a.txt(58,913,"SCREENSHOT TRAY",20,"mono",MUTED)
        a.txt(942,913,"DESIGN ANIMATION",20,"mono",MUTED,"ra")
    elif which=="draft":
        a=Art(900,1125,scale)
        page(a)
        a.mark(54,52,40)
        a.txt(109,55,"Riftlet",28)
        a.txt(51,122,"Inside the draft.",92,"serif")
        after=t>=4.0
        if not after:
            tray(a,503,559,295,"ab")
            p=ease((t-.65)/2.37)
            cursor(a,mix(180,580,p),mix(617,375,p))
        else:
            tray(a,503,559,295,"b")
        composer(a,53,611,794,367,after,caret=(int(t*2)%2==0 and not after))
        a.txt(54,1038,"CHATGPT IN CHROME",19,"mono",MUTED)
        a.txt(845,1038,"DESIGN ANIMATION",19,"mono",MUTED,"ra")
    return a.img


def print_panels():
    panels={}
    a=Art(scale=1.5)
    a.full(DARK,1.04,(.3,.4)); a.mark(72,60,56)
    a.txt(75,175,"Light",156,"serif",LIGHT); a.txt(75,319,"study.",153,"italic",MINT)
    a.txt(79,580,"A Riftlet film",33,"sans",LIGHT); a.foot(True,"OPTICAL STUDY  /  A")
    panels["stills/01-observation"]=a.img
    a=Art(scale=1.5); selection_scene(a,3.2); panels["stills/02-capture"]=a.img
    a=Art(scale=1.5); arrival_scene(a,4.5); panels["stills/03-arrival"]=a.img
    a=Art(scale=1.5); pair_scene(a,5.0); panels["stills/04-tray"]=a.img
    a=Art(scale=1.5); close_scene(a,3.21); panels["stills/05-draft"]=a.img
    a=Art(scale=1.5); page(a); a.mark(79,82,120)
    a.txt(76,274,"Riftlet",156,"serif"); a.txt(80,481,"From screenshot to draft.",55,"italic")
    a.txt(82,623,"Public Beta 0.3.5 (20)   ·   macOS 13+",27,color=MUTED)
    # The vertical slice samples the intersecting ray, not the empty paper.
    slice_=ImageOps.fit(PLATE,(733,900),RES.LANCZOS,centering=(.31,.60))
    a.put(slice_,867,0,733,900); a.txt(82,818,"RIFTLET.COM",20,"mono",MUTED)
    panels["stills/06-edition"]=a.img
    a=Art(scale=1.2); a.full(DARK,1.025,(.65,.55))
    a.mark(77,62,58); a.txt(151,71,"Riftlet",35,"sans",LIGHT)
    a.txt(75,185,"Light study.",145,"serif",LIGHT)
    a.txt(78,370,"From screenshot to draft.",56,"italic",MINT)
    a.foot(True,"BRAND FILM   /   37 SEC")
    panels["covers/press-16x9"]=a.img
    a=Art(1000,1250,1.2); page(a)
    a.mark(57,62,49); a.txt(122,67,"Riftlet",32)
    a.txt(54,176,"A detail",118,"serif"); a.txt(55,287,"worth keeping.",106,"italic")
    a.put(ImageOps.fit(PLATE,(902,512),RES.LANCZOS),49,465,902,512)
    tray(a,631,1029,272,"a"); a.txt(54,1112,"SCREENSHOT TO CHATGPT DRAFT",20,"mono",MUTED)
    a.txt(54,1163,"RIFTLET.COM",20,"mono",MUTED)
    panels["covers/social-4x5"]=a.img
    a=Art(scale=1.2); a.full(PLATE)
    a.mark(76,64,53); a.txt(147,72,"Riftlet",33,"sans",INK)
    a.txt(73,154,"光的路径",102,"zh",INK); a.txt(78,288,"Light study",69,"italic",INK)
    a.txt(78,400,"从截图，到草稿。",32,"zh",INK)
    corners(a,(323,590,613,830),LIGHT,2,24)
    a.box((1257,58,1521,104),PAPER,22)
    a.txt(1389,70,"BRAND FILM    /    37 SEC",15,"mono",INK,"ma")
    panels["covers/bilibili-16x9"]=a.img
    return panels
