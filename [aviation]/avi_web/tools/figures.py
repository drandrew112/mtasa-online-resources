"""Draws the SVG figures of the sanandreascontrol.eu documents (avi_web/web/img/*.svg).

The airspace / procedure figures are drawn from the real data (avi_airspace, avi_nav), so run this
again after those change:  python tools/figures.py   (from the avi_web folder)
The figures are shown on the light "paper" of the document reader.
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.normpath(os.path.join(HERE, '..', 'web', 'img'))

NAV = json.load(open(os.path.join(ROOT, 'avi_nav', 'data', 'nav.json'), encoding='utf-8'))
ASP = json.load(open(os.path.join(ROOT, 'avi_airspace', 'data', 'airspaces.json'), encoding='utf-8'))
APT = json.load(open(os.path.join(ROOT, 'avi_airports', 'data', 'airports.json'), encoding='utf-8'))['airports']
FIX = {f['id']: f for f in NAV['fixes']}

INK = '#1d2433'
DIM = '#6b7486'
BLUE = '#1f5fc4'
RED = '#c8343a'
AMBER = '#d98a00'
GREEN = '#1f8a4c'
FONT = 'font-family="Segoe UI, Roboto, Arial, sans-serif"'
MONO = 'font-family="Consolas, monospace"'


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            f'<rect width="{w}" height="{h}" fill="#ffffff"/>{body}</svg>')


def save(name, content):
    with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
        f.write(content)
    print('wrote', name, len(content), 'bytes')


class View:
    """world box -> svg box (north up)"""

    def __init__(self, minx, miny, maxx, maxy, w, h, pad=20):
        self.s = min((w - 2 * pad) / (maxx - minx), (h - 2 * pad) / (maxy - miny))
        self.ox = pad + ((w - 2 * pad) - (maxx - minx) * self.s) / 2 - minx * self.s
        self.oy = pad + ((h - 2 * pad) - (maxy - miny) * self.s) / 2 + maxy * self.s

    def p(self, x, y):
        return self.ox + x * self.s, self.oy - y * self.s

    def path(self, pts, closed=False):
        d = ' '.join(('M' if i == 0 else 'L') + '%.1f,%.1f' % self.p(*pt) for i, pt in enumerate(pts))
        return d + (' Z' if closed else '')


def text(x, y, s, size=12, color=INK, anchor='start', weight='normal', mono=False):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{color}" text-anchor="{anchor}" '
            f'font-weight="{weight}" {MONO if mono else FONT}>{s}</text>')


def tri(x, y, color=INK, r=5):
    return f'<path d="M{x:.1f},{y - r:.1f} L{x + r * .9:.1f},{y + r * .7:.1f} L{x - r * .9:.1f},{y + r * .7:.1f} Z" fill="{color}"/>'


def arrowhead(x1, y1, x2, y2, color, size=9):
    a = math.atan2(y2 - y1, x2 - x1)
    p1 = (x2 - size * math.cos(a - .4), y2 - size * math.sin(a - .4))
    p2 = (x2 - size * math.cos(a + .4), y2 - size * math.sin(a + .4))
    return f'<path d="M{x2:.1f},{y2:.1f} L{p1[0]:.1f},{p1[1]:.1f} L{p2[0]:.1f},{p2[1]:.1f} Z" fill="{color}"/>'


# ---------------------------------------------------------------- centre sectors (real data)
def centre_sectors():
    W, H = 760, 520
    v = View(-6000, -6000, 6000, 6000, 500, H, 24)
    b = []
    cta = [a for a in ASP['airspaces'] if a['type'] == 'CTA'][0]
    tmas = [a for a in ASP['airspaces'] if a['type'] == 'TMA']
    ctrs = [a for a in ASP['airspaces'] if a['type'] == 'CTR']
    # north / south fill
    for s in ASP['centre']['sectors']:
        if s['upper']:
            continue
        col = '#e3ecfa' if s['side'] == 'N' else '#f6ead6'
        b.append(f'<path d="{v.path(s["polygon"], True)}" fill="{col}"/>')
    for a in tmas:
        b.append(f'<path d="{v.path(a["polygon"], True)}" fill="#ffffff" stroke="{BLUE}" stroke-width="1.3"/>')
    for a in ctrs:
        b.append(f'<path d="{v.path(a["polygon"], True)}" fill="none" stroke="{RED}" stroke-width="1.1" stroke-dasharray="5 3"/>')
    b.append(f'<path d="{v.path(cta["polygon"], True)}" fill="none" stroke="{INK}" stroke-width="2"/>')
    b.append(f'<path d="{v.path(ASP["centre"]["line"])}" fill="none" stroke="{INK}" stroke-width="2" stroke-dasharray="10 5"/>')
    for fid in ('ZEPHR', 'PALIS', 'VINEW'):
        f = FIX[fid]
        x, y = v.p(f['x'], f['y'])
        b.append(tri(x, y))
        b.append(text(x + 7, y - 6, fid, 11, INK, mono=True, weight='bold'))
    for icao, a in APT.items():
        x, y = v.p(a['arp'][0], a['arp'][1])
        b.append(text(x, y + 4, icao, 11, BLUE, 'middle', 'bold', True))
    x, y = v.p(-4500, 4300)
    b.append(text(x, y, 'NORTH', 18, '#3d5f99', weight='bold'))
    x, y = v.p(-4500, -5300)
    b.append(text(x, y, 'SOUTH', 18, '#9a6a1c', weight='bold'))
    # vertical split, right side
    X0 = 540
    b.append(text(X0, 40, 'Vertical split', 14, INK, weight='bold'))
    rows = [('FL660', 70), ('upper sectors  NU / SU', 120), ('FL205', 190), ('lower sectors  NL / SL', 260), ('SFC', 330)]
    b.append(f'<rect x="{X0}" y="70" width="190" height="120" fill="#eef2f8" stroke="{INK}"/>')
    b.append(f'<rect x="{X0}" y="190" width="190" height="140" fill="#f7f3ea" stroke="{INK}"/>')
    b.append(text(X0 + 95, 135, 'Upper: NU / SU', 13, INK, 'middle', 'bold'))
    b.append(text(X0 + 95, 152, 'above FL205', 12, DIM, 'middle'))
    b.append(text(X0 + 95, 260, 'Lower: NL / SL', 13, INK, 'middle', 'bold'))
    b.append(text(X0 + 95, 277, 'SFC - FL205, outside TMAs', 12, DIM, 'middle'))
    for lab, y in (('FL660', 70), ('FL205', 190), ('SFC', 330)):
        b.append(text(X0 - 6, y + 4, lab, 11, INK, 'end', mono=True))
    # legend
    ly = 380
    b.append(f'<line x1="{X0}" y1="{ly}" x2="{X0 + 26}" y2="{ly}" stroke="{INK}" stroke-width="2"/>')
    b.append(text(X0 + 34, ly + 4, 'FIR / CTA boundary', 12))
    b.append(f'<line x1="{X0}" y1="{ly + 22}" x2="{X0 + 26}" y2="{ly + 22}" stroke="{INK}" stroke-width="2" stroke-dasharray="10 5"/>')
    b.append(text(X0 + 34, ly + 26, 'North / South line', 12))
    b.append(f'<line x1="{X0}" y1="{ly + 44}" x2="{X0 + 26}" y2="{ly + 44}" stroke="{BLUE}" stroke-width="1.5"/>')
    b.append(text(X0 + 34, ly + 48, 'TMA (Approach)', 12))
    b.append(f'<line x1="{X0}" y1="{ly + 66}" x2="{X0 + 26}" y2="{ly + 66}" stroke="{RED}" stroke-width="1.3" stroke-dasharray="5 3"/>')
    b.append(text(X0 + 34, ly + 70, 'CTR (Tower)', 12))
    save('centre-sectors.svg', svg(W, H, ''.join(b)))


# ---------------------------------------------------------------- Los Santos 27L: points + go-around (real data)
def ls_points(go_around):
    a = APT['SALS']
    W, H = (760, 300) if go_around else (760, 430)
    v = View(-200, -3800, 3600, -2350, W, H, 34) if go_around else View(-500, -3900, 3700, -1200, W, H, 30)
    b = []
    # runways
    for rw in a['runways']:
        e1, e2 = rw['ends']
        x1, y1 = v.p(e1['x'], e1['y'])
        x2, y2 = v.p(e2['x'], e2['y'])
        b.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#9aa3b2" stroke-width="7"/>')
        # end idents above the northern runway, below the southern one (the final / go-around lines
        # run along the centre lines)
        dy = -8 if e1['y'] > -2550 else 17
        b.append(text(x1 + 2, y1 + dy, e1['ident'], 10, DIM, 'start', mono=True))
        b.append(text(x2 - 2, y2 + dy, e2['ident'], 10, DIM, 'end', mono=True))
    # extended centre line of 27L
    x1, y1 = v.p(2065, -2593)
    x2, y2 = v.p(3600, -2593)
    b.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{DIM}" stroke-dasharray="4 4"/>')
    if go_around:
        route = ['LS09RH', 'LS273', 'LS27P1', 'LS271', 'LS27L']
        pts = [(1440, -2593)] + [(FIX[f]['x'], FIX[f]['y']) for f in route]
        b.append(f'<path d="{v.path(pts)}" fill="none" stroke="{AMBER}" stroke-width="3"/>')
        for i in range(len(pts) - 1):
            (ax, ay), (bx, by) = v.p(*pts[i]), v.p(*pts[i + 1])
            mx, my = (ax + bx) / 2, (ay + by) / 2
            b.append(arrowhead(ax, ay, mx, my, AMBER, 11))
        fx, fy = v.p(3265, -2593)
        tx, ty = v.p(2065, -2593)
        b.append(f'<line x1="{fx:.1f}" y1="{fy:.1f}" x2="{tx:.1f}" y2="{ty:.1f}" stroke="{GREEN}" stroke-width="3"/>')
        b.append(arrowhead(fx, fy, (fx + tx) / 2, fy, GREEN, 11))
        labels = {'LS09RH': 'half final of 09R (straight ahead)', 'LS273': 'circuit corner',
                  'LS27P1': 'parallel fix (abeam threshold)', 'LS271': 'base', 'LS27L': 'final fix'}
        show = route
        x, y = v.p(1440, -2593)
        b.append(text(x - 30, y + 30, 'go-around starts', 11, AMBER, 'start', 'bold'))
    else:
        labels = {'LS27L': 'final fix (1200 m)', 'LS27LH': 'half final (600 m)', 'LS27P1': 'parallel P1',
                  'LS27P2': 'parallel P2', 'LS271': 'base 1', 'LS272': 'base 2', 'LS273': 'downwind 3',
                  'LS274': 'downwind 4', 'LS275': 'climb-out 5', 'LS276': 'turn 6', 'LS277': 'turn 7'}
        show = list(labels)
    for fid in show:
        f = FIX[fid]
        x, y = v.p(f['x'], f['y'])
        col = GREEN if fid == 'LS27L' else INK
        b.append(tri(x, y, col))
        below = f['y'] < -3000
        b.append(text(x, y + (18 if below else -10), fid, 11, col, 'middle', 'bold', True))
        b.append(text(x, y + (31 if below else -23), labels[fid], 10, DIM, 'middle'))
    if go_around:
        b.append(text(20, 24, 'Go-around 27L (SALSGA): climb to 3000 ft, every turn 90°', 13, INK, weight='bold'))
    else:
        b.append(text(20, 24, 'Procedure points of runway 27L (Los Santos)', 13, INK, weight='bold'))
    x, y = v.p(1750, -2494)
    b.append(text(x, y - 20, 'SALS', 11, BLUE, 'middle', 'bold', True))
    save('ls27l-goaround.svg' if go_around else 'ls27l-points.svg', svg(W, H, ''.join(b)))


# ---------------------------------------------------------------- final profile (schematic)
def final_profile():
    W, H = 760, 300
    b = []
    gx0, gy = 80, 240           # ground line
    thr = 680                   # threshold x
    m_per_px = 2500 / (thr - gx0)
    ft_per_px = 2600 / 200
    X = lambda m: thr - m / m_per_px
    Y = lambda ft: gy - ft / ft_per_px
    b.append(f'<line x1="40" y1="{gy}" x2="{W - 30}" y2="{gy}" stroke="{INK}" stroke-width="2"/>')
    b.append(f'<rect x="{thr}" y="{gy - 4}" width="60" height="6" fill="#9aa3b2"/>')
    b.append(text(thr + 30, gy + 20, 'runway', 11, DIM, 'start'))
    # go-around zone
    b.append(f'<path d="M{X(1200)},{Y(1700)} L{X(1200)},{Y(2500)}" stroke="{RED}" stroke-width="2"/>')
    b.append(f'<rect x="{X(1200) - 6}" y="{Y(2500)}" width="12" height="{Y(1700) - Y(2500)}" fill="{RED}" opacity=".15"/>')
    b.append(text(X(1200) + 10, Y(2150), 'above 1700 ft AGL = go-around', 11, RED))
    # glide path
    b.append(f'<line x1="{X(2500)}" y1="{Y(2500)}" x2="{thr}" y2="{gy}" stroke="{GREEN}" stroke-width="2.5"/>')
    b.append(text(X(1900) + 8, Y(1900) - 10, 'glide path: 1 ft per metre', 11, GREEN, weight='bold'))
    # level segment at 1500
    b.append(f'<line x1="{X(2500)}" y1="{Y(1500)}" x2="{X(1500)}" y2="{Y(1500)}" stroke="{BLUE}" stroke-width="2.5" stroke-dasharray="7 4"/>')
    b.append(text(X(2480), Y(1500) - 8, 'cleared 1500 ft', 11, BLUE))
    for m, name, ft in ((1200, 'final fix', 1200), (600, 'half final', 600)):
        b.append(f'<line x1="{X(m)}" y1="{gy}" x2="{X(m)}" y2="{Y(ft)}" stroke="{DIM}" stroke-dasharray="3 3"/>')
        b.append(tri(X(m), gy + 14, INK))
        b.append(text(X(m), gy + 34, f'{name}', 11, INK, 'middle', 'bold'))
        b.append(text(X(m), gy + 48, f'{m} m · {ft} ft AGL', 10, DIM, 'middle'))
        b.append(f'<circle cx="{X(m)}" cy="{Y(ft)}" r="4" fill="{GREEN}"/>')
    b.append(text(thr, gy + 20, 'threshold', 11, INK, 'end'))
    b.append(text(40, 24, 'The final (side view, not to scale vertically)', 13, INK, weight='bold'))
    b.append(text(40, 42, 'Landing clearance needed 400 m before the threshold', 11, DIM))
    b.append(f'<line x1="{X(400)}" y1="{gy - 2}" x2="{X(400)}" y2="{gy - 26}" stroke="{AMBER}" stroke-width="2"/>')
    b.append(text(X(400) - 6, gy - 14, '400 m', 10, AMBER, 'end', 'bold'))
    save('final-profile.svg', svg(W, H + 20, ''.join(b)))


# ---------------------------------------------------------------- approach geometry (schematic)
def approach_geometry():
    W, H = 760, 380
    b = []
    cy = 190
    thr = 640
    ff = 400                     # final fix x
    b.append(f'<rect x="{thr}" y="{cy - 6}" width="100" height="12" fill="#9aa3b2"/>')
    b.append(f'<line x1="40" y1="{cy}" x2="{thr}" y2="{cy}" stroke="{DIM}" stroke-dasharray="5 4"/>')
    b.append(f'<line x1="{ff}" y1="{cy}" x2="{thr}" y2="{cy}" stroke="{GREEN}" stroke-width="3"/>')
    b.append(arrowhead(ff, cy, ff + 130, cy, GREEN, 11))
    b.append(tri(ff, cy, GREEN, 7))
    b.append(text(ff, cy + 24, 'final fix', 11, GREEN, 'middle', 'bold'))
    b.append(text(thr + 50, cy + 28, 'runway', 11, DIM, 'middle'))
    # 1: STAR
    pts = [(120, 40), (260, 40), (400, 40), (ff, cy)]
    b.append(f'<path d="M120,40 L300,40 Q{ff},40 {ff},{cy - 10}" fill="none" stroke="{BLUE}" stroke-width="2.5"/>')
    b.append(arrowhead(ff, cy - 40, ff, cy - 10, BLUE, 10))
    b.append(text(120, 30, '1  on a STAR: flies it to the final fix', 12, BLUE, weight='bold'))
    # 2: heading intercept
    ix = 250
    b.append(f'<line x1="60" y1="{cy + 120}" x2="{ix}" y2="{cy}" stroke="{AMBER}" stroke-width="2.5"/>')
    b.append(arrowhead(60, cy + 120, ix - 10, cy + 6, AMBER, 10))
    b.append(f'<path d="M{ix - 60},{cy} A60,60 0 0,0 {ix - 51},{cy + 31}" fill="none" stroke="{AMBER}"/>')
    b.append(text(ix - 72, cy + 26, '≤30°', 11, AMBER, 'end', 'bold'))
    b.append(text(60, cy + 140, '2  heading that intercepts: keeps it and turns onto the final', 12, AMBER, weight='bold'))
    # 3: direct to nearest final fix, from the airport side via base point
    bx, by = ff - 90, cy + 90
    b.append(f'<path d="M560,{cy + 150} L{bx},{by} L{ff},{cy + 8}" fill="none" stroke="{RED}" stroke-width="2.5" stroke-dasharray="8 4"/>')
    b.append(arrowhead(560, cy + 150, bx + 8, by + 3, RED, 10))
    b.append(arrowhead(bx, by, ff - 3, cy + 12, RED, 10))
    b.append(f'<circle cx="{bx}" cy="{by}" r="4" fill="{RED}"/>')
    b.append(text(bx - 8, by + 4, 'base point', 11, RED, 'end'))
    b.append(text(420, cy + 172, '3  anywhere else: direct to the nearest final fix', 12, RED, weight='bold'))
    b.append(text(420, cy + 186, '(base point first when it is on the airport side)', 11, RED))
    save('approach-geometry.svg', svg(W, H, ''.join(b)))


# ---------------------------------------------------------------- labels (schematic)
def label_air():
    W, H = 760, 300
    b = []
    tx, ty = 120, 230
    b.append(f'<rect x="{tx - 5}" y="{ty - 5}" width="10" height="10" fill="none" stroke="{BLUE}" stroke-width="2"/>')
    for i, d in enumerate((14, 26, 38, 50, 62)):
        b.append(f'<circle cx="{tx - d}" cy="{ty + d * .45}" r="2" fill="{BLUE}" opacity="{.8 - i * .13:.2f}"/>')
    b.append(f'<line x1="{tx}" y1="{ty}" x2="{tx + 46}" y2="{ty - 30}" stroke="{BLUE}" stroke-width="1.5"/>')
    lx, ly = 170, 60
    b.append(f'<line x1="{tx + 4}" y1="{ty - 5}" x2="{lx}" y2="{ly + 100}" stroke="{BLUE}" opacity=".6"/>')
    b.append(f'<rect x="{lx - 8}" y="{ly - 20}" width="220" height="132" fill="#2e3440" rx="2"/>')
    lines = [
        [('NRA9521 ', '#8fc1ff'), ('CS ', '#ffffff'), ('B763/H', '#8fc1ff')],
        [('330 340 CAYO', '#8fc1ff')],
        [('330', '#8fc1ff')],
        [('VINEW1A 27L 270', '#8fc1ff')],
        [('3422 181 -1800', '#8fc1ff')],
    ]
    expl = ['callsign · controller · type / wake', 'altitude (×100 ft) · speed (kts) · destination',
            'cleared level (×100 ft)', 'waypoint or procedure · assigned heading', 'squawk · heading · vertical speed (hover)']
    for i, segs in enumerate(lines):
        y = ly + i * 24
        x = lx
        for s, c in segs:
            b.append(f'<text x="{x}" y="{y}" font-size="15" fill="{c}" {MONO} xml:space="preserve">{s}</text>')
            x += len(s) * 8.3
        b.append(f'<line x1="{lx + 216}" y1="{y - 5}" x2="{lx + 250}" y2="{y - 5}" stroke="{DIM}"/>')
        b.append(text(lx + 256, y - 1, expl[i], 12, INK))
    b.append(text(20, 24, 'Airborne label (hovered: every line shown)', 13, INK, weight='bold'))
    b.append(text(tx + 50, ty + 24, 'target · history dots · speed vector (leader line)', 11, DIM))
    save('label-air.svg', svg(W, H, ''.join(b)))


def label_ground():
    W, H = 760, 200
    b = []
    for i, (bg, title, sub, ex) in enumerate((
            ('#2355a5', 'LCX6979', '0 0211', 'departure (blue)'),
            ('#237d41', 'NRA8187', '0 4521', 'arrival (green)'))):
        x = 40 + i * 250
        b.append(f'<rect x="{x}" y="50" width="96" height="58" fill="{bg}" rx="2"/>')
        b.append(f'<text x="{x + 6}" y="70" font-size="16" fill="#ffffff" {FONT} font-weight="bold">{title}</text>')
        b.append(f'<text x="{x + 6}" y="86" font-size="11" fill="#e8eef8" {MONO}>{sub}</text>')
        b.append(f'<text x="{x + 6}" y="100" font-size="11" fill="#e8eef8" {MONO}>A321/M</text>')
        b.append(text(x, 130, ex, 12, INK, weight='bold'))
    b.append(f'<rect x="540" y="50" width="96" height="58" fill="#2355a5" rx="2" stroke="#e8b400" stroke-width="3"/>')
    b.append(text(540, 130, 'yellow frame:', 12, INK, weight='bold'))
    b.append(text(540, 146, 'waits for a clearance', 12, INK))
    b.append(text(40, 168, 'Lines: callsign · speed (kts) and squawk · type / wake', 12, DIM))
    b.append(text(20, 24, 'Ground labels', 13, INK, weight='bold'))
    save('label-ground.svg', svg(W, H, ''.join(b)))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    centre_sectors()
    ls_points(False)
    ls_points(True)
    final_profile()
    approach_geometry()
    label_air()
    label_ground()
