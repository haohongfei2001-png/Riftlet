"""Regenerate the public fictional data and chart artwork used across the campaign."""

from pathlib import Path

import resvg_py

DEST = Path(__file__).resolve().parents[1] / "capture-props"
VALUES = (86, 91, 54, 78, 95)
GREEN, ACCENT, INK = "#147D70", "#CA623F", "#193D38"


def chart(lang):
    chinese = lang == "zh-CN"
    title = "分日访问量" if chinese else "Visits by day"
    top = "本周流量周报" if chinese else "Weekly traffic report"
    unit = "访问次数" if chinese else "Visits"
    days = ("周一", "周二", "周三", "周四", "周五") if chinese else ("Mon", "Tue", "Wed", "Thu", "Fri")
    xx = (108, 302, 496, 690, 884)
    yy = tuple(490 - int(v * 2.8) for v in VALUES)
    pts = " ".join(f"{x},{y}" for x, y in zip(xx, yy))
    pieces = [
        f'''<svg xmlns="http://www.w3.org/2000/svg" width="960" height="600" viewBox="0 0 960 600">
<title>{title}</title>
<rect width="960" height="600" fill="#F7F7EF"/>
<g font-family="Helvetica Neue, Heiti SC, sans-serif" fill="{INK}">
<rect x="55" y="56" width="11" height="11" rx="3" fill="{GREEN}"/>
<text x="79" y="69" font-size="21">{top}</text>
<text x="51" y="146" font-size="57" font-weight="bold">{title}</text>
<text x="884" y="143" text-anchor="end" font-size="19" fill="#537970">{unit}</text>'''
    ]
    for value in (0, 25, 50, 75, 100):
        y = 490 - int(value * 2.8)
        pieces.append(
            f'<path d="M92 {y}H887" stroke="#DBE3D8" stroke-width="1.3"/><text x="76" y="{y + 5}" text-anchor="end" font-size="16" fill="#688276">{value}</text>'
        )
    pieces.append(
        f'<polygon points="108,490 {pts} 884,490" fill="#2B9D81" opacity=".085"/><polyline points="{pts}" fill="none" stroke="{GREEN}" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>'
    )
    for i, (x, y, val, day) in enumerate(zip(xx, yy, VALUES, days)):
        color = ACCENT if i == 2 else GREEN
        if i == 2:
            pieces.append(
                f'<path d="M{x} {y + 13}V490" stroke="#CA623F" opacity=".55" stroke-width="1.7" stroke-dasharray="4 6"/><circle cx="{x}" cy="{y}" r="18" fill="#F4D9BE"/>'
            )
        pieces.append(
            f'<circle cx="{x}" cy="{y}" r="{9 if i == 2 else 6}" fill="{color}" stroke="#F7F7EF" stroke-width="2"/><text x="{x}" y="{y - 21}" text-anchor="middle" font-size="30" font-weight="bold" fill="{color}">{val}</text><text x="{x}" y="535" text-anchor="middle" font-size="23" fill="{color if i == 2 else INK}">{day}</text>'
        )
    return "".join(pieces) + "</g></svg>"


def overview(lang):
    chinese = lang == "zh-CN"
    top = "流量周报" if chinese else "Traffic report"
    title = "五日总览" if chinese else "Week at a glance"
    detail = "周一至周五 · 总访问次数" if chinese else "Mon–Fri · total visits"
    bits = [
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="960" height="600">
<rect width="960" height="600" fill="#F4D0A2"/>
<g font-family="Helvetica Neue, Heiti SC, sans-serif" fill="#4E3528">
<text x="58" y="72" font-size="23">{top}</text><path d="M58 101H902" stroke="#B99574"/>
<text x="54" y="199" font-size="62" font-weight="bold">{title}</text>
<text x="51" y="384" font-size="159" font-weight="bold">{sum(VALUES)}</text>
<text x="59" y="455" font-size="27">{detail}</text>"""
    ]
    for i, val in enumerate(VALUES):
        height = val * 2.25
        bits.append(
            f'<rect x="{580 + i * 63}" y="{454 - height}" width="45" height="{height}" rx="5" fill="{ACCENT if i == 2 else "#93765B"}"/>'
        )
    return "".join(bits) + "</g></svg>"


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    fonts = Path("/System/Library/Fonts")
    for lang in ("zh-CN", "en"):
        (DEST / f"trend-{lang}.svg").write_text(chart(lang))
        png = resvg_py.svg_to_bytes(
            svg_string=overview(lang),
            font_files=[str(fonts / "HelveticaNeue.ttc"), str(fonts / "STHeiti Medium.ttc")],
            sans_serif_family="Helvetica Neue",
        )
        (DEST / f"overview-{lang}.png").write_bytes(png)


if __name__ == "__main__":
    main()
