# Offline generator of the ER X-ray library (er/img/xr/xr_<part>_<finding>_<side>.jpg, 384x384).
# Synthetic radiographs in the style of the first library: black background, soft tissue, bright bones
# with a darker medullary canal, a side marker, a header and an exposure line. The anatomy is drawn for
# the LEFT side and mirrored for the right one; the texts are drawn after the mirroring.
#   python gen_xray.py            (pip install numpy pillow)
# Also mirrors the anatomy of the sided CT images (er/img/ct/<name>_r.jpg), keeping their texts.
import os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "er", "img", "xr")
CT = os.path.join(HERE, "..", "er", "img", "ct")
S = 384
os.makedirs(OUT, exist_ok=True)

def font(size):
    for f in ("consola.ttf", "cour.ttf", "DejaVuSansMono.ttf"):
        try: return ImageFont.truetype(f, size)
        except OSError: pass
    return ImageFont.load_default()
F_SMALL, F_MARK = font(11), font(22)

def layer():
    return Image.new("L", (S, S), 0)

def bone_rect(d, x0, y0, x1, y1, w_cort=7, val=215, canal=150, r=8):
    d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=val)
    if x1 - x0 > 2 * w_cort + 4:
        d.rounded_rectangle((x0 + w_cort, y0 + 6, x1 - w_cort, y1 - 6), radius=max(2, r - 3), fill=canal)

def ellipse(d, box, val): d.ellipse(box, fill=val)

def soft(d, poly, val=70): d.polygon(poly, fill=val)

def finish(an, side, part_label, kind="AP", seed=1, extra=None):
    rng = np.random.default_rng(seed)
    a = np.array(an.filter(ImageFilter.GaussianBlur(1.6)), dtype=np.float32)
    a += rng.normal(0, 6, a.shape)
    a = np.clip(a, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, "L")
    if side == "right": im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if extra: extra(im)
    im = im.convert("RGB")
    d = ImageDraw.Draw(im)
    d.rectangle((10, 10, 36, 40), fill=(235, 235, 235))
    d.text((15, 12), "R" if side == "right" else "L", fill=(10, 10, 10), font=F_MARK)
    side_txt = "" if side is None else ("R " if side == "right" else "L ")
    d.text((S - 10, 12), "All Saints SBO", fill=(225, 225, 225), font=F_SMALL, anchor="ra")
    d.text((S - 10, 27), side_txt + part_label, fill=(225, 225, 225), font=F_SMALL, anchor="ra")
    d.text((10, S - 22), f"{kind}  60 kV  5 mAs", fill=(225, 225, 225), font=F_SMALL)
    d.text((S - 10, S - 22), f"XR-2026-{100000 + seed:06d}", fill=(225, 225, 225), font=F_SMALL, anchor="ra")
    return im

def save(im, name): im.save(os.path.join(OUT, f"xr_{name}.jpg"), quality=88)

def crack(d, x0, y0, x1, y1, val=40, w=3, jag=4, seed=0):
    rnd = random.Random(seed)
    pts = []
    n = 6
    for i in range(n + 1):
        t = i / n
        pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + rnd.uniform(-jag, jag)))
    d.line(pts, fill=val, width=w)

# ---------------------------------------------------------------- limbs (left side drawn)

