"""Build two offline-capable first-screen previews and their vector chart assets."""

from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parent
DOWNLOAD = "https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.5/Riftlet-1.0.5.dmg"
SERIES = [86, 91, 54, 78, 95]


def icon(name):
    shapes = {
        "download": '<path d="M10 2v10m-4-4 4 4 4-4M3 13v4h14v-4"/>',
        "reset": '<path d="M4 7a6.5 6.5 0 1 1-.5 5M4 3v4h4"/>',
        "pointer": '<path d="m2 2 3.5 16 3.8-5.2 5.5 5 2-2-5.5-5 6.4-1.2z" fill="#1b3029" stroke="#fffdf1" stroke-width="1.35"/>',
        "arrow": '<path d="M10 15V5m-5 5 5-5 5 5"/>',
        "play": '<path d="m7 4 9 6-9 6z" fill="currentColor" stroke="none"/>',
        "plus": '<path d="M4 10h12M10 4v12"/>',
    }
    return f'<svg aria-hidden="true" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">{shapes[name]}</svg>'


def trend(lang):
    days = (
        ["周一", "周二", "周三", "周四", "周五"] if lang == "zh-CN" else ["Mon", "Tue", "Wed", "Thu", "Fri"]
    )
    title = "分日趋势" if lang == "zh-CN" else "Daily trend"
    label = "本周" if lang == "zh-CN" else "THIS WEEK"
    xs = [48, 132, 216, 300, 384]
    ys = [round(158 - (n - 48) * 1.57) for n in SERIES]
    points = " ".join(f"{x},{y}" for x, y in zip(xs, ys))
    grid = "".join(f'<path d="M40 {y}H392" stroke="#dcdfd3" fill="none"/>' for y in [72, 104, 136, 165])
    labels = "".join(
        f'<text x="{x}" y="188" text-anchor="middle" font-size="12" fill="{"#b05237" if i == 2 else "#52655b"}">{day}</text>'
        for i, (x, day) in enumerate(zip(xs, days))
    )
    dots = "".join(
        f'<circle cx="{x}" cy="{y}" r="{5.4 if i == 2 else 3.5}" fill="{"#b75b3e" if i == 2 else "#246e5a"}" stroke="#fff" stroke-width="1.4"/><text x="{x}" y="{y - 11}" text-anchor="middle" fill="{"#9d452e" if i == 2 else "#365047"}" font-size="{17 if i == 2 else 13}" font-weight="600">{val}</text>'
        for i, (x, y, val) in enumerate(zip(xs, ys, SERIES))
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 202">
<defs><linearGradient id="a" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#91b99b" stop-opacity=".48"/><stop offset="1" stop-color="#dbe9d9" stop-opacity=".09"/></linearGradient></defs>
<rect width="432" height="202" rx="3" fill="#f8f7ef"/><g font-family="-apple-system, Helvetica Neue, Helvetica, PingFang SC, Arial, sans-serif">
<text x="28" y="34" font-size="21" font-weight="620" fill="#263d32">{title}</text><text x="404" y="31" text-anchor="end" font-size="10" letter-spacing="1.3" fill="#607266">{label}</text>
{grid}<rect x="200" y="56" width="32" height="109" rx="4" fill="#d17853" opacity=".10"/>
<polygon points="{xs[0]},165 {points} {xs[-1]},165" fill="url(#a)"/><polyline points="{points}" fill="none" stroke="#286d58" stroke-width="3.4" stroke-linejoin="round"/>{dots}{labels}</g></svg>'''


def page(zh):
    lang = "zh-CN" if zh else "en"

    def tr(c, e):
        return c if zh else e

    claim = tr("刚截的图，点一下就进 ChatGPT。", "Just took a screenshot? One click adds it to ChatGPT.")
    support = tr(
        "点屏幕边缘的缩略图，把刚截的图附加到 Chrome 中当前可编辑的 ChatGPT 草稿。",
        "Click its thumbnail at the edge of your Mac screen to attach it to your current ChatGPT draft in Chrome.",
    )
    title_lines = (
        "<span>刚截的图，</span><em>点一下就进</em><em>ChatGPT。</em>"
        if zh
        else "<span>Just took a </span><span>screenshot? </span><em>One click adds it </em><em>to ChatGPT.</em>"
    )
    thumb = tr("分日趋势", "Daily trend")
    overview = tr("周报总览", "Weekly overview")
    output = "index.html" if zh else "en.html"
    other = "en.html" if zh else "index.html"
    other_lang = "en" if zh else "zh-CN"
    image = "assets/trend-" + lang + ".svg"
    (ROOT / image).write_text(trend(lang))
    get = tr("下载 Mac 版", "Download for Mac")
    demo = tr("交互示意", "Interactive illustration")
    start = tr("点右侧的截图，试试附加。", "Click the screenshot at the right edge.")
    done = tr("分日趋势已附加。你可以接着写。", "Daily trend attached. Keep writing in the draft.")
    draft = tr("为什么周三下滑？", "Why did Wednesday dip?")
    og = f"../social/share/{lang}.jpg"
    return (
        output,
        f'''<!doctype html>
<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Riftlet — {claim}</title><meta name="description" content="{escape(support)}">
<meta property="og:type" content="website"><meta property="og:title" content="{claim}"><meta property="og:description" content="{escape(support)}">
<meta property="og:locale" content="{tr("zh_CN", "en_US")}"><meta property="og:image" content="{og}"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="{og}">
<link rel="icon" href="assets/riftlet.svg"><link rel="stylesheet" href="hero.css"><script defer src="hero.js"></script></head>
<body><header><nav class="nav" aria-label="{tr("页面导航", "Navigation")}"><a class="wordmark" href="#top"><img src="assets/riftlet.svg" alt="">Riftlet</a>
<a href="{other}" lang="en" hreflang="{other_lang}" class="switch">{tr("English", "Chinese")} <span aria-hidden="true">↗</span></a></nav></header>
<main id="top"><div class="copy"><div class="scope"><i aria-hidden="true"></i>{tr("Mac · Chrome 网页版 ChatGPT", "Mac · ChatGPT in Chrome")}</div>
<h1 aria-label="{claim}">{title_lines}</h1><p class="support">{support}</p>
<div class="cta"><a class="get" href="{DOWNLOAD}">{icon("download")}{get}</a><a class="watch" href="../film/{lang}/master.mp4">{icon("play")}{tr("观看 20 秒短片", "Watch the 20s film")}</a></div><div class="spec">macOS 13+ · Apple silicon · Intel</div></div>
<section class="demo" data-start="{start}" data-done="{done}" aria-label="{demo}"><div class="desk">
<div class="desk-top"><span>{tr("周报工作台", "Weekly report")}</span><span>{demo}</span></div>
<div class="chart"><img src="{image}" alt="{tr("分日趋势：周一 86，周二 91，周三 54，周四 78，周五 95。", "Daily trend: Monday 86, Tuesday 91, Wednesday 54, Thursday 78, Friday 95.")}"></div>
<div class="edge-line"></div><button type="button" class="edge" aria-label="{tr("点选边缘截图，将分日趋势附加到草稿", "Click the edge screenshot to attach Daily trend to the draft")}" aria-describedby="state"><img src="{image}" alt="">{icon("pointer")}</button>
<div class="draft"><div class="draft-head"><strong>ChatGPT</strong><span>{tr("当前草稿", "Current draft")}</span></div>
<div class="attachments"><figure class="old"><img src="assets/overview.svg" alt=""><figcaption>{overview}</figcaption></figure><figure class="new" hidden><img src="{image}" alt=""><figcaption>{thumb}</figcaption></figure></div>
<textarea aria-label="{tr("未发送的草稿，可继续输入", "Unsent draft, editable")}" rows="1" spellcheck="false">{draft}</textarea>
<div class="tools" aria-hidden="true">{icon("plus")}<span class="unsent">{icon("arrow")}</span></div></div>
</div><div class="demo-foot"><p id="state" role="status">{start}</p>
<button type="button" class="reset" aria-label="{tr("重置示意", "Reset illustration")}" title="{tr("重置示意", "Reset illustration")}">{icon("reset")}</button></div></section>
</main><footer class="promise"><b>{tr("原来的问题还在。", "Keep the question.")}</b><span>{tr("已有附件也保留，继续输入，发送由你。", "Your existing attachments stay, too. Keep typing and send when you choose.")}</span></footer>
</body></html>''',
    )


for is_chinese in (True, False):
    name, data = page(is_chinese)
    (ROOT / name).write_text(data)
