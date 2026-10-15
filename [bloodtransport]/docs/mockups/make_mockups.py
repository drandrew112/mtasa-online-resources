"""Renders the Blood Transport UI mockups (PNG, 1920x1080) next to this file.
Usage: python make_mockups.py     (needs Pillow; fonts and the radar map come from the repo)"""
import os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FONT_R = os.path.join(RES, "[core]", "v_inventory", "client", "fonts", "Roboto.ttf")
FONT_B = os.path.join(RES, "[core]", "v_inventory", "client", "fonts", "RobotoB.ttf")
RADAR = os.path.join(RES, "[ui]", "v_radar", "radar", "files", "radar.png")

W, H = 1920, 1080
BG = (16, 18, 24); HEAD = (22, 26, 34); TILE = (28, 31, 40); TILE2 = (36, 40, 52)
ACC = (215, 55, 65); TEXT = (235, 238, 245); MUTED = (140, 146, 160); OFF = (95, 100, 112)
GOOD = (80, 210, 120); WARN = (255, 185, 60); BAD = (235, 70, 70); BLUE = (0, 140, 200)
KEY = (240, 184, 74); PURPLE = (180, 120, 230); ORANGE = (230, 150, 60); LINE = (42, 50, 60)

_fonts = {}
def F(size, bold=False):
    k = (size, bold)
    if k not in _fonts:
        _fonts[k] = ImageFont.truetype(FONT_B if bold else FONT_R, size)
    return _fonts[k]

FONT_SYM = r"C:\Windows\Fonts\seguisym.ttf"
_fb = {}
def FB(size, bold=False):
    if size not in _fb:
        _fb[size] = ImageFont.truetype(FONT_SYM, size)
    return _fb[size]

_glyph = {}
def has_glyph(font, ch):
    k = (id(font), ch)
    if k not in _glyph:
        if ord(ch) < 0x250:
            _glyph[k] = True
        else:
            m = (font.getbbox(ch), font.getlength(ch)); n = (font.getbbox("￿"), font.getlength("￿"))
            _glyph[k] = m != n
    return _glyph[k]


class Canvas:
    def __init__(self, base=None):
        self.im = (base or Image.new("RGB", (W, H), BG)).convert("RGB")
        self.d = ImageDraw.Draw(self.im)

    def rr(self, box, r=8, fill=None, outline=None, width=1, alpha=255):
        x0, y0, x1, y1 = [int(v) for v in box]
        w, h = x1 - x0, y1 - y0
        if w <= 0 or h <= 0: return
        patch = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        pd = ImageDraw.Draw(patch)
        f = (fill + (alpha,)) if fill else None
        o = (outline + (255,)) if outline else None
        pd.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=f, outline=o, width=width)
        self.im.paste(patch, (x0, y0), patch)

    def t(self, xy, s, size=14, bold=False, fill=TEXT, anchor="la"):
        f = F(size, bold)
        if all(has_glyph(f, ch) for ch in s):
            self.d.text(xy, s, font=f, fill=fill, anchor=anchor)
            return
        # symbols Roboto lacks (arrows, triangles, check) come from Segoe UI Symbol
        fb = FB(size, bold)
        segs = [(ch, f if has_glyph(f, ch) else fb) for ch in s]
        total = sum(self.d.textlength(ch, font=fn) for ch, fn in segs)
        x, y = xy
        if anchor[0] == "m": x -= total / 2
        elif anchor[0] == "r": x -= total
        asc, desc = f.getmetrics()
        if anchor[1] == "a": base = y + asc
        elif anchor[1] == "m": base = y + (asc - desc) / 2
        else: base = y
        for ch, fn in segs:
            self.d.text((x, base), ch, font=fn, fill=fill, anchor="ls")
            x += self.d.textlength(ch, font=fn)

    def tw(self, s, size=14, bold=False):
        f = F(size, bold)
        return sum(self.d.textlength(ch, font=(f if has_glyph(f, ch) else FB(size, bold))) for ch in s)

    def chip(self, x, y, label, color, size=11, filled=False, anchor="l"):
        w = self.tw(label, size, True) + 14
        h = size + 9
        if anchor == "r": x = x - w
        if filled:
            self.rr((x, y, x + w, y + h), 4, fill=color)
            self.t((x + w / 2, y + h / 2), label, size, True, (20, 20, 24), "mm")
        else:
            self.rr((x, y, x + w, y + h), 4, fill=color, alpha=40, outline=color)
            self.t((x + w / 2, y + h / 2), label, size, True, color, "mm")
        return w

    def key(self, x, y, label, size=12):
        w = self.tw(label, size, True) + 14
        self.rr((x, y, x + w, y + size + 9), 4, fill=KEY)
        self.t((x + w / 2, y + (size + 9) / 2), label, size, True, (30, 24, 10), "mm")
        return w

    def tile(self, x, y, s, label, color, size=15):
        self.rr((x, y, x + s, y + s), 6, fill=color)
        self.t((x + s / 2, y + s / 2), label, size, True, (255, 255, 255), "mm")

    def btn(self, x, y, w, h, label, kind="n", size=13):
        fills = {"n": (TILE2, TEXT, LINE), "p": (ACC, (255, 255, 255), ACC), "g": (None, GOOD, GOOD),
                 "w": (None, WARN, WARN), "off": (TILE, OFF, TILE), "b": (None, BLUE, BLUE)}
        f, c, o = fills[kind]
        self.rr((x, y, x + w, y + h), 6, fill=f or c, alpha=255 if f else 34, outline=o)
        self.t((x + w / 2, y + h / 2), label, size, True, c, "mm")

    def label(self, s):
        self.rr((24, 24, 24 + self.tw(s, 22, True) + 32, 70), 8, fill=(8, 9, 12), alpha=235)
        self.t((40, 47), s, 22, True, TEXT, "lm")

    def cursor(self, x, y):
        pts = [(x, y), (x, y + 24), (x + 6, y + 18), (x + 11, y + 29), (x + 15, y + 27), (x + 10, y + 17), (x + 18, y + 17)]
        self.d.polygon(pts, fill=(255, 255, 255), outline=(0, 0, 0))

    def save(self, name):
        self.im.save(os.path.join(HERE, name), optimize=True)
        print("saved", name)


