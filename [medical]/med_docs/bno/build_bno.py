# Offline converter (not loaded by MTA): [medical]/source/BNOTORZS.DBF + icd102019en.xml -> bno.db (SQLite).
#   python build_bno.py      (needs: pip install dbfread)
# The Hungarian text is the authority (never changed); the English name comes from WHO ICD-10 2019:
#   exact    : S0640 -> S06.4 (4th char, HU 5th char "0")
#   mod      : S0641 -> S06.4 + WHO 5th character modifier (e.g. "with open intracranial wound")
#   who5     : the WHO class has the 5 characters itself (e.g. M54.16)
#   cat      : HU "H" filler or a 4th char missing in the WHO 2019 (J46H0 -> J46): the WHO category name
#   parent   : a Hungarian 5th char extension without a WHO match: the WHO 4 / 3 character name (to review)
#   none     : no WHO code at all (Hungarian only)
import os, re, sqlite3, unicodedata, xml.etree.ElementTree as ET
from dbfread import DBF
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "source")
DB = os.path.join(HERE, "bno.db")

def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")

tree = ET.parse(os.path.join(SRC, "icd102019en.xml"))
root = tree.getroot()
XL = "{http://www.w3.org/XML/1998/namespace}lang"
def preferred(el):
    for r in el.findall("Rubric"):
        if r.get("kind") == "preferred":
            lab = r.find("Label")
            if lab is not None: return " ".join("".join(lab.itertext()).split())
    return None
classes, supers, mods, chapters = {}, {}, {}, {}
modifiers = {}
for m in root.findall("Modifier"):
    code = m.get("code")
    modifiers[code] = {}
for mc in root.findall("ModifierClass"):
    mod, sub = mc.get("modifier"), mc.get("code")
    modifiers.setdefault(mod, {})[sub] = preferred(mc)
for c in root.findall("Class"):
    code, kind = c.get("code"), c.get("kind")
    classes[code] = (kind, preferred(c))
    sc = c.find("SuperClass")
    if sc is not None: supers[code] = sc.get("code")
    mods[code] = [mb.get("code") for mb in c.findall("ModifiedBy")]
def chapter_of(code):
    seen = 0
    while code and seen < 10:
        k = classes.get(code, (None,))[0]
        if k == "chapter": return code
        code = supers.get(code); seen += 1
    return ""
def modifier_label(code4, digit):
    for c in (code4, code4[:3]):
        for m in mods.get(c, []):
            lab = modifiers.get(m, {}).get(digit)
            if lab: return lab
    return None

rows = []
stat = {}
os.chdir(SRC)  # dbfread globs the path: the [medical] brackets would break it
for r in DBF("BNOTORZS.DBF", encoding="cp852"):
    code = r["KOD10"].strip()
    if not code: continue
    hu = " ".join(r["NEV"].split())
    cat, c4, c5 = code[:3], code[3:4], code[4:5]
    who3 = cat
    who4 = cat + "." + c4 if c4 and c4 != "H" else None
    en, src = None, "none"
    if who4 and c5 and c5 not in ("0", "H"):
        w5 = who4 + c5
        if w5 in classes and classes[w5][1]: en, src = classes[w5][1], "who5"
        elif who4 in classes:
            lab = modifier_label(who4, c5)
            if lab: en, src = classes[who4][1] + ", " + lab[0].lower() + lab[1:], "mod"
            else: en, src = classes[who4][1], "parent"
    if not en and who4 and who4 in classes: en, src = classes[who4][1], "exact" if c5 in ("0", "H", "") else "parent"
    if not en and who4 and who3 in classes:
        # 4th character given as a WHO modifier of the category (E10.1 = E10 + "With ketoacidosis")
        lab = modifier_label(who3, "." + c4)
        if lab: en, src = classes[who3][1] + ", " + lab[0].lower() + lab[1:], "mod4"
    if not en and who3 in classes: en, src = classes[who3][1], "cat"
    if not en: en = hu
    stat[src] = stat.get(src, 0) + 1
    fmt = cat if (not c4 or c4 == "H") else cat + "." + c4 + (c5 if c5 and c5 not in ("0", "H") else "")
    sex = {"1": "m", "2": "f"}.get(str(r["NEM"]).strip(), "")
    rows.append((code, fmt, hu, en, src, (r["JEL"] or "").strip(), sex,
                 int(r["KOR_A"] or 0), int(r["KOR_F"] or 0) if r["KOR_F"] else 0,
                 str(r["ERV_KEZD"] or ""), str(r["ERV_VEGE"] or ""), chapter_of(who3),
                 norm(code + " " + fmt + " " + hu), norm(code + " " + fmt + " " + en)))
if os.path.exists(DB): os.remove(DB)
db = sqlite3.connect(DB)
db.execute("""CREATE TABLE bno (code TEXT PRIMARY KEY, code_fmt TEXT, name_hu TEXT, name_en TEXT, en_source TEXT,
    flag TEXT, sex TEXT, age_min INTEGER, age_max INTEGER, valid_from TEXT, valid_to TEXT, chapter TEXT,
    search_hu TEXT, search_en TEXT)""")
db.executemany("INSERT INTO bno VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
db.commit(); db.close()
print(len(rows), stat, os.path.getsize(DB))
