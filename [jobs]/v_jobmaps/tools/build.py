#!/usr/bin/env python3
"""v_jobmaps build tool (run with: python -I tools/build.py <command> ...)

  import <zip|folder> <name> [--title "Title"] [--distance 299]
        converts a JStreamer map pack (gta3.JSD / gta3.JSP + Content/{models,coll,textures}, e.g.
        1580665324_HG.zip) into the v_jobmaps format in maps/<name>/ :

            maps/<name>/<name>.map     MTA map editor format; model="hr01" = custom model of map.json,
                                       model="1234" = normal GTA model; removeWorldObject is supported
            maps/<name>/map.json       title, shared texture archives, model definitions
            maps/<name>/models/*.dff   col/*.col   textures/*.txd

        a pack may share ONE txd between all its dffs (JStreamer does): map.json "txds" lists every
        archive once, each model names the archive it imports.  Also checks that every texture a dff
        uses is inside the txd it is given.

  meta     rewrites the <file> list of meta.xml and maps/index.json from the maps/ folders
  check    validates every map folder (files, model names, textures) without writing anything

The resource is already in the format; only a new pack needs `import` and then `meta`.
"""
import json
import os
import re
import struct
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "maps")
META = os.path.join(ROOT, "meta.xml")
MARK_BEGIN = "    <!-- BEGIN MAP FILES (tools/build.py meta) -->"
MARK_END = "    <!-- END MAP FILES -->"

# ----------------------------------------------------------------------------- RenderWare chunks


def chunks(data, start=0, end=None):
    """yield (type, size, offset_of_payload) for the chunks between start and end"""
    end = len(data) if end is None else end
    pos = start
    while pos + 12 <= end:
        ctype, size, _ver = struct.unpack_from("<III", data, pos)
        yield ctype, size, pos + 12
        pos += 12 + size


def txd_textures(data):
    """names of all textures of a txd (case-insensitive set)"""
    names = set()
    for ctype, size, off in chunks(data):
        if ctype != 0x16:  # Texture Dictionary
            continue
        for t2, s2, o2 in chunks(data, off, off + size):
            if t2 != 0x15:  # Texture Native
                continue
            for t3, s3, o3 in chunks(data, o2, o2 + s2):
                if t3 == 0x01:  # struct: platform(4) filter(4) name[32] mask[32]
                    raw = data[o3 + 8:o3 + 40]
                    names.add(raw.split(b"\0")[0].decode("latin1").lower())
                    break
    return names


def dff_textures(data):
    """names of all textures the materials of a dff use"""
    names = set()

    def walk(start, end):
        for ctype, size, off in chunks(data, start, end):
            if ctype == 0x06:  # Texture
                for t2, s2, o2 in chunks(data, off, off + size):
                    if t2 == 0x02:  # String: the first one is the texture name
                        names.add(data[o2:o2 + s2].split(b"\0")[0].decode("latin1").lower())
                        break
            elif ctype in (0x10, 0x14, 0x0E, 0x08, 0x07, 0x1A, 0x03, 0x05, 0x15):  # containers
                walk(off, off + size)

    # clump 0x10 > geometry list 0x1A > geometry 0x0F > material list 0x08 > material 0x07 > texture 0x06
    def walk_all(start, end):
        for ctype, size, off in chunks(data, start, end):
            if ctype == 0x06:
                walk(off - 12, off + size)
            elif ctype in (0x10, 0x1A, 0x0F, 0x08, 0x07, 0x03, 0x05, 0x14, 0x0E):
                walk_all(off, off + size)

    walk_all(0, len(data))
    return names


# ----------------------------------------------------------------------------- reading a JStreamer pack


class Pack:
    """a JStreamer folder (or zip): the directory holding gta3.JSD + gta3.JSP"""

    def __init__(self, source):
        self.tmp = None
        if os.path.isdir(source):
            base = source
        else:
            self.tmp = tempfile.TemporaryDirectory(prefix="v_jobmaps_")
            with zipfile.ZipFile(source) as z:
                for info in z.infolist():  # no path escapes
                    target = os.path.normpath(os.path.join(self.tmp.name, info.filename))
                    if not target.startswith(os.path.normpath(self.tmp.name)):
                        raise SystemExit("unsafe path in zip: " + info.filename)
                z.extractall(self.tmp.name)
            base = self.tmp.name
        self.dir = None
        for dirpath, _dirs, files in os.walk(base):
            low = {f.lower() for f in files}
            if "gta3.jsd" in low and "gta3.jsp" in low:
                self.dir = dirpath
                break
        if not self.dir:
            raise SystemExit("no gta3.JSD + gta3.JSP found in " + source)
        # optional id list of the streamer core (name -> gta model id)
        self.ids = {}
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                if f.lower() == "ids.id":
                    with open(os.path.join(dirpath, f), encoding="latin1") as fh:
                        for line in fh:
                            p = line.strip().split(",")
                            if len(p) >= 2 and p[0].isdigit():
                                self.ids[p[1]] = int(p[0])

    def file(self, *parts):
        path = os.path.join(self.dir, *parts)
        if os.path.isfile(path):
            return path
        # case-insensitive fallback
        folder = os.path.dirname(path)
        want = os.path.basename(path).lower()
        if os.path.isdir(folder):
            for f in os.listdir(folder):
                if f.lower() == want:
                    return os.path.join(folder, f)
        return None

    def text(self, name):
        path = self.file(name)
        if not path:
            raise SystemExit(name + " missing in the pack")
        with open(path, encoding="latin1") as fh:
            return [l.strip() for l in fh.read().splitlines() if l.strip()]

    def close(self):
        if self.tmp:
            self.tmp.cleanup()