def scene():
    """Dusk city backdrop (blurred blocks) for the in-game mockups."""
    random.seed(7)
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        d.line((0, y, W, y), fill=(int(38 + 40 * t), int(48 + 30 * t), int(78 - 20 * t)))
    for _ in range(40):
        x = random.randint(-50, W); w = random.randint(80, 220); h = random.randint(150, 520)
        c = random.randint(18, 40)
        d.rectangle((x, 700 - h, x + w, 760), fill=(c, c + 4, c + 14))
        for _ in range(random.randint(3, 12)):
            wx = random.randint(x + 6, x + w - 12); wy = random.randint(700 - h + 10, 740)
            d.rectangle((wx, wy, wx + 6, wy + 8), fill=(200, 170, 90))
    d.rectangle((0, 760, W, H), fill=(36, 38, 44))
    d.rectangle((0, 760, W, 772), fill=(60, 62, 70))
    for x in range(0, W, 140):
        d.rectangle((x, 905, x + 70, 913), fill=(190, 190, 170))
    return im.filter(ImageFilter.GaussianBlur(6))


# ------------------------------------------------------------------------------------------ data
TYPES = {   # code, colour, name
    "ffp": ("FF", (200, 40, 60)), "rbc": ("RB", (200, 40, 60)), "plt": ("PL", (220, 100, 70)),
    "lab": ("LB", ORANGE), "med": ("MD", PURPLE),
}
TASKS = [
    dict(id="T-1042", type="rbc", what="RBC 0−  ×4", route="LS Blood Bank → All Saints General", tag=("URGENT", BAD), st="TRANSIT"),
    dict(id="T-1039", type="plt", what="Platelets B+  ×3", route="LS Blood Bank → Country General", tag=("PLANNED", BLUE), st="TRANSIT"),
    dict(id="T-1043", type="ffp", what="FFP A+  ×2", route="LS Blood Bank → Country General", tag=("URGENT", BAD), st="WAITING"),
    dict(id="T-1044", type="lab", what="Lab sample  ×1", route="Country General → LS Blood Bank", tag=("LAB", ORANGE), st="WAITING"),
    dict(id="T-1046", type="rbc", what="RBC A−  ×6", route="LS Blood Bank → All Saints General", tag=("RESUPPLY", MUTED), st="WAITING"),
]
STC = {"TRANSIT": WARN, "WAITING": BLUE, "DELIVERED": GOOD, "CANCELLED": OFF}


# ------------------------------------------------------------------------------------------ 01 HUD
def hud_card(c, x, y, w, on_duty, tasks, big=False):
    rows = len(tasks)
    h = 96 + (rows * 62 + 30 if on_duty else 40)
    c.rr((x, y, x + w, y + h), 10, fill=BG, alpha=232)
    c.rr((x, y, x + w, y + 4), 2, fill=ACC)
    c.rr((x, y + 4, x + w, y + 70), 0, fill=HEAD)
    c.t((x + 18, y + 22), "BLOOD TRANSPORT", 12, True, MUTED)
    if on_duty:
        c.t((x + 18, y + 46), "BT-4821", 20, True, TEXT)
        c.chip(x + 18 + c.tw("BT-4821", 20, True) + 12, y + 46, "ON DUTY", GOOD)
    else:
        c.t((x + 18, y + 46), "Off duty", 20, True, MUTED)
    kx = x + w - 18
    wk = c.tw("F6", 12, True) + 14
    c.key(kx - wk - c.tw("Expand", 12) - 8, y + 24, "F6")
    c.t((kx, y + 24 + 10), "Expand", 12, False, MUTED, "rm")
    yy = y + 84
    if not on_duty:
        c.t((x + 18, yy + 6), "Press F6, get in your BT- ambulance and sign on.", 13, False, MUTED)
        return h
    c.t((x + 18, yy), "IN TRANSIT", 11, True, MUTED)
    c.t((x + w - 18, yy), str(rows), 11, True, MUTED, "ra")
    yy += 22
    for t in tasks:
        col = TYPES[t["type"]][1]
        c.rr((x + 12, yy, x + w - 12, yy + 54), 6, fill=TILE)
        c.tile(x + 18, yy + 9, 36, TYPES[t["type"]][0], col, 14)
        c.t((x + 64, yy + 9), t["route"].replace(" General", ""), 14, True)
        c.t((x + 64, yy + 30), t["what"], 12, False, MUTED)
        c.chip(x + w - 20, yy + 17, "TRANSIT", WARN, 10, anchor="r")
        yy += 62
    return h


def m01():
    c = Canvas(scene())
    c.label("01 · Bottom-right panel – small view (always on for players with the transporter right)")
    # minimap stub
    c.d.ellipse((50, 790, 330, 1070), fill=(24, 60, 70), outline=(230, 230, 230), width=4)
    c.d.line((90, 1000, 190, 940, 250, 860), fill=(200, 200, 200), width=6)
    c.d.line((190, 940, 250, 860, 290, 830), fill=BAD, width=4)
    c.d.ellipse((284, 824, 298, 838), fill=BAD)
    c.d.polygon([(185, 930), (195, 930), (190, 916)], fill=(250, 250, 250))
    c.t((190, 1075), "", 10)
    # on-duty panel
    hud_card(c, W - 30 - 390, 1080 - 30 - 305, 390, True, TASKS[:2])
    c.t((W - 30 - 390, 1080 - 30 - 322), "", 10)
    # off duty variant
    c.rr((W - 30 - 390 - 8, 330, W - 30 + 8, 345), 0, fill=BG, alpha=0)
    c.t((W - 420, 395), "Off duty", 14, True, TEXT)
    hud_card(c, W - 30 - 390, 420, 390, False, [])
    c.t((W - 420, 560), "Waiting-for-pickup tasks are not in the small view,", 12, False, TEXT)
    c.t((W - 420, 578), "only in the F6 view; you get a notification instead.", 12, False, TEXT)
    # ui_core notification (top right)
    nx, ny = W - 30 - 400, 30
    c.rr((nx, ny, nx + 400, ny + 86), 8, fill=BG, alpha=235)
    c.rr((nx, ny, nx + 5, ny + 86), 2, fill=ACC)
    c.t((nx + 20, ny + 14), "Blood Transport", 15, True)
    c.t((nx + 20, ny + 40), "New task T-1043: FFP A+ ×2", 13, False, TEXT)
    c.t((nx + 20, ny + 60), "LS Blood Bank → Country General", 13, False, MUTED)
    c.save("01_hud_small.png")


