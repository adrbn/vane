#!/usr/bin/env python3
"""Builds the README art from real captures of Vane's demo window.

    python3 docs/assets/make_svgs.py [ticker|blocks]

Sources: docs/assets/readme-src/<theme>/*.jpg, made from full captures by `prep` (Pillow) the first time:
    python3 docs/assets/make_svgs.py prep <captures folder>
Everything else is stdlib. Output: docs/assets/<theme>/*.svg.
"""
import base64
import sys
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "readme-src"
FONT = "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue','PingFang SC','Noto Sans CJK SC',Arial,sans-serif"
EASE = ".45 0 .25 1"
WIN = 1360 / 926  # window aspect (points)

THEMES = {
    "ticker": dict(accent="#30D158", on_accent="#000000", pos="#30D158", neg="#FF453A",
                   pos_light="#1F9D45", neg_light="#D93025", card="#161618", card_edge="#2C2C2E",
                   card_fg="#FFFFFF", card_fg2="#8E8E93"),
    "blocks": dict(accent="#4433E0", on_accent="#FFFFFF", pos="#4BD08A", neg="#FF6B6B",
                   pos_light="#12804A", neg_light="#D93025", card="#FFFFFF", card_edge="#E4E3EA",
                   card_fg="#111111", card_fg2="#62626C"),
}

# Real numbers from the demo app "Cadence: Practice Timer", last 90 days (App Store and Usage screens).
TAPE = [("First-time downloads", "12,553", "+5.3%", True), ("Impressions", "736.1K", "+15.8%", True),
        ("Page views", "74.7K", "+4.7%", True), ("Tap-through rate", "10.1%", "−1.1 pts", False),
        ("Redownloads", "4,184", "+5.3%", True), ("Conversion rate", "22.4%", "+0.1 pts", True),
        ("Sessions", "383,756", "+9.9%", True), ("Crashes", "726", "+27.3%", False),
        ("Active subscriptions", "330", "+8.2%", True)]

HERO = [("appstore", "App Store", "the whole funnel on one screen"),
        ("insights", "Insights", "what changed, in plain words"),
        ("m-first_downloads", "Every metric", "7 days to a year, day by day"),
        ("territories", "Territories", "where your downloads come from")]

# name: (capture, title, subtitle, panel box in % of the window: x0, y0, x1, y1). Boxes sit on the app's own
# gutters, so the zoom frames one whole panel and never cuts a line of text.
CARDS = {
    "ticker": [("insights", "Insights", "Drops, milestones, keyword waste", (69.5, 41.8, 98.6, 71.8)),
               ("m-first_downloads", "Every metric", "Same period as the tile you clicked", (8.5, 8, 42, 28.5)),
               ("territories", "Territories", "Downloads by country, growth floor", (18.5, 8, 69, 47)),
               ("reviews", "Reviews", "Reply, translate, by version", (9.5, 7.5, 60, 44.5)),
               ("listing", "Listing", "Edit metadata, see it in search", (9, 17.5, 26.8, 50)),
               ("report", "Reports", "Weekly, monthly, yearly; PDF", (1, 1.5, 40.2, 27.5))],
    "blocks": [("insights", "Insights", "Drops, milestones, keyword waste", (72.5, 41, 98.6, 71.8)),
               ("m-first_downloads", "Every metric", "Same period as the tile you clicked", (19, 8.5, 66, 30.5)),
               ("territories", "Territories", "Downloads by country, growth floor", (24, 8, 72, 47)),
               ("reviews", "Reviews", "Reply, translate, by version", (19, 7.5, 68, 44.5)),
               ("listing", "Listing", "Edit metadata, see it in search", (19.3, 18, 36.8, 50)),
               ("report", "Reports", "Weekly, monthly, yearly; PDF", (1, 1.5, 40.2, 27.5))],
}

