"""Flat illustrations for the weed farm upgrades (SVG, 800x500).

    python tools/draw_upgrades.py [out_dir]

Writes weed_capacity.svg / weed_staff.svg. The game uses the JPEG versions in
biz_core/img/upgrades/ (800x500, quality 85): open the SVG in a browser and save
it as JPEG (or draw it to a canvas and export).
"""
import math, random, sys, os

W, H = 800, 500
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)


def leaf(cx, cy, size, rot, color, dark):
    """cannabis leaf: 7 leaflets fanned out from the stem point"""
    parts = []
    spec = [(-75, .55), (-48, .8), (-22, .95), (0, 1.0), (22, .95), (48, .8), (75, .55)]
    for ang, ln in spec:
        L = size * ln
        a = math.radians(ang + rot - 90)
        ex, ey = cx + math.cos(a) * L, cy + math.sin(a) * L
        # leaflet as a thin ellipse rotated along the vector
        mx, my = (cx + ex) / 2, (cy + ey) / 2
        deg = math.degrees(a)
        parts.append(f'<ellipse cx="{mx:.1f}" cy="{my:.1f}" rx="{L/2:.1f}" ry="{L*0.13:.1f}" transform="rotate({deg:.1f} {mx:.1f} {my:.1f})" fill="{color}"/>')
        parts.append(f'<line x1="{cx:.1f}" y1="{cy:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" stroke="{dark}" stroke-width="{max(0.6, size*0.02):.1f}"/>')
    return ''.join(parts)


def plant(x, base, h, rnd, pal=("#4f9a3c", "#3b7f2c", "#62b04a"), dark="#24521b"):
    s = [f'<path d="M{x:.1f} {base:.1f} L{x:.1f} {base-h:.1f}" stroke="{dark}" stroke-width="{h*0.035:.1f}"/>']
    n = 6
    for i in range(n):
        t = i / (n - 1)
        y = base - h * (0.25 + 0.75 * t)
        size = h * (0.42 - 0.22 * t)
        for side in (-1, 1):
            s.append(leaf(x + side * size * 0.15, y, size, side * (35 + rnd.uniform(-10, 10)), rnd.choice(pal), dark))
    s.append(leaf(x, base - h, h * 0.22, 0, pal[2], dark))
    return ''.join(s)


def defs():
    return '''<defs>
  <linearGradient id="wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b1712"/><stop offset="1" stop-color="#2a221a"/></linearGradient>
  <linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b241c"/><stop offset="1" stop-color="#14110d"/></linearGradient>
  <radialGradient id="glow" cx=".5" cy="0" r="1"><stop offset="0" stop-color="#ffcf7a" stop-opacity=".55"/><stop offset=".6" stop-color="#ff9a3c" stop-opacity=".12"/><stop offset="1" stop-color="#ff9a3c" stop-opacity="0"/></radialGradient>
  <linearGradient id="cone" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd58a" stop-opacity=".45"/><stop offset="1" stop-color="#ffb04a" stop-opacity="0"/></linearGradient>
  <linearGradient id="pot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3a3a"/><stop offset="1" stop-color="#1c1c1c"/></linearGradient>
  <linearGradient id="vig" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".55"/></linearGradient>
</defs>'''


def room(rnd):
    s = [f'<rect width="{W}" height="{H}" fill="url(#wall)"/>']
    # back wall planks
    for i in range(0, W, 40):
        s.append(f'<rect x="{i}" y="0" width="38" height="250" fill="#231d16" opacity="{0.5 + rnd.random()*0.5:.2f}"/>')
    s.append(f'<polygon points="0,250 {W},250 {W},{H} 0,{H}" fill="url(#floor)"/>')
    # floor perspective lines
    for i in range(-6, 7):
        s.append(f'<line x1="{400 + i*40}" y1="250" x2="{400 + i*190}" y2="{H}" stroke="#3a3027" stroke-width="1" opacity=".6"/>')
    return s


def lamp(x, y, w, s):
    s.append(f'<polygon points="{x-w*0.35},{y+8} {x+w*0.35},{y+8} {x+w*1.1},{y+260} {x-w*1.1},{y+260}" fill="url(#cone)"/>')
    s.append(f'<line x1="{x}" y1="0" x2="{x}" y2="{y}" stroke="#0e0c0a" stroke-width="2"/>')
    s.append(f'<rect x="{x-w/2}" y="{y}" width="{w}" height="10" rx="3" fill="#cfcfcf"/>')
    s.append(f'<rect x="{x-w/2+4}" y="{y+8}" width="{w-8}" height="4" rx="2" fill="#fff4cf"/>')