# ------------------------------------------------------------------------------------------ 02 big
def m02():
    c = Canvas(scene())
    c.label("02 · Panel – big view (F6, cursor appears)")
    x, y, w, h = W - 30 - 860, 1080 - 30 - 760, 860, 760
    c.rr((x, y, x + w, y + h), 10, fill=BG, alpha=238)
    c.rr((x, y, x + w, y + 4), 2, fill=ACC)
    c.rr((x, y + 4, x + w, y + 84), 0, fill=HEAD)
    c.t((x + 22, y + 20), "BLOOD TRANSPORT", 12, True, MUTED)
    c.t((x + 22, y + 42), "BT-4821", 24, True)
    c.chip(x + 22 + c.tw("BT-4821", 24, True) + 14, y + 47, "ON DUTY", GOOD, 12)
    c.t((x + 22 + c.tw("BT-4821", 24, True) + 100, y + 52), "Marcus_Hale · 01:12:40", 13, False, MUTED)
    c.btn(x + w - 330, y + 26, 148, 34, "Wind down  ○ OFF", "n", 13)
    c.btn(x + w - 172, y + 26, 120, 34, "End service", "p", 13)
    c.key(x + w - 40, y + 4 + 6, "F6", 11)
    # stats strip
    sy = y + 96
    stats = [("DELIVERED", "3", GOOD), ("IN TRANSIT", "2", WARN), ("WAITING", "3", BLUE), ("PAY SO FAR", "€9,500", TEXT)]
    sw = (w - 44 - 3 * 10) / 4
    for i, (lab, val, col) in enumerate(stats):
        sx = x + 22 + i * (sw + 10)
        c.rr((sx, sy, sx + sw, sy + 52), 6, fill=TILE)
        c.t((sx + 12, sy + 8), lab, 10, True, MUTED)
        c.t((sx + 12, sy + 24), val, 18, True, col)
    # offer banner
    by = sy + 64
    c.rr((x + 22, by, x + w - 22, by + 54), 6, fill=WARN, alpha=26, outline=WARN)
    c.t((x + 36, by + 9), "BT-1177 (Dana_Reed) offers you a task", 13, True, WARN)
    c.t((x + 36, by + 29), "FFP AB ×2 · Country General → LV Blood Bank · waiting for pickup", 12, False, TEXT)
    c.btn(x + w - 250, by + 12, 90, 30, "Accept", "g", 12)
    c.btn(x + w - 150, by + 12, 90, 30, "Decline", "n", 12)
    c.t((x + w - 54, by + 27), "18s", 11, True, MUTED, "mm")
    # lists
    def section(yy, title, sub=""):
        c.t((x + 22, yy), title, 11, True, MUTED)
        if sub: c.t((x + w - 22, yy), sub, 11, False, OFF, "ra")
        return yy + 20

    def row(yy, t, mode):
        rh = 66
        col = TYPES[t["type"]][1]
        sel = mode == "transit"
        c.rr((x + 22, yy, x + w - 22, yy + rh), 6, fill=TILE, outline=(WARN if sel else None))
        if mode == "wait":
            c.t((x + 30, yy + rh / 2), "⋮⋮", 16, True, OFF, "lm")
        c.tile(x + 52, yy + 15, 36, TYPES[t["type"]][0], col, 14)
        c.t((x + 100, yy + 11), t["what"], 15, True)
        cw = c.tw(t["what"], 15, True)
        c.chip(x + 100 + cw + 12, yy + 11, t["tag"][0], t["tag"][1], 10)
        c.t((x + 100, yy + 37), t["route"], 12, False, MUTED)
        c.t((x + 100 + c.tw(t["route"], 12) + 12, yy + 37), t["id"], 11, False, OFF)
        bx = x + w - 34
        if mode == "transit":
            c.chip(bx, yy + 8, "TRANSIT", WARN, 10, anchor="r")
            c.btn(bx - 130, yy + 30, 130, 26, "Route ● ON" if t["id"] == "T-1042" else "Route", "g" if t["id"] == "T-1042" else "n", 12)
        elif mode == "wait":
            c.chip(bx, yy + 8, "WAITING", BLUE, 10, anchor="r")
            c.btn(bx - 130, yy + 30, 60, 26, "Route", "n", 12)
            c.btn(bx - 64, yy + 30, 64, 26, "Hand over", "b" if t["id"] == "T-1043" else "off", 11)
            c.t((x + 52 - 18, yy + 53), "▲", 9, True, OFF, "mm")
            c.t((x + 52 - 18, yy + 63), "▼", 9, True, OFF, "mm")
        else:
            c.chip(bx, yy + 8, "DELIVERED ✓", GOOD, 10, anchor="r")
            c.t((bx, yy + 40), "disappears in 3 s", 11, False, OFF, "ra")
        return yy + rh + 6

    yy = section(by + 68, "IN TRANSIT – pinned to the top", "2")
    for t in TASKS[:2]: yy = row(yy, t, "transit")
    yy = section(yy + 6, "WAITING FOR PICKUP – drag or ▲▼ to set your order", "3")
    for t in TASKS[2:]: yy = row(yy, t, "wait")
    done = dict(id="T-1038", type="ffp", what="FFP O+  ×2", route="LS Blood Bank → All Saints General", tag=("RESUPPLY", MUTED))
    yy = section(yy + 6, "JUST DELIVERED")
    row(yy, done, "done")
    c.cursor(x + w - 108, by + 150)
    # callouts
    def callout(py, s):
        tx = x - 40
        c.d.line((tx, py, x - 2, py), fill=KEY, width=2)
        c.d.ellipse((x - 8, py - 5, x + 2, py + 5), fill=KEY)
        c.rr((tx - 340, py - 16, tx, py + 16), 6, fill=(8, 9, 12), alpha=235, outline=KEY)
        c.t((tx - 170, py), s, 13, True, KEY, "mm")
    callout(y + 43, "Wind down: no new tasks, finish the rest")
    callout(by + 120, "Route: one objective at a time (v_radar)")
    callout(by + 300, "Hand over: only when another unit is next to you")
    c.save("02_hud_big.png")


