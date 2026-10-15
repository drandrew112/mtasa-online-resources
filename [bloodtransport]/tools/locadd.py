"""Dev helper: merge texts into the v_locals catalogs (en + hu) and keep v_locals/meta.xml in sync.
usage: python tools/loc_bt.py"""
import json, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.abspath(os.path.join(ROOT, "..", "[core]", "v_locals"))

def add(ns, en, hu):
    assert set(en) == set(hu), ("key mismatch", set(en) ^ set(hu))
    for lang, data in (("en", en), ("hu", hu)):
        path = os.path.join(LOC, "locales", lang, ns + ".json")
        cur = {}
        if os.path.exists(path):
            cur = json.load(open(path, encoding="utf-8"))
        cur.update(data)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(dict(sorted(cur.items())), f, ensure_ascii=False, indent=2)
            f.write("\n")
    meta = os.path.join(LOC, "meta.xml")
    s = open(meta, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    for lang in ("en", "hu"):
        line = f'<file src="locales/{lang}/{ns}.json" />'
        if line in s: continue
        last = [m for m in re.finditer(rf'[ \t]*<file src="locales/{lang}/[^"]+\.json" />', s)][-1]
        s = s[:last.end()] + nl + "    " + line + s[last.end():]
    open(meta, "w", encoding="utf-8", newline="").write(s)