def grow_room():
    rnd = random.Random(7)
    s = room(rnd)
    s.append(f'<ellipse cx="400" cy="0" rx="520" ry="380" fill="url(#glow)"/>')
    # three rows receding: back (small) to front (big)
    rows = [(262, 0.45, 12), (300, 0.7, 9), (370, 1.0, 6)]
    for (base, sc, count) in rows:
        span = 760 * (0.55 + 0.45 * sc)
        x0 = 400 - span / 2
        for i in range(count):
            x = x0 + span * (i + 0.5) / count
            ph = 120 * sc * rnd.uniform(0.85, 1.1)
            pw = 46 * sc
            s.append(plant(x, base - 14 * sc, ph, rnd))
            s.append(f'<path d="M{x-pw/2:.1f} {base-18*sc:.1f} h{pw:.1f} l{-pw*0.12:.1f} {22*sc:.1f} h{-pw*0.76:.1f} z" fill="url(#pot)"/>')
        if sc < 1:
            for i in range(3):
                lamp(x0 + span * (i + 0.5) / 3, 40 + (1 - sc) * 40, 90 * sc, s)
    for i in range(3):
        lamp(140 + i * 260, 30, 120, s)
    # front tray
    s.append('<rect x="20" y="372" width="760" height="16" rx="3" fill="#3b3229"/>')
    # "expanded" hint: measuring arrows on the floor
    s.append('<g stroke="#f2c14e" stroke-width="4" fill="none" stroke-linecap="round" opacity=".9">'
             '<path d="M70 440 H730"/><path d="M90 425 L70 440 L90 455"/><path d="M710 425 L730 440 L710 455"/></g>')
    s.append(f'<rect width="{W}" height="{H}" fill="url(#vig)"/>')
    return s


def person(x, y, shirt, skin, hair, rnd, flip=1):
    s = []
    s.append(f'<rect x="{x-38}" y="{y}" width="76" height="120" rx="30" fill="{shirt}"/>')                      # torso
    s.append(f'<rect x="{x-26}" y="{y+18}" width="52" height="90" rx="10" fill="#e9e6df" opacity=".9"/>')       # apron
    s.append(f'<circle cx="{x}" cy="{y-26}" r="30" fill="{skin}"/>')                                             # head
    s.append(f'<path d="M{x-31} {y-30} a31 31 0 0 1 62 0 q-30 -14 -62 0z" fill="{hair}"/>')                      # hair
    s.append(f'<rect x="{x-20}" y="{y-20}" width="40" height="16" rx="6" fill="#bfe3f2"/>')                      # mask
    s.append(f'<rect x="{x-24}" y="{y-36}" width="48" height="10" rx="5" fill="#1b1b1b" opacity=".8"/>')         # goggles
    # arms toward the table
    s.append(f'<path d="M{x-34} {y+30} Q{x-56} {y+80} {x-22+8*flip} {y+108}" stroke="{shirt}" stroke-width="20" fill="none" stroke-linecap="round"/>')
    s.append(f'<path d="M{x+34} {y+30} Q{x+56} {y+80} {x+22+8*flip} {y+108}" stroke="{shirt}" stroke-width="20" fill="none" stroke-linecap="round"/>')
    s.append(f'<circle cx="{x-22+8*flip}" cy="{y+110}" r="10" fill="#7cc4e4"/><circle cx="{x+22+8*flip}" cy="{y+110}" r="10" fill="#7cc4e4"/>')  # gloves
    return ''.join(s)


def staff():
    rnd = random.Random(11)
    s = room(rnd)
    s.append(f'<ellipse cx="400" cy="0" rx="520" ry="380" fill="url(#glow)"/>')
    # background plants row
    for i in range(10):
        x = 60 + i * 76
        s.append(plant(x, 250, 95 * rnd.uniform(.85, 1.1), rnd))
        s.append(f'<path d="M{x-17} 246 h34 l-4 16 h-26 z" fill="url(#pot)"/>')
    for i in range(3):
        lamp(140 + i * 260, 28, 120, s)
    # workers behind the table
    s.append(person(270, 255, "#2f6f8f", "#c98d64", "#2a1a10", rnd, 1))
    s.append(person(530, 250, "#7a4a8f", "#8a5a3c", "#111", rnd, -1))
    # table
    s.append('<rect x="120" y="360" width="560" height="22" rx="4" fill="#8a7a62"/>')
    s.append('<rect x="130" y="382" width="16" height="110" fill="#5c5040"/><rect x="654" y="382" width="16" height="110" fill="#5c5040"/>')
    # trimmed buds + trays on the table
    s.append('<rect x="330" y="340" width="140" height="22" rx="4" fill="#d9d9d9"/>')
    for i in range(9):
        bx = 345 + i * 14 + rnd.uniform(-2, 2)
        s.append(f'<ellipse cx="{bx:.1f}" cy="{344 + rnd.uniform(-2,2):.1f}" rx="8" ry="6" fill="{rnd.choice(["#6dae4f", "#5a9a40", "#83c25f"])}"/>')
    s.append(plant(200, 360, 70, rnd))
    s.append(plant(600, 360, 70, rnd))
    # clipboard + speed gauge badge
    s.append('<rect x="610" y="300" width="56" height="70" rx="5" fill="#c9b28a" transform="rotate(8 638 335)"/>')
    s.append('<g transform="translate(700 70)"><circle r="48" fill="#11161c" stroke="#f2c14e" stroke-width="5"/>'
             '<path d="M-30 14 A34 34 0 1 1 30 14" fill="none" stroke="#3a4552" stroke-width="7" stroke-linecap="round"/>'
             '<path d="M-30 14 A34 34 0 0 1 22 -24" fill="none" stroke="#3fb950" stroke-width="7" stroke-linecap="round"/>'
             '<line x1="0" y1="0" x2="20" y2="-22" stroke="#f2c14e" stroke-width="5" stroke-linecap="round"/><circle r="6" fill="#f2c14e"/></g>')
    s.append(f'<rect width="{W}" height="{H}" fill="url(#vig)"/>')
    return s


for name, fn in (("weed_capacity", grow_room), ("weed_staff", staff)):
    body = ''.join(fn())
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">{defs()}{body}</svg>'
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(svg)
    print(name, len(svg) // 1024, "KB")