# ------------------------------------------------------------------------------------------ 03 port
def m03():
    c = Canvas(scene().filter(ImageFilter.GaussianBlur(6)))
    c.label("03 · Port window at a blood bank (v_inventory transfer window, rules from bt_items)")
    x0, y0, x1, y1 = 250, 120, 1670, 960
    c.rr((x0, y0, x1, y1), 10, fill=BG, alpha=240)
    c.rr((x0, y0, x1, y0 + 5), 2, fill=ACC)
    c.rr((x0, y0 + 5, x1, y0 + 66), 0, fill=HEAD)
    c.t((x0 + 24, y0 + 20), "PORT · LOS SANTOS BLOOD BANK", 12, True, MUTED)
    c.t((x0 + 24, y0 + 40), "Dispatch counter", 20, True)
    c.key(x1 - 100, y0 + 24, "ESC"); c.t((x1 - 24, y0 + 34), "Close", 13, False, MUTED, "rm")
    # banner
    c.rr((x0 + 24, y0 + 80, x1 - 24, y0 + 118), 4, fill=WARN, alpha=26, outline=WARN)
    c.t((x0 + 40, y0 + 99), "Blood Transport:  take the units marked TAKE (your tasks).  Units of other drivers are locked.", 14, True, WARN, "lm")
    # left: you
    lx = x0 + 24
    c.t((lx, y0 + 140), "YOU", 11, True, MUTED)
    for i, (lab, name, sub, act) in enumerate([("LEFT HAND", "Empty", "", False), ("RIGHT HAND", "Transport box", "2.1 / 10 kg", True), ("BACK", "Empty", "", False)]):
        bx = lx + i * 218
        c.rr((bx, y0 + 156, bx + 208, y0 + 236), 6, fill=TILE, outline=(ACC if act else None), width=2)
        c.t((bx + 12, y0 + 168), lab, 10, True, MUTED)
        if act:
            c.tile(bx + 12, y0 + 186, 40, "BX", ACC, 15)
            c.t((bx + 62, y0 + 190), name, 15, True); c.t((bx + 62, y0 + 212), sub, 12, False, MUTED)
        else:
            c.t((bx + 12, y0 + 198), name, 14, False, OFF)
    c.t((lx, y0 + 262), "OPEN CONTAINER", 11, True, MUTED)
    c.t((lx, y0 + 282), "Blood transport box", 20, True)
    c.t((lx + 640, y0 + 262), "2.1 / 10 kg", 12, True, TEXT, "ra")
    c.rr((lx + 480, y0 + 276, lx + 640, y0 + 284), 4, fill=TILE2); c.rr((lx + 480, y0 + 276, lx + 513, y0 + 284), 4, fill=GOOD)
    items = [
        ("RB", (200, 40, 60), "RBC A−  ×6 · for All Saints", "T-1046 · yours", "DELIVER »", "x6", "3.0 kg", True),
    ]
    iy = y0 + 312
    for tl, col, nm, sub, tag, qty, kg, hl in items:
        c.rr((lx, iy, lx + 640, iy + 54), 6, fill=TILE, outline=(WARN if hl else None), width=2)
        c.tile(lx + 10, iy + 9, 36, tl, col, 13)
        c.t((lx + 58, iy + 9), nm, 14, True); c.t((lx + 58, iy + 30), sub, 11, False, MUTED)
        if tag: c.chip(lx + 470, iy + 17, tag, WARN, 10, anchor="r")
        c.t((lx + 600, iy + 9), qty, 14, True, TEXT, "ra"); c.t((lx + 628, iy + 30), kg, 11, False, MUTED, "ra")
        iy += 62
    # centre arrows
    c.btn(lx + 660, y0 + 360, 44, 44, "»", "n", 18); c.btn(lx + 660, y0 + 420, 44, 44, "«", "n", 18)
    # right: port
    rx = x0 + 760
    c.t((rx, y0 + 140), "PORT", 11, True, MUTED)
    c.t((rx, y0 + 160), "Los Santos Blood Bank · dispatch counter", 18, True)
    c.t((rx, y0 + 188), "Shipments prepared for the transporters on duty", 12, False, MUTED)
    pit = [
        ("RB", (200, 40, 60), "RBC 0−  ×4", "For All Saints General · T-1042 · yours", "« TAKE", "x4", "2.0 kg", "mine"),
        ("FF", (200, 40, 60), "FFP A+  ×2", "For Country General · T-1043 · Marcus_Hale (waiting)", "« TAKE", "x2", "1.0 kg", "mine"),
        ("PL", (220, 100, 70), "Platelets B+  ×3", "For LV Blood Bank · T-1051 · Dana_Reed", "LOCKED", "x3", "0.6 kg", "other"),
        ("RB", (200, 40, 60), "RBC AB−  ×2", "For All Saints General · T-1049 · Leo_Marsh", "LOCKED", "x2", "1.0 kg", "other"),
    ]
    iy = y0 + 224
    for tl, col, nm, sub, tag, qty, kg, who in pit:
        mine = who == "mine"
        c.rr((rx, iy, x1 - 24, iy + 54), 6, fill=TILE, outline=(WARN if mine else None), width=2)
        c.tile(rx + 10, iy + 9, 36, tl, col if mine else OFF, 13)
        c.t((rx + 58, iy + 9), nm, 14, True, TEXT if mine else OFF); c.t((rx + 58, iy + 30), sub, 11, False, MUTED if mine else OFF)
        c.chip(x1 - 150, iy + 17, tag, WARN if mine else OFF, 10, anchor="r")
        c.t((x1 - 60, iy + 9), qty, 14, True, TEXT if mine else OFF, "ra"); c.t((x1 - 40, iy + 30), kg, 11, False, MUTED if mine else OFF, "ra")
        iy += 62
    c.rr((rx, iy + 20, x1 - 24, iy + 110), 6, outline=OFF)
    c.t(((rx + x1 - 24) / 2, iy + 65), "Drop items here", 14, False, OFF, "mm")
    c.t((rx, iy + 140), "Rule: you may only take what belongs to your tasks, and only into your own box.", 12, False, MUTED)
    c.t((rx, iy + 160), "At a hospital the direction flips: put the units in; the lab samples are the ones you take.", 12, False, MUTED)
    # footer
    c.d.line((x0, y1 - 56, x1, y1 - 56), fill=LINE)
    fx = x0 + 24
    for k, s in [("Drag", "Move"), ("Double-click", "Quick move"), ("Shift", "+ drag: split a stack"), ("Right-click", "Details")]:
        fx += c.key(fx, y1 - 42, k) + 8
        c.t((fx, y1 - 32), s, 13, False, MUTED, "lm"); fx += c.tw(s, 13) + 22
    c.cursor(rx + 120, y0 + 262)
    c.save("03_port_window.png")