ICONS = {
    "download": "M12 3.5v11.5M7 10.5l5 5 5-5M4.5 20h15",
    "grid": "M4 4h6.5v6.5H4zM13.5 4H20v6.5h-6.5zM4 13.5h6.5V20H4zM13.5 13.5H20V20h-6.5z",
    "lock": "M7.5 11V8a4.5 4.5 0 0 1 9 0v3M5.5 11h13v9.5h-13z",
    "code": "M8 7l-5 5 5 5M16 7l5 5-5 5M14 4.5l-4 15",
}

REG = {c: w for c, w in zip("abcdefghijklmnopqrstuvwxyz", [556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500,
                                                          222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500,
                                                          722, 500, 500, 500])}
REG.update({c: 680 for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"})
REG.update({c: 556 for c in "0123456789"})
REG.update({" ": 278, ".": 278, ",": 278, "-": 333, "+": 584, "−": 584, "%": 889, "'": 238, ";": 278, "·": 278})


def width(s, size, bold=False):
    # CJK glyphs are a full em wide.
    return sum(920 if ord(c) >= 0x2E80 else REG.get(c, 600) for c in s) / 1000 * size * (1.07 if bold else 1)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size, fill, weight=400, anchor=None, extra=""):
    a = f' text-anchor="{anchor}"' if anchor else ""
    return (f'<text x="{x:g}" y="{y:g}" font-family="{FONT}" font-size="{size:g}" font-weight="{weight}" '
            f'fill="{fill}"{a}{extra}>{esc(s)}</text>')


def svg(w, h, body, title, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}" '
            f'role="img"><title>{esc(title)}</title>{f"<defs>{defs}</defs>" if defs else ""}{body}</svg>\n')


def anim(attr, kf, total, tag="animate", extra="", ease=True):
    times = ";".join(f"{t / total:.4f}" for t, _ in kf)
    vals = ";".join(str(v) for _, v in kf)
    mode = f'calcMode="spline" keySplines="{";".join([EASE] * (len(kf) - 1))}"' if ease else 'calcMode="linear"'
    return (f'<{tag} attributeName="{attr}" values="{vals}" keyTimes="{times}" dur="{total:g}s" {mode} '
            f'repeatCount="indefinite"{extra}/>')


def uri(name, theme):
    return "data:image/jpeg;base64," + base64.b64encode((SRC / theme / f"{name}.jpg").read_bytes()).decode()


# --- hero -------------------------------------------------------------------------------------------------
def tape(y, light, t):
    fg, fg2 = ("#111111", "#6E6E73") if light else ("#FFFFFF", "#8E8E93")
    pos, neg = (t["pos_light"], t["neg_light"]) if light else (t["pos"], t["neg"])
    parts, x = [], 0.0
    for name, value, change, good in TAPE:
        parts.append(text(x, y, name, 15, fg2))
        x += width(name, 15) + 8
        parts.append(text(x, y, value, 15, fg, 600))
        x += width(value, 15, True) + 7
        parts.append(text(x, y, change, 15, pos if good else neg, 600))
        x += width(change, 15, True) + 40
    loop = x
    row = "".join(parts)
    move = anim("transform", [(0, "0 0"), (60, f"{-loop:g} 0")], 60, "animateTransform", ' type="translate"',
                ease=False)
    return f'<g>{move}<g>{row}</g><g transform="translate({loop:g} 0)">{row}</g></g>'