def long_bone_limb(part, finding, side, seed):
    an = layer(); d = ImageDraw.Draw(an)
    soft(d, [(120, 0), (270, 0), (285, S), (105, S)], 75)
    if part == "humerus":
        ellipse(d, (130, 8, 230, 92), 210)                     # head
        bone_rect(d, 160, 60, 205, 330)
        ellipse(d, (135, 300, 235, 360), 205)                  # condyles
        if finding == "fx":
            d.rectangle((150, 190, 215, 206), fill=75)
            crack(d, 156, 192, 210, 200, 55, 3, 3, seed)
    elif part == "femur":
        ellipse(d, (115, 0, 205, 70), 215)                     # head
        d.polygon([(165, 40), (200, 70), (195, 110), (150, 80)], fill=210)   # neck
        bone_rect(d, 170, 80, 220, 340)
        ellipse(d, (145, 320, 250, 384), 210)
        if finding == "fx":
            d.rectangle((160, 200, 230, 214), fill=75)
            an2 = an.crop((150, 214, 240, 384)); an.paste(an2, (162, 220))
    elif part == "tibia":
        ellipse(d, (130, 0, 245, 40), 210)
        bone_rect(d, 160, 20, 210, 360)                        # tibia
        bone_rect(d, 228, 30, 246, 350, w_cort=5, canal=170, r=5)   # fibula (lateral, image right for L)
        ellipse(d, (140, 345, 230, 384), 205)
        if finding in ("fx",):
            crack(d, 160, 220, 210, 236, 50, 4, 5, seed)
            crack(d, 228, 190, 246, 200, 45, 3, 2, seed + 1)
            sub = an.crop((150, 236, 252, 384)); an.paste(sub, (158, 240))
        if finding == "cast":
            crack(d, 162, 228, 208, 232, 150, 2, 2, seed)
    elif part == "forearm":
        bone_rect(d, 150, 0, 182, 300, w_cort=6)              # ulna (medial)
        bone_rect(d, 196, 0, 232, 300, w_cort=6)              # radius (lateral)
        ellipse(d, (190, 280, 250, 320), 210)                  # distal radius
        for i, (x, y) in enumerate([(150, 315), (178, 318), (206, 318), (230, 320), (160, 345), (190, 348), (218, 348)]):
            ellipse(d, (x, y, x + 26, y + 24), 195)            # carpals
        if finding == "colles":
            crack(d, 194, 268, 236, 278, 45, 4, 3, seed)
            sub = an.crop((190, 278, 252, 330)); an.paste(sub, (200, 274))
            ellipse(d, (154, 296, 170, 310), 70)               # ulnar styloid off
        if finding == "cast":
            crack(d, 196, 272, 232, 274, 150, 2, 1, seed)
    elif part == "elbow":
        bone_rect(d, 165, 0, 210, 170)
        ellipse(d, (135, 140, 245, 205), 210)
        bone_rect(d, 150, 200, 182, 384, w_cort=6)
        bone_rect(d, 196, 205, 232, 384, w_cort=6)
        ellipse(d, (190, 195, 236, 230), 205)
    elif part == "hand":
        soft(d, [(110, 40), (280, 40), (300, 384), (90, 384)], 70)
        for i in range(5):
            x = 125 + i * 33
            bone_rect(d, x, 170, x + 22, 270, w_cort=4, canal=170, r=6)       # metacarpals
            bone_rect(d, x + 2, 90, x + 20, 162, w_cort=4, canal=175, r=6)   # proximal phalanx
            bone_rect(d, x + 3, 40, x + 19, 84, w_cort=3, canal=180, r=5)
        for x, y in [(130, 285), (165, 288), (200, 288), (235, 286), (150, 320), (190, 322), (225, 320)]:
            ellipse(d, (x, y, x + 28, y + 26), 195)
    elif part == "knee":
        bone_rect(d, 160, 0, 215, 150)
        ellipse(d, (125, 120, 250, 205), 212)
        ellipse(d, (165, 105, 210, 150), 190)                  # patella
        d.rounded_rectangle((128, 215, 248, 245), radius=8, fill=210)
        bone_rect(d, 160, 240, 210, 384)
        bone_rect(d, 228, 250, 246, 384, w_cort=5, canal=170, r=5)
    elif part == "ankle":
        bone_rect(d, 160, 0, 210, 230)
        bone_rect(d, 228, 0, 246, 255, w_cort=5, canal=170, r=5)
        ellipse(d, (150, 230, 250, 300), 205)                  # talus
        d.rounded_rectangle((130, 300, 270, 360), radius=20, fill=190)   # calcaneus / foot
        if finding == "fx":
            crack(d, 226, 196, 248, 226, 45, 4, 3, seed)
            sub = an.crop((224, 226, 252, 260)); an.paste(sub, (232, 228))
    elif part == "foot":
        soft(d, [(100, 30), (300, 30), (290, 384), (110, 384)], 70)
        for i in range(5):
            x = 120 + i * 34
            bone_rect(d, x, 150, x + 22, 280, w_cort=4, canal=170, r=6)
            bone_rect(d, x + 3, 70, x + 19, 142, w_cort=4, canal=175, r=6)
            bone_rect(d, x + 4, 30, x + 18, 62, w_cort=3, canal=180, r=5)
        d.rounded_rectangle((130, 290, 280, 384), radius=24, fill=190)
    return an