# ------------------------------------------------------------------------------------------ 04 admin (in game)
def m04():
    c = Canvas(scene().filter(ImageFilter.GaussianBlur(5)))
    c.label("04 · /btadmin (in-game, admin level 2+) – same layout as /ermadmin, without the auto-dispatch switch")
    w, h = 1180, 700
    x, y = (W - w) // 2, (H - h) // 2 + 20
    c.rr((x, y, x + w, y + h), 10, fill=BG, alpha=245)
    c.rr((x, y, x + w, y + 5), 2, fill=ACC)
    c.rr((x, y + 5, x + w, y + 60), 0, fill=HEAD)
    c.t((x + 22, y + 32), "Blood Transport Admin", 19, True, TEXT, "lm")
    c.btn(x + 330, y + 18, 100, 30, "Shifts", "p", 13); c.btn(x + 440, y + 18, 100, 30, "Tasks", "n", 13)
    c.key(x + w - 70, y + 24, "ESC")
    # list
    lw = 580
    c.rr((x + 16, y + 72, x + 16 + lw, y + 112), 6, fill=TILE)
    c.t((x + 30, y + 92), "Search unit, driver, plate…", 13, False, OFF, "lm")
    c.btn(x + 16 + lw - 250, y + 78, 70, 28, "All", "p", 11); c.btn(x + 16 + lw - 174, y + 78, 80, 28, "On duty", "n", 11); c.btn(x + 16 + lw - 88, y + 78, 72, 28, "Ended", "n", 11)
    ty = y + 124
    for cx, lab in [(30, "UNIT"), (130, "DRIVER"), (290, "STARTED"), (400, "TIME"), (470, "TASKS"), (535, "")]:
        c.t((x + cx, ty), lab, 10, True, MUTED)
    rows = [("BT-4821", "Marcus_Hale", "10-15 14:02", "01:12", "5 / 7", "LIVE", True), ("BT-1177", "Dana_Reed", "10-15 13:40", "01:34", "6 / 6", "LIVE", False),
            ("BT-0932", "Leo_Marsh", "10-15 12:55", "00:41", "2 / 3", "ENDED", False), ("BT-4821", "Sam_Ortiz", "10-15 11:10", "01:05", "4 / 4", "ENDED", False),
            ("BT-7710", "Marcus_Hale", "10-14 21:30", "00:25", "1 / 2", "ENDED", False), ("BT-3306", "Nora_Vance", "10-14 20:02", "02:10", "9 / 10", "ENDED", False),
            ("BT-1177", "Dana_Reed", "10-14 18:45", "00:55", "3 / 3", "ENDED", False), ("BT-5521", "Ivo_Petrov", "10-14 17:20", "00:12", "0 / 1", "ENDED", False)]
    ry = ty + 20
    for u, dr, st, du, tk, state, sel in rows:
        c.rr((x + 16, ry, x + 16 + lw, ry + 34), 4, fill=(TILE2 if sel else TILE))
        c.t((x + 30, ry + 17), u, 13, True, TEXT, "lm"); c.t((x + 130, ry + 17), dr, 13, False, TEXT, "lm")
        c.t((x + 290, ry + 17), st, 12, False, MUTED, "lm"); c.t((x + 400, ry + 17), du, 12, False, MUTED, "lm"); c.t((x + 470, ry + 17), tk, 12, False, TEXT, "lm")
        c.chip(x + 535, ry + 7, state, GOOD if state == "LIVE" else OFF, 10)
        ry += 38
    c.btn(x + 16, y + h - 46, 70, 30, "Prev", "n", 12); c.btn(x + 16 + lw - 70, y + h - 46, 70, 30, "Next", "n", 12)
    c.t((x + 16 + lw / 2, y + h - 31), "Page 1 / 7 · 52 shifts", 12, False, MUTED, "mm")
    # detail
    dx = x + 16 + lw + 14; dw = w - lw - 46
    c.rr((dx, y + 72, dx + dw, y + h - 16), 8, fill=TILE)
    c.t((dx + 18, y + 94), "Shift #52 · BT-4821", 17, True, TEXT, "lm"); c.chip(dx + dw - 18, y + 84, "LIVE", GOOD, 11, anchor="r")
    kv = [("Driver", "Marcus_Hale (acc: mhale)"), ("Started", "2026-10-15 14:02:11"), ("Vehicle", "Ambulance 415 · BT-4821"), ("Wind down", "No"), ("Pay (est.)", "€9,500")]
    for i, (k, v) in enumerate(kv):
        c.t((dx + 18, y + 128 + i * 24), k, 12, False, MUTED); c.t((dx + 130, y + 128 + i * 24), v, 12, True)
    c.t((dx + 18, y + 262), "TASKS GIVEN TO THIS SHIFT (ID log)", 10, True, MUTED)
    trows = [("T-1042", "RBC 0− ×4", "TRANSIT"), ("T-1043", "FFP A+ ×2", "WAITING"), ("T-1038", "FFP O+ ×2", "DELIVERED"), ("T-1036", "Lab ×1", "DELIVERED"), ("T-1031", "Platelets ×3", "CANCELLED · handed to BT-1177")]
    for i, (i_d, what, st) in enumerate(trows):
        yy = y + 282 + i * 36
        c.rr((dx + 14, yy, dx + dw - 14, yy + 30), 4, fill=TILE2)
        c.t((dx + 26, yy + 15), i_d, 12, True, TEXT, "lm"); c.t((dx + 100, yy + 15), what, 12, False, TEXT, "lm")
        base = st.split(" ")[0]
        c.chip(dx + dw - 24, yy + 5, st, STC.get(base, OFF), 9, anchor="r")
    c.t((dx + 18, y + 482), "Click a task to open its history: created → assigned → picked up → delivered, from / to, units, source.", 11, False, MUTED)
    c.cursor(dx + 70, y + 296)
    c.save("04_admin_ingame.png")