def hero(theme, light):
    t = THEMES[theme]
    W, ww = 1280, 1104
    wh = round(ww / WIN)
    x0, y0 = (W - ww) / 2, 28
    bg = "#FFFFFF" if light else "#0B0B0C"
    fg, fg2 = ("#111111", "#6E6E73") if light else ("#FFFFFF", "#8E8E93")
    total, step = 20, 5
    imgs = []
    for i, (cap, *_), in enumerate(HERO):
        src = f"{theme}-{cap}" if cap != "appstore" else f"appstore-{theme}"
        if i == 0:
            op = ""
        elif i < len(HERO) - 1:
            a = i * step
            op = anim("opacity", [(0, 0), (a - 1, 0), (a, 1), (a + step, 1), (a + step, 0), (total, 0)], total)
        else:
            a = i * step
            op = anim("opacity", [(0, 0), (a - 1, 0), (a, 1), (total - 1, 1), (total, 0)], total)
        imgs.append(f'<image href="{uri(src, theme)}" x="{x0:g}" y="{y0}" width="{ww}" height="{wh}" '
                    f'preserveAspectRatio="xMidYMid slice" opacity="{1 if i == 0 else 0}">{op}</image>')
    caps = []
    cy = y0 + wh + 40
    for i, (_, title, sub) in enumerate(HERO):
        a = i * step
        if i == 0:
            kf = [(0, 1), (step - 1, 1), (step, 0), (total - 1, 0), (total, 1)]
        else:
            kf = [(0, 0), (a - 1, 0), (a, 1), (a + step - 1, 1), (a + step, 0), (total, 0)]
            if i == len(HERO) - 1:
                kf = [(0, 0), (a - 1, 0), (a, 1), (total - 1, 1), (total, 0)]
        tw = width(title, 17, True) + 10 + width(sub, 17)
        caps.append(f'<g opacity="{1 if i == 0 else 0}">{anim("opacity", kf, total)}'
                    + text(W / 2 - tw / 2, cy, title, 17, fg, 700)
                    + text(W / 2 - tw / 2 + width(title, 17, True) + 10, cy, sub, 17, fg2) + '</g>')
    ty = cy + 50
    H = ty + 30
    edge = "#E4E3EA" if light else "#26262A"
    defs = (f'<clipPath id="win"><rect x="{x0:g}" y="{y0}" width="{ww}" height="{wh}" rx="22"/></clipPath>'
            f'<clipPath id="tape"><rect x="0" y="{ty - 24}" width="{W}" height="40"/></clipPath>'
            f'<linearGradient id="fade" x1="0" x2="1"><stop offset="0" stop-color="{bg}"/>'
            f'<stop offset=".08" stop-color="{bg}" stop-opacity="0"/><stop offset=".92" stop-color="{bg}" '
            f'stop-opacity="0"/><stop offset="1" stop-color="{bg}"/></linearGradient>'
            f'<filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="18" '
            f'stdDeviation="24" flood-color="#000" flood-opacity="{.16 if light else .5}"/></filter>')
    body = (f'<rect width="{W}" height="{H}" fill="{bg}"/>'
            f'<rect x="{x0:g}" y="{y0}" width="{ww}" height="{wh}" rx="22" fill="{bg}" filter="url(#sh)"/>'
            f'<g clip-path="url(#win)">{"".join(imgs)}</g>'
            f'<rect x="{x0 - .5:g}" y="{y0 - .5}" width="{ww + 1}" height="{wh + 1}" rx="22.5" fill="none" '
            f'stroke="{edge}"/>' + "".join(caps)
            + f'<line x1="{x0:g}" x2="{x0 + ww:g}" y1="{ty - 30}" y2="{ty - 30}" stroke="{edge}"/>'
            + f'<g clip-path="url(#tape)"><g transform="translate({x0:g} 0)">{tape(ty, light, t)}</g></g>'
            + f'<rect x="0" y="{ty - 24}" width="{W}" height="40" fill="url(#fade)"/>')
    return svg(W, H, body, "Vane: App Store Connect analytics on the Mac, with demo data", defs)