def fmt(v):
    v = float(v)
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def esc(s):
    return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;")


# ----------------------------------------------------------------------------- import


def cmd_import(args):
    title = None
    distance = None
    rest = []
    i = 0
    while i < len(args):
        if args[i] == "--title":
            title = args[i + 1]
            i += 2
        elif args[i] == "--distance":
            distance = float(args[i + 1])
            i += 2
        else:
            rest.append(args[i])
            i += 1
    if len(rest) != 2 or not re.fullmatch(r"[a-z0-9_]+", rest[1]):
        raise SystemExit('usage: import <zip|folder> <name a-z0-9_> [--title "..."] [--distance 299]')
    source, name = rest
    out = os.path.join(MAPS, name)
    pack = Pack(source)
    try:
        # --- definitions (gta3.JSD): name,dff,txd,col,drawdistance,alpha,cull,lod[,on,off]
        defs = {}
        for line in pack.text("gta3.JSD"):
            p = line.split(",")
            if len(p) < 5:
                continue
            defs[p[0]] = {
                "dff": p[1], "txd": p[2], "col": p[3],
                "distance": float(p[4]) if distance is None else distance,
                "doublesided": (p[6].lower() == "true") if len(p) > 6 else True,
                "alpha": (p[5].lower() == "true") if len(p) > 5 and p[5] != "nil" else False,
            }
        # --- placements (gta3.JSP): first line = offset, then name,int,dim,x,y,z,rx,ry,rz ('!' = ignored)
        lines = pack.text("gta3.JSP")
        ox, oy, oz = [float(v) for v in lines[0].split(",")[:3]]
        placed = []
        for line in lines[1:]:
            p = line.split(",")
            if p[0] == "!" or len(p) < 9:
                continue
            placed.append((p[0], int(float(p[1])), float(p[3]) + ox, float(p[4]) + oy, float(p[5]) + oz,
                           float(p[6]), float(p[7]), float(p[8])))

        used = sorted({p[0] for p in placed if p[0] in defs})
        unknown = sorted({p[0] for p in placed if p[0] not in defs})
        for n in unknown:
            if n not in pack.ids:
                raise SystemExit("model '%s' is neither a definition of the pack nor a GTA model name" % n)

        os.makedirs(os.path.join(out, "models"), exist_ok=True)
        os.makedirs(os.path.join(out, "col"), exist_ok=True)
        os.makedirs(os.path.join(out, "textures"), exist_ok=True)

        copied = {}

        def copy(kind_dir, src_dir, base, ext):
            dst = os.path.join(out, kind_dir, base.lower() + ext)
            src = pack.file("Content", src_dir, base + ext)
            if not src:
                raise SystemExit("missing %s/%s%s in the pack" % (src_dir, base, ext))
            if src not in copied:
                with open(src, "rb") as a, open(dst, "wb") as b:
                    b.write(a.read())
                copied[src] = dst
            return kind_dir + "/" + base.lower() + ext

        models, txds, problems = {}, {}, []
        txd_names = {}
        for n in used:
            d = defs[n]
            model = {
                "dff": copy("models", "models", d["dff"], ".dff"),
                "col": copy("col", "coll", d["col"], ".col"),
                "txd": d["txd"].lower(),
                "distance": d["distance"],
                "doublesided": d["doublesided"],
            }
            if d["alpha"]:
                model["alpha"] = True
            if d["txd"].lower() not in txds:
                txds[d["txd"].lower()] = copy("textures", "textures", d["txd"], ".txd")
                with open(copied[pack.file("Content", "textures", d["txd"] + ".txd")], "rb") as fh:
                    txd_names[d["txd"].lower()] = txd_textures(fh.read())
            with open(os.path.join(out, model["dff"]), "rb") as fh:
                missing = dff_textures(fh.read()) - txd_names[model["txd"]]
            if missing:
                problems.append("%s: textures not in %s.txd: %s" % (n, model["txd"], ", ".join(sorted(missing))))
            models[n] = model

        # --- the .map
        rows = ['<map edf:definitions="editor_main">']
        for k, (n, interior, x, y, z, rx, ry, rz) in enumerate(placed, 1):
            ref = n if n in defs else str(pack.ids[n])
            rows.append('    <object id="%s (%d)" model="%s" interior="%d" dimension="0" posX="%s" posY="%s" posZ="%s" '
                        'rotX="%s" rotY="%s" rotZ="%s" scale="1" doublesided="false"></object>'
                        % (esc(n), k, esc(ref), interior, fmt(x), fmt(y), fmt(z), fmt(rx), fmt(ry), fmt(rz)))
        rows.append("</map>")
        with open(os.path.join(out, name + ".map"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(rows) + "\n")

        with open(os.path.join(out, "map.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"name": name, "title": title or name.replace("_", " ").title(),
                       "txds": txds, "models": models}, fh, indent=2, sort_keys=True)
            fh.write("\n")

        print("imported %s: %d objects, %d custom models, %d texture archive(s), %d GTA model refs"
              % (name, len(placed), len(models), len(txds), len(placed) - sum(1 for p in placed if p[0] in defs)))
        shared = {t: sum(1 for m in models.values() if m["txd"] == t) for t in txds}
        for t, c in shared.items():
            print("  txd %s shared by %d model(s)" % (t, c))
        for p in problems:
            print("  PROBLEM " + p)
        unused = sorted(set(defs) - set(used))
        if unused:
            print("  definitions never placed (skipped): " + ", ".join(unused))
    finally:
        pack.close()
    cmd_meta([])


# ----------------------------------------------------------------------------- meta / check


def map_folders():
    out = []
    if os.path.isdir(MAPS):
        for n in sorted(os.listdir(MAPS)):
            if os.path.isfile(os.path.join(MAPS, n, "map.json")):
                out.append(n)
    return out


def map_files(name):
    """every client file of a map folder (relative to the resource, forward slashes)"""
    with open(os.path.join(MAPS, name, "map.json"), encoding="utf-8") as fh:
        data = json.load(fh)
    files = set(data.get("txds", {}).values())
    for m in data.get("models", {}).values():
        files.add(m["dff"])
        files.add(m["col"])
    return ["maps/%s/%s" % (name, f) for f in sorted(files)]


def cmd_meta(_args):
    names = map_folders()
    rows = [MARK_BEGIN]
    for n in names:
        rows.append("    <!-- %s -->" % n)
        for f in map_files(n):
            rows.append('    <file src="%s" type="client" />' % f)
    rows.append(MARK_END)
    with open(META, encoding="utf-8") as fh:
        text = fh.read()
    if MARK_BEGIN not in text or MARK_END not in text:
        raise SystemExit("meta.xml has no BEGIN/END MAP FILES markers")
    a = text.index(MARK_BEGIN)
    b = text.index(MARK_END) + len(MARK_END)
    with open(META, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text[:a] + "\n".join(rows) + text[b:])
    with open(os.path.join(MAPS, "index.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"maps": names}, fh, indent=2)
        fh.write("\n")
    print("meta.xml + maps/index.json: %d map(s), %d file(s)" % (len(names), sum(len(map_files(n)) for n in names)))


def cmd_check(_args):
    bad = 0
    for n in map_folders():
        with open(os.path.join(MAPS, n, "map.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        if not os.path.isfile(os.path.join(MAPS, n, n + ".map")):
            print("%s: %s.map missing" % (n, n))
            bad += 1
        for f in map_files(n):
            if not os.path.isfile(os.path.join(ROOT, f)):
                print("%s: missing file %s" % (n, f))
                bad += 1
        txd_names = {}
        for t, f in data.get("txds", {}).items():
            with open(os.path.join(ROOT, "maps", n, f), "rb") as fh:
                txd_names[t] = txd_textures(fh.read())
        for mn, m in data.get("models", {}).items():
            if m["txd"] not in txd_names:
                print("%s: model %s uses unknown txd %s" % (n, mn, m["txd"]))
                bad += 1
                continue
            with open(os.path.join(MAPS, n, m["dff"]), "rb") as fh:
                missing = dff_textures(fh.read()) - txd_names[m["txd"]]
            if missing:
                print("%s: %s textures not in txd: %s" % (n, mn, ", ".join(sorted(missing))))
                bad += 1
        with open(os.path.join(MAPS, n, n + ".map"), encoding="utf-8") as fh:
            used = set(re.findall(r'<object [^>]*model="([^"]+)"', fh.read()))
        for u in sorted(used):
            if not u.isdigit() and u not in data.get("models", {}):
                print("%s: .map uses unknown model %s" % (n, u))
                bad += 1
        print("%s: %d models, %d txd, %d model names used" % (n, len(data.get("models", {})), len(txd_names), len(used)))
    print("OK" if not bad else "%d problem(s)" % bad)
    return bad


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("import", "meta", "check"):
        print(__doc__)
        return 1
    cmd = {"import": cmd_import, "meta": cmd_meta, "check": cmd_check}[sys.argv[1]]
    return cmd(sys.argv[2:]) or 0


if __name__ == "__main__":
    sys.exit(main())