# ------------------------------------------------------------------------------------------ web helpers
WBG = (15, 18, 22); WPANEL = (22, 27, 33); WP2 = (29, 35, 43); WP3 = (37, 45, 55); WLINE = (42, 50, 60)
WTEXT = (232, 236, 241); WDIM = (152, 162, 174); WACC = (224, 60, 49); WTOP = (11, 14, 17)

def browser_frame(c, url):
    c.rr((0, 0, W, 76), 0, fill=(32, 34, 40))
    c.rr((16, 12, 260, 44), 8, fill=WBG); c.t((30, 28), "Blood Transport", 13, False, WTEXT, "lm")
    c.rr((16, 46, W - 16, 70), 12, fill=(22, 23, 28)); c.t((34, 58), url, 13, False, WDIM, "lm")

def topbar(c, y, nav, active, right=""):
    c.rr((0, y, W, y + 56), 0, fill=WTOP)
    c.rr((20, y + 12, 52, y + 44), 7, fill=WACC)
    c.d.polygon([(36, y + 17), (31, y + 28), (36, y + 38), (41, y + 28)], fill=(255, 255, 255))
    c.t((64, y + 18), "Blood Transport", 16, True, WTEXT); c.t((64, y + 36), "Los Santos · Las Venturas · San Fierro", 11, False, WDIM)
    nx = 430
    for n in nav:
        w = c.tw(n, 14, True) + 36
        if n == active:
            c.rr((nx, y + 11, nx + w, y + 45), 6, fill=WP3)
        c.t((nx + w / 2, y + 28), n, 14, True, WTEXT if n == active else WDIM, "mm")
        nx += w + 6
    if right: c.t((W - 24, y + 28), right, 13, False, WDIM, "rm")

def wpanel(c, box, title=None):
    c.rr(box, 8, fill=WPANEL, outline=WLINE)
    if title: c.t((box[0] + 18, box[1] + 18), title, 12, True, WDIM)

# ------------------------------------------------------------------------------------------ 05 web home
def m05():
    c = Canvas(Image.new("RGB", (W, H), WBG))
    browser_frame(c, "http://<server>:22005/bt_web/   ·   in game: blood-transport.eu (ui_browser › Services)")
    topbar(c, 76, ["Home", "Map", "Admin"], "Home", "Public · English")
    y = 160
    c.rr((60, y, W - 60, y + 250), 12, fill=WP2, outline=WLINE)
    c.t((100, y + 40), "Be the link between the blood bank and the ward.", 38, True, WTEXT)
    c.t((100, y + 100), "Blood transporters carry blood products, lab samples and urgent medicine between blood supply centers and hospitals", 17, False, WDIM)
    c.t((100, y + 126), "across San Andreas. Every unit counts – and every minute on the road matters.", 17, False, WDIM)
    c.btn(100, y + 176, 200, 46, "How do I start?", "p", 15); c.btn(316, y + 176, 180, 46, "Live map →", "n", 15)
    # stats
    sy = y + 276
    for i, (lab, val, sub, col) in enumerate([("ON DUTY NOW", "4", "transporters", GOOD), ("ACTIVE TASKS", "9", "waiting for pickup + in transit", WARN), ("COMPLETED, ALL TIME", "1,284", "deliveries", WTEXT)]):
        bx = 60 + i * 616
        wpanel(c, (bx, sy, bx + 600, sy + 118))
        c.t((bx + 24, sy + 20), lab, 12, True, WDIM); c.t((bx + 24, sy + 42), val, 44, True, col); c.t((bx + 24 + c.tw(val, 44, True) + 14, sy + 70), sub, 14, False, WDIM)
    # what do they do
    wy = sy + 146
    c.t((60, wy), "What does a blood transporter do?", 22, True, WTEXT)
    cards = [("1", "Pick up", "Collect the prepared shipment at the blood bank or hospital counter and put it in your cooled transport box."),
             ("2", "Plan", "Several tasks can run at once. You choose the order and the route – urgent ones first, scheduled surgery blood in between."),
             ("3", "Deliver", "Hand the shipment over at the destination counter before it is too late. Lab samples travel the other way."),
             ("4", "Cooperate", "Hand waiting tasks over to a colleague standing next to you when you are overloaded.")]
    for i, (n, t, d) in enumerate(cards):
        bx = 60 + i * 462
        wpanel(c, (bx, wy + 40, bx + 446, wy + 210))
        c.rr((bx + 18, wy + 58, bx + 54, wy + 94), 18, fill=WACC); c.t((bx + 36, wy + 76), n, 16, True, (255, 255, 255), "mm")
        c.t((bx + 66, wy + 68), t, 18, True, WTEXT)
        words = d.split(); line = ""; ly = wy + 108
        for wd in words:
            if c.tw(line + " " + wd, 13) > 400:
                c.t((bx + 20, ly), line, 13, False, WDIM); ly += 20; line = wd
            else: line = (line + " " + wd).strip()
        c.t((bx + 20, ly), line, 13, False, WDIM)
    hy = wy + 236
    c.t((60, hy), "How do I become a blood transporter?", 22, True, WTEXT)
    wpanel(c, (60, hy + 40, W - 60, hy + 150))
    steps = ["Go to a blood transport duty marker (marked on your map) and go on duty.", "Take a BT- ambulance from the vehicle point.", "Sit in it and sign on in the panel (F6).", "Tasks arrive automatically – good luck!"]
    for i, s in enumerate(steps):
        bx = 90 + i * 456
        c.t((bx, hy + 66), f"STEP {i + 1}", 11, True, WACC);
        words = s.split(); line = ""; ly = hy + 88
        for wd in words:
            if c.tw(line + " " + wd, 14) > 400:
                c.t((bx, ly), line, 14, False, WTEXT); ly += 20; line = wd
            else: line = (line + " " + wd).strip()
        c.t((bx, ly), line, 14, False, WTEXT)
    c.t((20, H - 22), "Provided by OpenSanAndreas", 11, False, WDIM)
    c.save("05_web_home.png")