# --- cards ------------------------------------------------------------------------------------------------
def card(theme, i, spec):
    """The whole window first, cut out on the card; then a zoom onto one panel, framed to its edges."""
    t = THEMES[theme]
    cap, title, sub, (x0, y0, x1, y1) = spec
    W, H, ix, iy, iw = 400, 352, 16, 86, 368
    ih = round(iw / WIN, 1)
    src = f"{theme}-{cap}"
    ih_img = iw / (980 / 860) if cap == "report" else ih  # the report window is taller; its top shows
    rx, ry, rw, rh = x0 / 100 * iw, y0 / 100 * ih_img, (x1 - x0) / 100 * iw, (y1 - y0) / 100 * ih_img
    s0 = .92 if cap != "report" else .92 * ih / ih_img * 1.0
    s0 = min(s0, ih * .92 / ih_img)
    p0 = ((iw - iw * s0) / 2, (ih - ih_img * s0) / 2)
    s1 = min(iw / rw, ih / rh) * .94
    p1 = (iw / 2 - s1 * (rx + rw / 2), ih / 2 - s1 * (ry + rh / 2))
    c1 = (ix + (iw - rw * s1) / 2, iy + (ih - rh * s1) / 2, rw * s1, rh * s1)
    c0 = (ix + p0[0], iy + p0[1], iw * s0, ih_img * s0)
    total = 12
    kf = lambda a, b: [(0, a), (2.5, a), (4.5, b), (9, b), (11, a), (total, a)]
    f = lambda v: f"{v:.1f}"
    move = anim("transform", kf(f"{f(p0[0])} {f(p0[1])}", f"{f(p1[0])} {f(p1[1])}"), total, "animateTransform",
                ' type="translate"')
    scale = anim("transform", kf(f"{s0:.3f}", f"{s1:.3f}"), total, "animateTransform", ' type="scale"')
    box = "".join(anim(a, kf(f(v0), f(v1)), total) for a, v0, v1 in zip(("x", "y", "width", "height"), c0, c1))
    r0, r1 = 14 * s0, 12
    rr = anim("rx", kf(f(r0), f(r1)), total)
    defs = (f'<clipPath id="c{i}"><rect x="{f(c0[0])}" y="{f(c0[1])}" width="{f(c0[2])}" height="{f(c0[3])}" '
            f'rx="{f(r0)}">{box}{rr}</rect></clipPath>')
    body = (f'<rect x=".5" y=".5" width="{W - 1}" height="{H - 1}" rx="20" fill="{t["card"]}" '
            f'stroke="{t["card_edge"]}"/>'
            + text(24, 44, title, 20, t["card_fg"], 700) + text(24, 68, sub, 14, t["card_fg2"])
            + f'<g clip-path="url(#c{i})"><g transform="translate({ix} {iy})"><g transform="translate({f(p0[0])} '
            f'{f(p0[1])})">{move}<g transform="scale({s0:.3f})">{scale}'
            f'<image href="{uri(src, theme)}" width="{iw}" height="{ih_img:.1f}"/></g></g></g></g>'
            f'<rect x="{f(c0[0])}" y="{f(c0[1])}" width="{f(c0[2])}" height="{f(c0[3])}" rx="{f(r0)}" fill="none" '
            f'stroke="{t["card_edge"]}" stroke-width="1.5">{box}{rr}</rect>')
    return svg(W, H, body, f"{title}: {sub}", defs)


# --- buttons ----------------------------------------------------------------------------------------------
def button(theme, icon, label, primary):
    t = THEMES[theme]
    tw = width(label, 15, True)
    w, h = round(tw + 64), 44
    bg, fg, edge, ic = ((t["accent"], t["on_accent"], t["accent"], t["on_accent"]) if primary
                        else ("#141416", "#F2F2F2", "#2E2E33", t["accent"]))
    body = (f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{h / 2 - .5}" fill="{bg}" stroke="{edge}"/>'
            f'<path transform="translate(18 12.5) scale(.79)" d="{ICONS[icon]}" fill="none" stroke="{ic}" '
            f'stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'
            + text(46, 27.5, label, 15, fg, 600, extra=f' textLength="{tw:.0f}" lengthAdjust="spacing"'))
    return svg(w, h, body, label)


KOFI = {"en": ("Buy me a coffee", "Support Vane on Ko-fi"), "fr": ("Offrir un café", "Soutenir Vane sur Ko-fi"),
        "es": ("Invítame a un café", "Apoya Vane en Ko-fi"), "zh": ("请我喝杯咖啡", "在 Ko-fi 上支持 Vane")}
BUTTONS = [("download", True, {"en": "Download for Mac", "fr": "Télécharger pour Mac",
                                "es": "Descargar para Mac", "zh": "下载 Mac 版"}),
           ("grid", False, {"en": "What it does", "fr": "Ce qu'elle fait", "es": "Qué hace", "zh": "功能"}),
           ("lock", False, {"en": "Privacy", "fr": "Confidentialité", "es": "Privacidad", "zh": "隐私"}),
           ("code", False, {"en": "Source", "fr": "Code source", "es": "Código fuente", "zh": "源代码"})]