LIMBS = {
    "humerus": ("upper arm", ["normal", "fx"]), "elbow": ("elbow", ["normal"]),
    "forearm": ("forearm / wrist", ["normal", "colles", "cast"]), "hand": ("hand", ["normal"]),
    "femur": ("thigh", ["normal", "fx"]), "knee": ("knee", ["normal"]),
    "tibia": ("lower leg", ["normal", "fx", "cast"]), "ankle": ("ankle", ["normal", "fx"]), "foot": ("foot", ["normal"]),
}

# ---------------------------------------------------------------- chest PA

def chest(finding, side, seed):
    an = layer(); d = ImageDraw.Draw(an)
    soft(d, [(40, 20), (344, 20), (370, 384), (14, 384)], 80)
    lung = 28
    d.ellipse((60, 60, 186, 330), fill=lung)                   # patient's right lung (image left)
    d.ellipse((198, 60, 324, 330), fill=lung)                  # patient's left lung (image right)
    rnd = random.Random(seed)
    for y in range(80, 320, 14):                               # vessel markings
        for _ in range(8):
            x = rnd.uniform(70, 315)
            d.line((x, y, x + rnd.uniform(-10, 10), y + 8), fill=60, width=1)
    for i in range(9):                                         # ribs
        y = 70 + i * 28
        d.arc((50, y - 30, 192, y + 40), 200, 340, fill=170, width=6)
        d.arc((192, y - 30, 334, y + 40), 200, 340, fill=170, width=6)
    d.rectangle((180, 20, 204, 384), fill=150)                 # spine / mediastinum
    d.ellipse((170, 170, 300, 320), fill=150)                  # heart (left)
    d.line((90, 40, 185, 70), fill=200, width=8); d.line((294, 40, 199, 70), fill=200, width=8)  # clavicles
    d.chord((50, 300, 196, 380), 180, 360, fill=170); d.chord((188, 310, 334, 390), 180, 360, fill=170)  # diaphragm
    # findings on the LEFT lung (image right); the right side is the mirrored image
    if finding == "ptx":
        d.ellipse((198, 60, 324, 330), fill=12)
        d.ellipse((215, 120, 285, 300), fill=55)                # collapsed lung
    elif finding == "htx":
        d.rectangle((198, 230, 330, 335), fill=160)
        d.chord((198, 200, 330, 260), 0, 180, fill=160)
    elif finding == "ribfx":
        d.rectangle((250, 182, 268, 196), fill=40)
    elif finding == "contusion":
        for _ in range(9):
            x, y = rnd.uniform(215, 300), rnd.uniform(120, 280)
            d.ellipse((x, y, x + 34, y + 26), fill=95)
    elif finding == "edema":
        for cx in (130, 255):
            for _ in range(12):
                x, y = cx + rnd.uniform(-45, 45), rnd.uniform(120, 290)
                d.ellipse((x, y, x + 30, y + 22), fill=85)
    return an

# ---------------------------------------------------------------- pelvis AP

def pelvis(finding, side, seed):
    an = layer(); d = ImageDraw.Draw(an)
    soft(d, [(20, 40), (364, 40), (380, 384), (4, 384)], 80)
    d.chord((60, 40, 324, 260), 180, 360, fill=200)             # iliac wings
    d.chord((95, 70, 289, 230), 180, 360, fill=80)
    d.rectangle((168, 60, 216, 200), fill=180)                  # sacrum
    d.ellipse((120, 200, 180, 290), fill=200); d.ellipse((132, 215, 168, 275), fill=80)   # obturator R
    d.ellipse((204, 200, 264, 290), fill=200); d.ellipse((216, 215, 252, 275), fill=80)   # obturator L
    for x0 in (60, 254):                                         # hips: head + neck + shaft
        d.ellipse((x0, 160, x0 + 70, 230), fill=215)
        d.polygon([(x0 + 35, 200), (x0 + 60, 225), (x0 + 50, 270), (x0 + 22, 245)], fill=210)
        bone_rect(d, x0 + 20, 250, x0 + 62, 384)
    if finding == "neckfx":                                      # left femoral neck (image right)
        crack(d, 270, 210, 300, 236, 45, 4, 3, seed)
        sub = an.crop((270, 230, 322, 384)); an.paste(sub, (276, 244))
    elif finding == "fx":                                        # pubic rami / ring
        crack(d, 210, 205, 236, 230, 45, 4, 3, seed); crack(d, 150, 260, 170, 286, 45, 4, 3, seed + 1)
    return an