# ------------------------------------------------------------------------------------------ 06 web map
def m06():
    c = Canvas(Image.new("RGB", (W, H), WBG))
    browser_frame(c, "http://<server>:22005/bt_web/#map")
    topbar(c, 76, ["Home", "Map", "Admin"], "Map", "● live · updated 2 s ago")
    top = 132
    lw, rw = 330, 360
    mx0, mx1 = lw, W - rw
    # map
    try:
        rad = Image.open(RADAR).convert("RGB")
        mw, mh = mx1 - mx0, H - top
        side = max(mw, mh)
        # focus on San Andreas fully scaled to the map height, centered
        rad2 = rad.resize((mh, mh), Image.LANCZOS)
        mp = Image.new("RGB", (mw, mh), (10, 42, 61))
        mp.paste(rad2, ((mw - mh) // 2, 0))
        c.im.paste(mp, (mx0, top))
        ox = mx0 + (mw - mh) // 2
    except Exception as e:
        print("radar missing", e); ox = mx0
        c.rr((mx0, top, mx1, H), 0, fill=(10, 42, 61)); mh = H - top
    def wp(wx, wy):
        return ox + (wx + 3000) / 6000 * mh, top + (3000 - wy) / 6000 * mh
    inst = [("LS Blood Bank", 933, -1443, "bank"), ("LV Blood Bank", 1365, 1897, "bank"), ("SF Blood Bank", -2720, 127, "bank"),
            ("All Saints", 1177, -1320, "hosp"), ("Country General", 2025, -1404, "hosp"), ("LV General", 1610, 1817, "hosp"), ("SF Medical Center", -2656, 637, "hosp")]
    units = [("BT-4821", 1010, -1380, True), ("BT-1177", 1500, 1500, False), ("BT-0932", -2600, 300, False)]
    # route polyline for hovered unit (dashed)
    a = wp(1010, -1380); b = wp(1177, -1320)
    c.d.line((*a, *wp(1100, -1350), *b), fill=WARN, width=3)
    for nm, wx, wy, kind in inst:
        px, py = wp(wx, wy)
        if kind == "bank":
            c.rr((px - 11, py - 11, px + 11, py + 11), 4, fill=WACC, outline=(255, 255, 255), width=2)
            c.d.polygon([(px, py - 6), (px - 4, py + 1), (px, py + 6), (px + 4, py + 1)], fill=(255, 255, 255))
        else:
            c.rr((px - 11, py - 11, px + 11, py + 11), 11, fill=(46, 160, 67), outline=(255, 255, 255), width=2)
            c.t((px, py), "+", 16, True, (255, 255, 255), "mm")
    for nm, wx, wy, hov in units:
        px, py = wp(wx, wy)
        c.d.polygon([(px, py - 11), (px + 9, py + 8), (px, py + 4), (px - 9, py + 8)], fill=WARN, outline=(20, 20, 20))
    # tooltip on hovered unit
    px, py = wp(1010, -1380)
    tx, ty = px + 22, py - 150
    c.rr((tx, ty, tx + 300, ty + 150), 8, fill=WTOP, outline=WLINE)
    c.t((tx + 14, ty + 12), "BT-4821", 15, True, WTEXT); c.t((tx + 90, ty + 14), "driver: Marcus_Hale", 12, False, WDIM)
    c.t((tx + 14, ty + 40), "CURRENT TASKS", 10, True, WDIM)
    for i, s in enumerate(["T-1042  RBC 0− ×4 → All Saints  · transit", "T-1039  Platelets B+ ×3 → Country Gen.  · transit", "T-1043  FFP A+ ×2 → Country Gen.  · waiting"]):
        c.t((tx + 14, ty + 62 + i * 22), s, 12, False, WTEXT)
    c.d.line((px + 8, py - 6, tx, ty + 120), fill=WLINE, width=1)
    # hover on a hospital
    hx, hy = wp(2025, -1404)
    c.rr((hx + 16, hy + 8, hx + 276, hy + 84), 8, fill=WTOP, outline=WLINE)
    c.t((hx + 30, hy + 18), "Country General Hospital", 13, True, WTEXT); c.t((hx + 30, hy + 40), "Stock: OK · low: FFP AB−", 12, False, WDIM); c.t((hx + 30, hy + 60), "Open deliveries: 2", 12, False, WDIM)
    c.cursor(int(px) + 4, int(py) - 6)
    # left panel
    wpanel(c, (0, top, lw, H), None)
    c.t((20, top + 20), "UNITS ON DUTY", 12, True, WDIM); c.t((lw - 20, top + 20), "3", 12, True, WDIM, "ra")
    for i, (u, dr, done, el) in enumerate([("BT-4821", "Marcus_Hale", 3, "01:12:40"), ("BT-1177", "Dana_Reed", 6, "01:34:05"), ("BT-0932", "Leo_Marsh", 2, "00:41:19")]):
        yy = top + 50 + i * 76
        c.rr((14, yy, lw - 14, yy + 66), 6, fill=WP2)
        c.t((28, yy + 12), u, 15, True, WTEXT); c.t((28, yy + 36), dr, 12, False, WDIM)
        c.t((lw - 28, yy + 12), f"{done} delivered", 12, True, GOOD, "ra"); c.t((lw - 28, yy + 36), f"on duty {el}", 12, False, WDIM, "ra")
    c.t((20, top + 300), "Read-only list. Hover a unit on the map for its tasks.", 11, False, (98, 108, 120))
    # right panel: stock
    rx = W - rw
    wpanel(c, (rx, top, W, H), None)
    c.t((rx + 20, top + 20), "STOCK", 12, True, WDIM)
    c.btn(rx + rw - 200, top + 12, 84, 26, "Centers", "p", 11); c.btn(rx + rw - 110, top + 12, 94, 26, "Hospitals", "n", 11)
    groups = ["0−", "0+", "A−", "A+", "B−", "B+", "AB−", "AB+"]
    random.seed(3)
    for bi, (nm, scale) in enumerate([("Los Santos Blood Bank", 1.0), ("Las Venturas Blood Bank", 0.7), ("San Fierro Blood Bank", 0.5)]):
        by = top + 52 + bi * 300
        c.rr((rx + 14, by, W - 14, by + 288), 6, fill=WP2)
        c.t((rx + 28, by + 12), nm, 14, True, WTEXT)
        for pi, prod in enumerate(["RBC", "FFP", "PLT"]):
            c.t((rx + 28, by + 44 + pi * 78), prod, 11, True, WDIM)
            for gi, g in enumerate(groups):
                col = gi % 4; row = gi // 4
                cx = rx + 66 + col * 70; cy = by + 38 + pi * 78 + row * 30
                lvl = random.uniform(0.15, 1.0) * scale
                colr = GOOD if lvl > 0.45 else (WARN if lvl > 0.25 else BAD)
                c.t((cx, cy + 5), g, 11, True, WTEXT)
                c.rr((cx + 24, cy + 6, cx + 62, cy + 14), 3, fill=WP3); c.rr((cx + 24, cy + 6, cx + 24 + 38 * min(1, lvl), cy + 14), 3, fill=colr)
    c.t((rx + 20, H - 20), "Hospital stock: \"Hospitals\" tab", 11, False, (98, 108, 120))
    c.t((mx0 + 12, H - 18), "Provided by OpenSanAndreas", 11, False, (230, 230, 230))
    c.save("06_web_map.png")


# ------------------------------------------------------------------------------------------ 07 web admin
def m07():
    c = Canvas(Image.new("RGB", (W, H), WBG))
    browser_frame(c, "http://<server>:22005/bt_web/#admin")
    topbar(c, 76, ["Home", "Map", "Admin"], "Admin", "mhale · admin level 2   [Sign out]")
    top = 132
    # sub tabs + toolbar
    c.btn(24, top + 14, 90, 32, "Shifts", "p", 13); c.btn(122, top + 14, 90, 32, "Tasks", "n", 13)
    c.rr((240, top + 14, 700, top + 46), 6, fill=WP2, outline=WLINE); c.t((254, top + 30), "Search id, unit, driver, from, to…", 13, False, (98, 108, 120), "lm")
    c.rr((712, top + 14, 860, top + 46), 6, fill=WP2, outline=WLINE); c.t((726, top + 30), "All  ▾", 13, False, WTEXT, "lm")
    # list
    lw = 1100
    wpanel(c, (24, top + 64, 24 + lw, H - 24))
    cols = [(44, "ID"), (120, "TASK"), (260, "TYPE"), (420, "FROM → TO"), (760, "DRIVER"), (880, "CREATED"), (1000, "STATUS")]
    for cx, lab in cols: c.t((24 + cx, top + 84), lab, 10, True, WDIM)
    rows = [("T-1046", "RBC A− ×6", "Resupply", "LS Blood Bank → All Saints", "Marcus_Hale", "14:21", "WAITING"),
            ("T-1043", "FFP A+ ×2", "Urgent", "LS Blood Bank → Country Gen.", "Marcus_Hale", "14:18", "WAITING"),
            ("T-1042", "RBC 0− ×4", "Urgent", "LS Blood Bank → All Saints", "Marcus_Hale", "14:11", "TRANSIT"),
            ("T-1039", "Platelets B+ ×3", "Planned", "LS Blood Bank → Country Gen.", "Marcus_Hale", "14:05", "TRANSIT"),
            ("T-1038", "FFP O+ ×2", "Resupply", "LS Blood Bank → All Saints", "Dana_Reed", "13:58", "DELIVERED"),
            ("T-1036", "Lab sample ×1", "Lab", "Country Gen. → LS Blood Bank", "Dana_Reed", "13:51", "DELIVERED"),
            ("T-1033", "Urgent drug ×1", "Medicine", "LV General → SF Medical Center", "Leo_Marsh", "13:40", "DELIVERED"),
            ("T-1031", "Platelets A+ ×3", "Planned", "SF Blood Bank → SF Medical Center", "Leo_Marsh", "13:22", "CANCELLED"),
            ("T-1029", "RBC B+ ×8", "Resupply", "LV Blood Bank → LV General", "–", "13:10", "CANCELLED")]
    for i, r in enumerate(rows):
        yy = top + 104 + i * 54
        c.rr((36, yy, 24 + lw - 12, yy + 46), 5, fill=(WP3 if i == 2 else WP2))
        for (cx, _), v in zip(cols[:6], r[:6]): c.t((24 + cx, yy + 23), v, 13, cx == 44, WTEXT, "lm")
        c.chip(24 + 1000, yy + 12, r[6], STC[r[6]], 10)
    # detail
    dx = 24 + lw + 16; dw = W - dx - 24
    wpanel(c, (dx, top + 64, dx + dw, H - 24))
    c.t((dx + 18, top + 90), "Task T-1042", 18, True, WTEXT); c.chip(dx + dw - 18, top + 82, "TRANSIT", WARN, 11, anchor="r")
    kv = [("Type", "Urgent blood · RBC 0− ×4"), ("From", "Los Santos Blood Bank"), ("To", "All Saints General Hospital"), ("Driver", "Marcus_Hale · BT-4821 · shift #52"), ("Source", "Hospital request (bt_stock)")]
    for i, (k, v) in enumerate(kv):
        c.t((dx + 18, top + 130 + i * 26), k, 12, False, WDIM); c.t((dx + 120, top + 130 + i * 26), v, 12, True, WTEXT)
    c.t((dx + 18, top + 290), "HISTORY", 11, True, WDIM)
    for i, (tm, s) in enumerate([("14:11:02", "Created · reserved 4 units at LS Blood Bank"), ("14:11:05", "Assigned to BT-4821 (least loaded)"), ("14:14:40", "Picked up (port → box)"), ("–", "Delivery pending")]):
        yy = top + 316 + i * 30
        c.d.ellipse((dx + 20, yy + 5, dx + 30, yy + 15), fill=(GOOD if i < 3 else WP3))
        c.t((dx + 44, yy + 10), tm, 12, True, WDIM, "lm"); c.t((dx + 120, yy + 10), s, 12, False, WTEXT, "lm")
    c.t((dx + 18, top + 470), "The Shifts tab mirrors /btadmin: unit, driver, duration,", 11, False, (98, 108, 120))
    c.t((dx + 18, top + 488), "tasks given (ID log) and the pay breakdown.", 11, False, (98, 108, 120))
    c.save("07_web_admin.png")


if __name__ == "__main__":
    for fn in (m01, m02, m03, m04, m05, m06, m07):
        fn()