def suffix(lang):
    return "" if lang == "en" else f"-{lang}"


def kofi(lang):
    top, sub = KOFI[lang]
    tw = max(width(top, 18, True), width(sub, 13))
    h = 64
    w = round(16 + 44 + 14 + tw + 50)
    cx, cy = 38, h / 2
    cup = (f'<g transform="translate({cx} {cy + 2})" fill="none" stroke="#fff" stroke-width="2.4" '
           f'stroke-linecap="round" stroke-linejoin="round"><path d="M-10 -6H6V3A7 7 0 0 1 -1 10H-3A7 7 0 0 1 -10 3Z" '
           f'fill="#fff"/><path d="M6 -3H8.5A3.5 3.5 0 0 1 8.5 4H6"/></g>')
    body = (f'<rect width="{w}" height="{h}" rx="{h / 2}" fill="#FF5E5B"/>'
            f'<circle cx="{cx}" cy="{cy}" r="21" fill="#fff" fill-opacity=".2"/>' + cup
            + text(74, 29, top, 18, "#fff", 700) + text(74, 47, sub, 13, "#fff", 500, extra=' fill-opacity=".9"')
            + f'<path d="M{w - 28} {h / 2 - 6}l6 6-6 6" fill="none" stroke="#fff" stroke-width="2.4" '
            f'stroke-linecap="round" stroke-linejoin="round" opacity=".85"/>')
    return svg(w, h, body, f"{top} on Ko-fi")


# --- prep (Pillow) -----------------------------------------------------------------------------------------
def prep(captures):
    from PIL import Image
    cap = Path(captures)
    for theme in THEMES:
        out = SRC / theme
        out.mkdir(parents=True, exist_ok=True)
        names = {f"appstore-{theme}"} | {f"{theme}-{c[0]}" for c in HERO[1:]} | {f"{theme}-{c[0]}" for c in CARDS[theme]}
        for n in sorted(names):
            im = Image.open(cap / f"{n}.png").convert("RGBA")
            flat = Image.new("RGB", im.size, (22, 22, 24) if theme == "ticker" else (255, 255, 255))
            flat.paste(im, mask=im.split()[3])
            wide = 1500 if n.startswith("appstore") or any(n.endswith(c[0]) for c in HERO) else 1300
            flat.thumbnail((wide, wide))
            flat.save(out / f"{n}.jpg", quality=80, optimize=True, progressive=True)
    shots = ROOT / "shots"
    shots.mkdir(exist_ok=True)
    for n in ["appstore-ticker", "appstore-blocks", "appstore-nocturne", "appstore-candy", "ticker-sales",
              "blocks-sales", "ticker-usage", "blocks-usage"]:
        im = Image.open(cap / f"{n}.png").convert("RGBA")
        flat = Image.new("RGB", im.size, (255, 255, 255))
        flat.paste(im, mask=im.split()[3])
        flat.thumbnail((1200, 1200))
        flat.save(shots / f"{n}.jpg", quality=82, optimize=True, progressive=True)


def build(theme):
    out = ROOT / theme
    out.mkdir(exist_ok=True)
    (out / "hero.svg").write_text(hero(theme, False))
    (out / "hero-light.svg").write_text(hero(theme, True))
    for i, spec in enumerate(CARDS[theme]):
        (out / f"card-{spec[0].replace('m-first_downloads', 'metrics')}.svg").write_text(card(theme, i, spec))
    for icon, primary, labels in BUTTONS:
        for lang, label in labels.items():
            (out / f"btn-{icon}{suffix(lang)}.svg").write_text(button(theme, icon, label, primary))
    for lang in KOFI:
        (ROOT / f"kofi{suffix(lang)}.svg").write_text(kofi(lang))


if __name__ == "__main__":
    if sys.argv[1:2] == ["prep"]:
        prep(sys.argv[2])
    else:
        for th in (sys.argv[1:] or ["blocks"]):
            build(th)
