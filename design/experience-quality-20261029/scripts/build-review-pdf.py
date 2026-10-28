"""Create the visual review book from verified design boards, not native screenshots."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont as PDFTTFont
from reportlab.lib.colors import HexColor, Color, toColor
from reportlab.lib.utils import ImageReader
from fontTools.ttLib import TTFont
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
import json, os

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('RIFTLET_REVIEW_OUTPUT', str(ROOT/'exports')))
OUT.mkdir(parents=True,exist_ok=True)
FONT=Path(os.environ.get('RIFTLET_REVIEW_TTF', '/tmp/riftlet-review-cjk-subset.ttf'))
if not FONT.exists():
    src=TTFont(os.environ.get('RIFTLET_REVIEW_OTF', '/tmp/riftlet-review-cjk-subset.otf'))
    fb=FontBuilder(src['head'].unitsPerEm,isTTF=True)
    order=src.getGlyphOrder();fb.setupGlyphOrder(order)
    gs=src.getGlyphSet();out={}
    for name in order:
        pen=TTGlyphPen(None)
        gs[name].draw(Cu2QuPen(pen,max_err=1.0,reverse_direction=True))
        out[name]=pen.glyph()
    fb.setupGlyf(out)
    fb.setupHorizontalMetrics(dict(src['hmtx'].metrics))
    fb.setupHorizontalHeader(ascent=src['hhea'].ascent,descent=src['hhea'].descent)
    fb.setupCharacterMap(src.getBestCmap())
    fb.setupNameTable({'familyName':'Riftlet Review CJK','styleName':'Regular','uniqueFontIdentifier':'RiftletReviewCJK','fullName':'Riftlet Review CJK Regular','psName':'RiftletReviewCJK-Regular'})
    fb.setupOS2(sTypoAscender=src['hhea'].ascent,sTypoDescender=src['hhea'].descent,usWinAscent=max(0,src['hhea'].ascent),usWinDescent=abs(src['hhea'].descent))
    fb.setupPost();fb.setupMaxp();fb.save(FONT)
pdfmetrics.registerFont(PDFTTFont('Review',str(FONT)))
W,H=1440,1100
INK=HexColor('#172521');MUTED=HexColor('#65716b');ACCENT=HexColor('#087f73');LINE=HexColor('#d5dfd8');BG=HexColor('#f7f9f8')
c=canvas.Canvas(str(OUT/'Riftlet-Experience-Review.pdf'),pagesize=(W,H),pageCompression=1)
c.setTitle('Riftlet | 完整产品体验补充设计')
c.setAuthor('Riftlet independent product experience review')
page=0
def text(x,y,t,size=20,color=INK):
    c.setFillColor(color);c.setFont('Review',size);c.drawString(x,H-y,t)
def paragraph(x,y,t,size=22,width=1240,leading=None,color=INK):
    leading=leading or size*1.5;line=''
    for char in t:
        if char=='\n' or pdfmetrics.stringWidth(line+char,'Review',size)>width:
            text(x,y,line,size,color);y+=leading;line='' if char=='\n' else char
        else:line+=char
    if line:text(x,y,line,size,color);y+=leading
    return y
def rect(x,y,w,h,fill='white',radius=10,stroke=LINE):
    c.setFillColor(toColor(fill) if isinstance(fill,str) else fill);c.setStrokeColor(stroke);c.setLineWidth(.8);c.roundRect(x,H-y-h,w,h,radius,fill=1,stroke=1)
def new(title=None,sub=None):
    global page
    if page:c.showPage()
    page+=1;c.setFillColor(BG);c.rect(0,0,W,H,fill=1,stroke=0)
    if title:text(72,80,title,34)
    if sub:text(72,118,sub,17,MUTED)
def footer(label='独立补充设计 · 合成画面 · 不代表原生验收'):
    text(72,1067,label,14,MUTED);text(1305,1067,f'{page:02d} / 20',14,MUTED)
def arrow(x1,y1,x2,y2,color=ACCENT):
    c.setStrokeColor(color);c.setFillColor(color);c.setLineWidth(2);c.line(x1,H-y1,x2,H-y2)
    import math
    a=math.atan2(y2-y1,x2-x1);p=c.beginPath();p.moveTo(x2,H-y2)
    p.lineTo(x2-10*math.cos(a-.5),H-(y2-10*math.sin(a-.5)))
    p.lineTo(x2-10*math.cos(a+.5),H-(y2-10*math.sin(a+.5)));p.close();c.drawPath(p,fill=1,stroke=0)

new();text(72,95,'Riftlet',29,ACCENT)
text(72,215,'完整产品体验补充设计',52)
text(72,274,'首次使用 · 异常恢复 · 原生一致性',30,MUTED)
paragraph(72,360,'保持「薄界」，补齐有证据的体验缺口。',30)
paragraph(72,421,'本轮审查真实工程、原生图像、录屏、状态契约与自动化证据。补充设计不修改当前正式集成，不改变 PR #1，不以原型宣称真实上传或真机验收。',22,width=1130)
cards=[('48','证据条目','区分已实现、已有设计差额、真实缺陷与尚未验证。'),('06','交互场景组','38 个固定情境，覆盖首次使用到退出后再次启动。'),('16','高保真审阅图','沿用原生候选的窗框、字体层级、几何与颜色。')]
for i,(n,t,d) in enumerate(cards):
    x=72+i*435;rect(x,560,408,220);text(x+24,620,n,42,ACCENT);text(x+24,668,t,24);paragraph(x+24,708,d,18,width=355,leading=28,color=MUTED)
text(72,851,'正式设计 7e03bd2c  /  原生候选 00dedc7f  /  原生交接 443d21da',19)
text(72,891,'审计起点：PR #1 = 0e7ea8be，Open / Draft；main = eba1a4f。',18,MUTED)
text(72,927,'2026-10-29 · 北京时间 · 独立设计交付',18,MUTED);footer()

new('先保留成熟部分，再补完整体验','证据等级决定结论；候选已实现不等于已经正式集成。')
rows=[('明确保留','固定模式槽、移动取消盖片、只保留无/磁力吸引、真实开始后快速吞噬、UNKNOWN 与历史、原图、独立暂停与隐藏、反馈本地草稿。'),('真实缺口','首屏承诺没有跟随实际能力；已选目标倒计时未呈现；历史长日期截断与大预览解码不足；反馈状态动作与关闭保护的解释不完整。'),('已有设计差额','附近 240pt 非激活说明、设置内嵌等已有正式设计。当前 tooltip、AX 和等待短线已经存在，不能称为完全没有反馈。'),('尚未验证','物理首用/权限、中文 IME、VoiceOver、1x/多屏拔插、Spaces/全屏和最终组合 App 的跨应用焦点。现有 helper 证据不外推。')]
y=178
for title,body in rows:
    rect(72,y,1296,159);text(96,y+42,title,25,ACCENT);paragraph(96,y+84,body,21,width=1225,leading=32);y+=180
text(72,955,'执行文件：EVIDENCE_LEDGER.md / APPKIT_SUPPLEMENT.md / STATE_TRANSITIONS.md / ENGINEERING_CHECKLIST.md',15,MUTED)
footer('本页判断均追溯至固定 SHA；完整文件路径和行号在证据清单中')

boards=sorted((ROOT/'boards').glob('[0-9][0-9]-*.png'))
assert len(boards)==16, len(boards)
for board in boards:
    new();c.drawImage(ImageReader(str(board)),0,50,width=1440,height=1050,mask='auto')
    footer('设计模拟 · '+board.stem)

new('两个必须清楚分开的状态链','状态图是实施约束，不是新的上传能力或真实原生运行证据。')
text(72,190,'截图：已确认目标与下一次模式互不覆盖',26,ACCENT)
labels=[('选择目标','完整用户手势'),('冻结请求','本次区域 + 5秒'),('倒计时','下一张可切窗口'),('捕获结果','先验证后收录'),('继续会话','保持展开，X结束')]
for i,(a,b) in enumerate(labels):
    x=72+263*i;rect(x,226,235,113);text(x+18,269,a,22);text(x+18,308,b,17,MUTED)
    if i<4:arrow(x+239,282,x+259,282)
paragraph(72,389,'X / Escape 结束整个会话。未交付的旧回调失效；已经完成的截图仍保留。切换模式不改变原 request 的目标、延时或捕获参数。',21,width=1260)
text(72,503,'附加：视觉消失与最终结果是两个事实',26,ACCENT)
labels=[('可见截图','一次原点击'),('受理等待','仍在输入前'),('prepared','中性处理中'),('uploadStarted','唯一快吞噬触发'),('隐藏后观察','保留原操作')]
for i,(a,b) in enumerate(labels):
    x=72+263*i;rect(x,543,235,113);text(x+18,586,a,22);text(x+18,625,b,17,MUTED)
    if i<4:arrow(x+239,599,x+259,599)
for i,(a,b) in enumerate([('独立完成','后台更新；无成功 Toast'),('UNKNOWN','保持隐藏；不重试、不删除'),('获准明确失败','仅安全准入后恢复普通截图')]):
    x=300+i*355;rect(x,757,330,116);text(x+18,799,a,22);text(x+18,840,b,17,MUTED)
arrow(1250,660,1250,716);arrow(1250,716,465,750);arrow(1250,716,820,750);arrow(1250,716,1175,750)
paragraph(72,943,'等待、动画结束、placeholder、权限允许，都不产生上传开始或成功。未来安全失败情境仅用于条件设计，本轮不开放该能力。',21,width=1260)
footer()

new('交给工程的最小改进清单','先完成现有正式集成，再以新的正式 SHA 判断哪些差额仍然存在。')
items=[('P0','Q01','首屏 / 结束页 / AX 文案与实际能力一致。保持三页也可先完成最小修复。'),('P1','Q02','单页可选快速开始；已可读目录不再重复请求，帮助主动展开。'),('P1','Q03','倒计时、本次 / 下一张模式、取消边界与捕获错误的现场说明。'),('P1','Q04','落实附近轻说明；保留下划线 / tooltip / AX，严格资产和版本归属。'),('P1','Q05','目录、入口录屏、Chrome Automation、浏览器设置与目标分开恢复。'),('P1','Q06','历史短时间与空状态；独立清晰预览，不改原图和上传素材。'),('P1','Q07','反馈服务与草稿状态分开；精确取消 / 删除 sheet；字符校验同口径。'),('P1','Q08','组字、保存中、保存失败时说明为何尚未关闭；不解除保护。'),('P2','Q09','已有设置内嵌、Feedback 窗口位置、标准设置快捷键。'),('P1 / P2','Q10','真实环境证据补齐；编号垫片按 1/backing 对齐，1x观感独立验收。')]
y=176
for pri,q,t in items:
    c.setStrokeColor(LINE);c.line(72,H-y-56,1368,H-y-56)
    text(72,y+22,pri,18,ACCENT);text(190,y+22,q,20);paragraph(280,y+22,t,20,width=1050,leading=29);y+=73
paragraph(72,962,'本轮只交付独立设计。所有原生接线、Controller / Main / Host / Feedback 变更等待集成结束；无需创始人参与 Beta。不得把整个设计分支合入产品工程。',20,width=1260,leading=29)
footer('完整工单含问题、影响、约束、验收与等待条件；按 ENGINEERING_CHECKLIST.md 执行')
assert page==20,page
c.save()
print(json.dumps({'pdf':str(OUT/'Riftlet-Experience-Review.pdf'),'pages':page,'bytes':(OUT/'Riftlet-Experience-Review.pdf').stat().st_size}))
