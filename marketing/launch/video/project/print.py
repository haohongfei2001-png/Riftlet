"""Nine independently composed publicity images using the recorded Mac windows."""
from films import Footage
from graphics import (KIT, NATIVE, MUTED, GREEN, DARK, PALE, WHITE, brand,
                      chart, label, line, lines, new, paste_fit, photo)


def source_frame(f, t, box=None):
    im = f.at(t)
    return im.crop(box) if box else im


def save(im, directory, name):
    target = KIT / directory / (name+".png")
    im.save(target, optimize=True)
    print(name, flush=True)


def overview(f):
    im = new((1800,1200))
    brand(im, 100, 78, 51)
    lines(im, (94, 234), ["截图，","留在手边。"], 116, role="serif", zh=True, leading=154)
    label(im, (101, 625), "想让草稿看见哪一处，就选哪张图。", 38, zh=True, color=MUTED)
    label(im, (100, 1080), "macOS 13+   /   Chrome 网页版 ChatGPT", 30, zh=True, color=MUTED)
    paste_fit(im, chart("high",False), (936,0,864,478), cover=True, center=(.72,.5))
    paste_fit(im, source_frame(f,10,(78,0,652,585)), (1010,491,725,700))
    return im


def tray_detail(f):
    im = new((1440,1440))
    label(im, (94, 98), "桌面托盘", 33, color=GREEN, zh=True)
    lines(im, (89, 200), ["两张图，","一眼可辨。"], 111, role="serif", zh=True, leading=136)
    paste_fit(im, source_frame(f,9,(82,24,650,567)), (363, 476, 990, 810))
    label(im, (91, 1308), "低潮在左，高潮在右。", 35, zh=True, color=MUTED)
    return im


def sequence(f):
    im = new((2048,1152))
    brand(im, 97, 76, 45)
    label(im,(93,196),"从截图到草稿，三步。",91,role="serif",zh=True)
    w = 616
    for x, tag in [(98,"照常截图"),(765,"打开目标草稿"),(1433,"点击微图")]:
        line(im, (x,405,x+w-60,405), "#AFC5B7",2)
        label(im,(x,429),tag,30,color=GREEN,zh=True)
    paste_fit(im,photo("low-window.png"),(96,532,551,397))
    lines(im,(760,550),["把要用的","ChatGPT 草稿","放到 Chrome 前台。"],60,leading=94,role="serif",zh=True,maximum=564)
    paste_fit(im,source_frame(f,5,(93,195,652,560)),(1425,527,565,406))
    label(im,(100,993),"macOS 存下窗口图。",31,color=MUTED,zh=True)
    label(im,(765,993),"选择可以添加附件的草稿。",31,color=MUTED,zh=True)
    label(im,(1433,993),"点图附加，发送由你。",31,color=MUTED,zh=True)
    return im


def desk(f):
    im = new((1800,1350),PALE)
    label(im,(93,94),"涨潮后，哪里变了？",94,role="serif",zh=True)
    label(im,(99,247),"把两次观察截下来，给草稿里的问题配图。",36,zh=True,color=MUTED)
    paste_fit(im,photo("low-window.png"),(97,380,752,548))
    paste_fit(im,photo("high-window.png"),(952,519,752,548))
    label(im,(100,963),"低潮时的岸线",33,zh=True)
    label(im,(952,1102),"同一处海湾，潮水上涨",33,zh=True)
    label(im,(100,1240),"MERIDIAN INLET   /   TIDAL STUDIES",26,role="mono",color=GREEN)
    return im


def control_detail(f):
    im = new((1600,1200))
    label(im,(91,89),"相机键里，有什么？",97,role="serif",zh=True)
    label(im,(94,244),"在实际运行的托盘里展开截图方式。",36,zh=True,color=MUTED)
    paste_fit(im,source_frame(f,13.5,(102,33,647,565)),(65,319,814,794))
    line(im,(928,506,1498,506),"#AFC5B7",2)
    for n,(head,body) in enumerate([("区域","截取想指出的那一处。"),("窗口","保留一整幅图的上下文。")]):
        y=552+n*228
        label(im,(933,y),head,72,role="serif",zh=True)
        label(im,(936,y+107),body,33,color=MUTED,zh=True)
    return im


def brand_visual():
    im = new((1800,1080),DARK)
    brand(im,108,93,53,color=WHITE)
    paste_fit(im,chart("low",False),(1144,0,656,1080),cover=True,center=(.63,.50))
    lines(im,(100,338),["Bring this detail","into the draft."],131,leading=144,role="serif",color=WHITE,maximum=1004)
    label(im,(108,871),"riftlet.com",48,color="#A7DFCC",role="medium")
    return im


def launch_cover(f):
    im = new((1920,1080))
    paste_fit(im,chart("low",False),(0,0,830,1080),cover=True,center=(.65,.5))
    # The precise same inlet turns into an actual thumbnail on the opposite page.
    brand(im,920,86,57)
    label(im,(915,222),"让截图进入草稿。",92,zh=True,role="serif",maximum=944)
    label(im,(922,395),"Mac 公开测试版",38,zh=True,color=GREEN)
    paste_fit(im,source_frame(f,5,(86,232,650,572)), (1033,481,715,420))
    label(im,(920,958),"Riftlet 0.3.5   /   riftlet.com",32,color=MUTED)
    return im


def social_cover(f):
    im = new((1080,1920))
    brand(im,86,127,52)
    lines(im,(79,299),["截完图，","下一步呢？"],118,role="serif",zh=True,leading=161)
    paste_fit(im,chart("high",False),(0,739,1080,430),cover=True)
    paste_fit(im,source_frame(f,13.4,(87,48,652,562)),(189,1182,730,623))
    label(im,(80,1792),"桌面托盘实录",34,color=MUTED,zh=True)
    return im


def web_cover():
    im = new((1600,840),DARK)
    # Two opposing tide sections carry the story even in link previews.
    paste_fit(im,chart("high",False),(1033,0,567,409),cover=True,center=(.6,.48))
    paste_fit(im,chart("low",False),(1120,430,480,410),cover=True,center=(.6,.48))
    brand(im,80,69,49,color=WHITE)
    lines(im,(76,233),["From screenshot","to your draft."],113,role="serif",color=WHITE,leading=124)
    label(im,(82,655),"Mac Public Beta  /  riftlet.com",35,color="#A7DFCC")
    return im


if __name__ == "__main__":
    footage = Footage(NATIVE/"tray-lossless.mp4")
    for filename, draw in [("01-overview",overview),("02-tray-detail",tray_detail),("03-workflow",sequence),
                           ("04-two-tides",desk),("05-camera-control",control_detail)]:
        save(draw(footage),"images",filename)
    save(brand_visual(),"images","06-brand")
    save(launch_cover(footage),"covers","01-public-beta")
    save(social_cover(footage),"covers","02-social-video")
    save(web_cover(),"covers","03-site-campaign")