# ---------------------------------------------------------------- spine (lateral)

def spine(level, finding, seed):
    an = layer(); d = ImageDraw.Draw(an)
    soft(d, [(90, 0), (300, 0), (300, 384), (90, 384)], 75)
    n = 7 if level == "c" else 6
    h = 384 / n
    for i in range(n):
        y = i * h + 6
        x0 = 150 + (i * 4 if level == "c" else (math.sin(i / n * math.pi) * 14))
        d.rounded_rectangle((x0, y, x0 + 70, y + h - 16), radius=6, fill=205)
        d.rectangle((x0 + 70, y + 8, x0 + 110, y + h - 24), fill=170)   # posterior elements
    if finding == "fx":
        i = n // 2
        y = i * h + 6
        x0 = 150 + (i * 4 if level == "c" else (math.sin(i / n * math.pi) * 14))
        d.rectangle((x0 - 2, y - 2, x0 + 72, y + h - 14), fill=75)
        d.polygon([(x0, y + 22), (x0 + 70, y + 4), (x0 + 70, y + h - 16), (x0, y + h - 16)], fill=215)   # wedge
        d.polygon([(x0 + 60, y + h - 30), (x0 + 82, y + h - 26), (x0 + 74, y + h - 14)], fill=215)       # fragment
    return an

def main():
    seed = 300
    made = []
    for part, (label, findings) in LIMBS.items():
        for f in findings:
            for side in ("left", "right"):
                seed += 1
                im = finish(long_bone_limb(part, f, side, seed), side, label, seed=seed)
                save(im, f"{part}_{f}_{side}"); made.append(f"{part}_{f}_{side}")
    for f in ("normal", "ptx", "htx", "ribfx", "contusion", "edema"):
        for side in (("left", "right") if f in ("ptx", "htx", "ribfx", "contusion") else ("left",)):
            seed += 1
            im = finish(chest(f, side, seed), side if f != "normal" and f != "edema" else None, "chest PA", "PA", seed)
            name = f"chest_{f}" + (f"_{side}" if f in ("ptx", "htx", "ribfx", "contusion") else "")
            save(im, name); made.append(name)
    for f in ("normal", "neckfx", "fx"):
        for side in (("left", "right") if f == "neckfx" else ("left",)):
            seed += 1
            im = finish(pelvis(f, side, seed), side if f == "neckfx" else None, "pelvis / hips", seed=seed)
            name = f"pelvis_{f}" + (f"_{side}" if f == "neckfx" else "")
            save(im, name); made.append(name)
    for level in ("c", "t", "l"):
        for f in ("normal", "fx"):
            seed += 1
            im = finish(spine(level, f, seed), None, {"c": "cervical spine", "t": "thoracic spine", "l": "lumbar spine"}[level], "LAT", seed)
            save(im, f"spine_{level}_{f}"); made.append(f"spine_{level}_{f}")
    print(len(made), "x-ray images")
    # CT: the anatomy of the sided images mirrored (patient's right lesion), the texts kept
    n = 0
    for name in ("head_edh", "head_sdh", "head_contusion", "head_ich", "head_fracture", "chest_ptx_lung", "chest_htx_med",
                 "chest_contusion_lung", "chest_ribfx_bone"):
        p = os.path.join(CT, name + ".jpg")
        if not os.path.exists(p): continue
        im = Image.open(p).convert("RGB")
        box = (44, 32, 340, 352)
        im.paste(im.crop(box).transpose(Image.FLIP_LEFT_RIGHT), box)
        im.save(os.path.join(CT, name + "_r.jpg"), quality=90); n += 1
    print(n, "mirrored CT images")

if __name__ == "__main__":
    main()
