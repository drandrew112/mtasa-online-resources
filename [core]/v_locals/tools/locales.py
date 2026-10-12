"""v_locals phase 2 tool: collect, classify and build the UI strings (DESIGN.md 8 / 2. fázis).

    python tools/locales.py scan      inventory + reports        -> tools/out/
    python tools/locales.py build     catalogs from the inventory -> locales/, meta.xml, keys.lock.json
    python tools/locales.py lint      catalog checks + texts still hard-coded in sinks (phase 3)
    python tools/locales.py all       scan + build

Inputs (hand edited, tools/):
    config.json      exclusions, sinks, field names, technical patterns
    decisions.json   per item / per text overrides, common.* merges
    hu_to_en.json    English source text of the Hungarian strings found in the code
Output (generated, tools/out/): inventory.json, inventory.csv, report_*.md
keys.lock.json (tools/): namespace|text -> key; once a key is given it never changes.
"""
import csv
import hashlib
import json
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALS = os.path.dirname(HERE)                                  # [core]/v_locals
RESOURCES = os.path.dirname(os.path.dirname(LOCALS))            # .../resources
OUT = os.path.join(HERE, "out")


def load_json(name, default):
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


CFG = load_json("config.json", {})

# --------------------------------------------------------------------------
# Lua lexer
# --------------------------------------------------------------------------
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
            "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
OPS = ["...", "..", "==", "~=", "<=", ">=", "::"] + list("+-*/%^#<>=(){}[];:,.")
ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
       "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class Tok:
    __slots__ = ("kind", "value", "line", "raw")

    def __init__(self, kind, value, line, raw=None):
        self.kind, self.value, self.line, self.raw = kind, value, line, raw

    def __repr__(self):
        return "%s:%r@%d" % (self.kind, self.value, self.line)


def lex(src):
    toks, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:i + 40])
            if m:
                close = "]" + m.group(1) + "]"
                e = src.find(close, i)
                e = n if e < 0 else e + len(close)
                line += src.count("\n", i, e)
                i = e
            else:
                e = src.find("\n", i)
                i = n if e < 0 else e
            continue
        if c == "[":
            m = re.match(r"\[(=*)\[", src[i:i + 40])
            if m:
                close = "]" + m.group(1) + "]"
                start = i + len(m.group(0))
                e = src.find(close, start)
                e = n if e < 0 else e
                text = src[start:e]
                if text.startswith("\n"):
                    text = text[1:]
                toks.append(Tok("str", text, line, "long"))
                line += src.count("\n", i, e)
                i = e + len(close)
                continue
        if c in "\"'":
            j, buf, start_line = i + 1, bytearray(), line
            while j < n and src[j] != c:
                ch = src[j]
                if ch == "\\" and j + 1 < n:
                    nx = src[j + 1]
                    if nx.isdigit():
                        # "\226\130\172" are the UTF-8 bytes of €: collect bytes, decode at the end
                        m = re.match(r"\d{1,3}", src[j + 1:j + 4])
                        buf.append(int(m.group(0)) & 0xFF)
                        j += 1 + len(m.group(0))
                        continue
                    buf += ESC.get(nx, nx).encode("utf-8")
                    if nx == "\n":
                        line += 1
                    j += 2
                    continue
                if ch == "\n":
                    break
                buf += ch.encode("utf-8")
                j += 1
            toks.append(Tok("str", buf.decode("utf-8", errors="replace"), start_line, "short"))
            i = j + 1
            continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
            w = m.group(0)
            toks.append(Tok("kw" if w in KEYWORDS else "name", w, line))
            i += len(w)
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = re.match(r"0[xX][0-9a-fA-F]+|\d*\.?\d+(?:[eE][+-]?\d+)?", src[i:])
            toks.append(Tok("num", m.group(0), line))
            i += len(m.group(0))
            continue
        for op in OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, line))
                i += len(op)
                break
        else:
            i += 1
    return toks


OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}


def match_pairs(toks):
    pair, stack = {}, []
    for i, t in enumerate(toks):
        if t.kind == "op" and t.value in OPEN:
            stack.append(i)
        elif t.kind == "op" and t.value in CLOSE:
            if stack and toks[stack[-1]].value == CLOSE[t.value]:
                j = stack.pop()
                pair[i], pair[j] = j, i
    return pair


# --------------------------------------------------------------------------
# File analysis
# --------------------------------------------------------------------------
def is_op(t, v=None):
    return t is not None and t.kind == "op" and (v is None or t.value == v)


class LuaFile:
    def __init__(self, rel, src):
        self.rel, self.src = rel, src
        self.toks = lex(src)
        self.pair = match_pairs(self.toks)
        self.scope_of = [None] * len(self.toks)     # token index -> function scope id
        self.scopes = []                            # {name, kind, start, parent, test, render}
        self._scopes()

    def tok(self, i):
        return self.toks[i] if 0 <= i < len(self.toks) else None

    # ---------------- operand / expression spans ----------------
    def operand_start(self, i):
        """index of the first token of the operand that ends at token i"""
        toks = self.toks
        while True:
            t = toks[i]
            if is_op(t) and t.value in (")", "]") and i in self.pair:
                j = self.pair[i]
                p = self.tok(j - 1)
                # f(x) / t[k] / f(a)(b): keep walking to the callee
                if p is not None and (p.kind in ("name", "str") or (is_op(p) and p.value in (")", "]"))):
                    i = j - 1
                    continue
                return j
            p = self.tok(i - 1)
            if t.kind == "name" and is_op(p) and p.value in (".", ":"):
                i -= 2
                continue
            return i

    def operand_end(self, i):
        """index of the last token of the operand that starts at token i"""
        toks = self.toks
        t = toks[i]
        if is_op(t) and t.value in OPEN and i in self.pair:
            i = self.pair[i]
        elif t.kind == "kw" and t.value == "not":
            return self.operand_end(i + 1)
        elif is_op(t, "#") or is_op(t, "-"):
            return self.operand_end(i + 1)
        while True:
            nx = self.tok(i + 1)
            if nx is None:
                return i
            if is_op(nx) and nx.value in (".", ":") and self.tok(i + 2) is not None and self.tok(i + 2).kind == "name":
                i += 2
                continue
            if is_op(nx) and nx.value in ("(", "[") and (i + 1) in self.pair and toks[i].kind in ("name", "str", "op"):
                if toks[i].kind == "op" and toks[i].value not in (")", "]"):
                    return i
                i = self.pair[i + 1]
                continue
            if nx.kind == "str" and toks[i].kind == "name":       # f"str" call
                i += 1
                continue
            return i

    def concat_span(self, i):
        """[s, e] of the `a .. b .. c` chain the string at i belongs to, and operand spans"""
        s = e = i
        ops = [(i, i)]
        while is_op(self.tok(s - 1), ".."):
            ps = self.operand_start(s - 2)
            ops.insert(0, (ps, s - 2))
            s = ps
        while is_op(self.tok(e + 1), ".."):
            pe = self.operand_end(e + 2)
            ops.append((e + 2, pe))
            e = pe
        return s, e, ops

    BINOPS = {"..", "==", "~=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%", "^"}

    def expr_span(self, s, e):
        """grow [s, e] over and / or / not and binary operators: `cond and "A" or "B"`"""
        while True:
            p = self.tok(s - 1)
            if p is not None and p.kind == "kw" and p.value == "not":
                s -= 1
                continue
            if p is not None and ((p.kind == "kw" and p.value in ("and", "or")) or (is_op(p) and p.value in self.BINOPS)):
                if s - 2 < 0:
                    break
                s = self.operand_start(s - 2)
                continue
            break
        while True:
            n = self.tok(e + 1)
            if n is not None and ((n.kind == "kw" and n.value in ("and", "or")) or (is_op(n) and n.value in self.BINOPS)):
                if self.tok(e + 2) is None:
                    break
                e = self.operand_end(e + 2)
                continue
            break
        return s, e

    def text_of(self, s, e):
        return " ".join(t.value if t.kind != "str" else repr(t.value) for t in self.toks[s:e + 1])

    # ---------------- function scopes ----------------
    def _scopes(self):
        toks = self.toks
        stack = []      # entries: ("fn", scope_id) | ("blk", None) | ("rep", None)
        cur = None
        for i, t in enumerate(toks):
            if t.kind == "kw":
                if t.value == "function":
                    name, anon_ctx = self._fn_name(i)
                    sid = len(self.scopes)
                    self.scopes.append({"name": name, "start": i, "parent": cur, "ctx": anon_ctx,
                                        "line": t.line, "calls": set()})
                    stack.append(("fn", sid))
                    cur = sid
                elif t.value in ("if", "do"):
                    # `while x do` / `for ... do` share one block with their `do`
                    stack.append(("blk", None))
                elif t.value == "repeat":
                    stack.append(("rep", None))
                elif t.value == "until":
                    if stack and stack[-1][0] == "rep":
                        stack.pop()
                elif t.value == "end":
                    if stack:
                        kind, sid = stack.pop()
                        if kind == "fn":
                            cur = self.scopes[sid]["parent"]
            self.scope_of[i] = cur
            if t.kind == "name" and is_op(self.tok(i + 1), "(") and cur is not None:
                self.scopes[cur]["calls"].add(t.value)

    def _fn_name(self, i):
        """(name, context) of the function keyword at i; context = enclosing call info for anonymous ones"""
        nx = self.tok(i + 1)
        if nx is not None and nx.kind == "name":
            j, parts = i + 1, [nx.value]
            while is_op(self.tok(j + 1)) and self.tok(j + 1).value in (".", ":") and self.tok(j + 2) and self.tok(j + 2).kind == "name":
                parts.append(self.tok(j + 2).value)
                j += 2
            return parts[-1], None
        p = self.tok(i - 1)
        if is_op(p, "="):
            q = self.tok(i - 2)
            if q is not None and q.kind == "name":
                return q.value, None
        call = self.enclosing_call(i)
        return None, call

    # ---------------- contexts ----------------
    def enclosing_open(self, s):
        """index of the nearest unmatched opener before token s, and the argument index"""
        depth, argn, j = 0, 1, s - 1
        toks = self.toks
        while j >= 0:
            t = toks[j]
            if is_op(t):
                if t.value in CLOSE and j in self.pair:
                    j = self.pair[j] - 1
                    continue
                if t.value in OPEN:
                    return j, argn
                if t.value in (",", ";"):
                    argn += 1
            elif t.kind == "kw" and t.value in ("function", "then", "do", "else", "end", "return", "local"):
                if t.value != "function":
                    return None, None
            j -= 1
        return None, None

    def callee(self, open_idx):
        """('name', full) of the call whose '(' is at open_idx"""
        p = self.tok(open_idx - 1)
        if p is None or p.kind != "name":
            return None, None
        parts, j = [p.value], open_idx - 1
        while is_op(self.tok(j - 1)) and self.tok(j - 1).value in (".", ":") and self.tok(j - 2) and self.tok(j - 2).kind == "name":
            parts.insert(0, self.tok(j - 2).value)
            j -= 2
        return p.value, ".".join(parts)

    def enclosing_call(self, s):
        o, argn = self.enclosing_open(s)
        if o is None or self.toks[o].value != "(":
            return None
        name, full = self.callee(o)
        if not name:
            return None
        return {"name": name, "full": full, "arg": argn, "open": o}

    def call_args(self, open_idx):
        """list of (s, e) spans of the arguments of the call opened at open_idx"""
        close = self.pair.get(open_idx)
        if close is None:
            return []
        spans, s, j = [], open_idx + 1, open_idx + 1
        while j < close:
            t = self.toks[j]
            if is_op(t) and t.value in OPEN and j in self.pair:
                j = self.pair[j] + 1
                continue
            if is_op(t, ","):
                spans.append((s, j - 1))
                s = j + 1
            j += 1
        if s <= close - 1:
            spans.append((s, close - 1))
        return spans

    def context(self, s, e):
        """describe where the expression [s, e] is used"""
        toks = self.toks
        before, after = self.tok(s - 1), self.tok(e + 1)
        ctx = {"kind": "other"}
        if is_op(before) and before.value in ("==", "~=") or is_op(after) and after.value in ("==", "~="):
            ctx = {"kind": "compare"}
            return ctx
        if is_op(before, "[") and is_op(after, "]"):
            # t["x"] (index) or { ["x"] = ... } (table key)
            return {"kind": "index"}
        if before is not None and before.kind == "kw" and before.value == "return":
            return {"kind": "return"}
        if is_op(before, "="):
            lhs = self.tok(s - 2)
            if lhs is not None and lhs.kind == "name":
                o, _ = self.enclosing_open(s - 2)
                if o is not None and toks[o].value == "{":
                    return self._table_ctx(o, field=lhs.value)
                return {"kind": "assign", "var": lhs.value}
            if is_op(lhs, "]") and (s - 2) in self.pair:
                # { [k] = "text" } -> list item of the table; t[k] = "text" -> assign to t
                ob = self.pair[s - 2]
                o, _ = self.enclosing_open(ob)
                if o is not None and toks[o].value == "{" and (is_op(self.tok(ob - 1), "{") or is_op(self.tok(ob - 1), ",") or is_op(self.tok(ob - 1), ";")):
                    c = self._table_ctx(o, field=None)
                    c["keyed"] = True
                    return c
                st = self.operand_start(s - 2)
                q = self.tok(st)
                return {"kind": "assign", "var": q.value if q is not None and q.kind == "name" else None, "indexed": True}
        if before is not None and (is_op(before, ",") or is_op(before, "(") or is_op(before, "{")):
            o, argn = self.enclosing_open(s)
            if o is not None:
                if toks[o].value == "(":
                    name, full = self.callee(o)
                    if name:
                        return {"kind": "call", "name": name, "full": full, "arg": argn, "open": o}
                    # ( "x" ):format(...) handled by the caller
                    return {"kind": "paren", "open": o}
                if toks[o].value == "{":
                    return self._table_ctx(o, field=None)
        if before is not None and before.kind == "name" and before.value != "return":
            # f "str" call syntax
            if self.tok(s - 1).kind == "name":
                return {"kind": "call", "name": before.value, "full": before.value, "arg": 1, "open": None}
        if is_op(before, ","):
            # `return false, "reason"` / `local a, b = x, "y"`
            j = s - 1
            while j >= 0:
                t = toks[j]
                if is_op(t) and t.value in CLOSE and j in self.pair:
                    j = self.pair[j] - 1
                    continue
                if is_op(t) and t.value in OPEN:
                    break
                if t.kind == "kw":
                    if t.value == "return":
                        return {"kind": "return"}
                    if t.value not in ("and", "or", "not", "nil", "true", "false", "function"):
                        break
                if is_op(t, "="):
                    lhs = self.tok(j - 1)
                    return {"kind": "assign", "var": lhs.value if lhs is not None and lhs.kind == "name" else None, "multi": True}
                j -= 1
        return ctx

    def _table_ctx(self, o, field):
        """table constructor at o: own field name + what the table itself is assigned / passed to"""
        owner = None
        p = self.tok(o - 1)
        if is_op(p, "="):
            q = self.tok(o - 2)
            if q is not None and q.kind == "name":
                owner = q.value
        elif p is not None and p.kind == "name":
            owner = p.value            # f{ ... }
        else:
            c = self.enclosing_call(o)
            if c:
                owner = c["name"]
            else:
                oo, _ = self.enclosing_open(o)
                if oo is not None and self.toks[oo].value == "{":
                    q = self.tok(o - 2)
                    if is_op(self.tok(o - 1), "=") and q is not None and q.kind == "name":
                        owner = q.value
                    else:
                        # element of a list: use the list's own owner
                        owner = self._table_ctx(oo, None).get("owner")
        return {"kind": "field" if field else "item", "field": field, "owner": owner}


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------
LETTER = re.compile(r"[A-Za-zÀ-ÿĀ-žА-я]")
HU_CHARS = re.compile(r"[őűŐŰ]|[áéíóöúü].*[áéíóöúü]|\b(és|nincs|vagy|játékos|jatekos|szint|szintet|törölve|"
                      r"Használat|jogod|ilyen|szerelvény|Kaptal|Adtal|Elérted|Ehhez|nem|meg|már|Nincs|"
                      r"mentve|Osztott|Erősség|Ismeretlen|Állapot|bejegyzés|minden|Vasúti|napló|Játékidő|"
                      r"perc|óra|nap|aréna|háború|leáll|újraindul|Kérlek|Sikeres|Hiba|kocsi|vonat)\b")


def compile_list(key):
    return [re.compile(p) for p in CFG.get(key, [])]


TECH = None


def technical(s):
    t = s.strip()
    if not t or not LETTER.search(t):
        return True
    if " " in t:
        # a sentence with printf codes ("%s side paralysed") is text formatted later,
        # not a Lua pattern ("^%s+", "(%d%d%d)" have no spaces)
        t = FMT_RX.sub("x", t)
    for rx in TECH:
        if rx.search(t):
            return True
    return False


def texty(s, strong):
    """user-visible looking text. strong = the string sits in a known UI sink"""
    t = s.strip()
    if technical(t):
        return False
    # one all-caps word (TAXI, BEACH, PEA): a code unless it sits in a UI sink
    if not strong and re.fullmatch(r"[A-Z0-9]+", t):
        return False
    if " " in t or t[0].isupper() or re.search(r"[.!?:…]$", t) or not t.isascii():
        return True
    # single lower-case word: only in a strong sink, and never an identifier
    if strong and re.fullmatch(r"[a-z][a-z'\-]*", t) and "_" not in t:
        return True
    return False


HU_ACCENT = re.compile(r"[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]")
HU_WORDS = re.compile(r"\b(Kaptal|Adtal|kocsi|vonat|TELEFON|szakasz|engedély|jatekosnak|tol|Szint|Rendszer|vagy|nincs|Nincs)\b")


def is_hungarian(s):
    # colour codes and placeholders glue words together: "#ffffffKaptal", "{prefix}Elérted"
    t = re.sub(r"#[0-9a-fA-F]{6}", " ", s)
    t = re.sub(r"\{[^}]*\}", " ", t)
    return bool(HU_ACCENT.search(t) or HU_WORDS.search(t) or HU_CHARS.search(t))


def placeholder_name(expr_toks):
    """param name for a non-literal operand"""
    names = [t.value for t in expr_toks if t.kind == "name"]
    skip = {"tostring", "tonumber", "math", "floor", "string", "format", "upper", "lower", "getPlayerName",
            "getElementData", "ceil", "abs", "self", "exports", "utf8", "sub", "rep", "concat", "table", "L"}
    if len(expr_toks) == 1 and expr_toks[0].kind == "name":
        return expr_toks[0].value
    if len(expr_toks) == 1 and expr_toks[0].kind == "num":
        return None
    if names and names[0] == "getPlayerName":
        return "player"
    meaningful = [n for n in names if n not in skip]
    if meaningful:
        return meaningful[-1]
    return "value"


def snake(name):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()
    s = re.sub(r"[^a-z0-9_]", "_", s).strip("_")
    return s or "value"


FMT_RX = re.compile(r"%([-0-9.]*)([sdifgqx%])")


def format_to_template(fmt, arg_names):
    """'%d players, %.1f km, %s' + names -> '{a|int} players, {b|1f} km, {c}' (None if unsupported)"""
    out, k, pos = [], 0, 0
    for m in FMT_RX.finditer(fmt):
        out.append(escape_braces(fmt[pos:m.start()]))
        pos = m.end()
        flags, conv = m.group(1), m.group(2)
        if conv == "%":
            out.append("%")
            continue
        if k >= len(arg_names):
            return None
        name = arg_names[k]
        k += 1
        if conv == "s" and flags == "":
            out.append("{%s}" % name)
        elif conv in "di" and flags == "":
            out.append("{%s|int}" % name)
        elif conv == "f" and re.fullmatch(r"\.\d", flags):
            out.append("{%s|%sf}" % (name, flags[1]))
        else:
            return None            # %02d, %5.1f, %q ... -> review by hand
    out.append(escape_braces(fmt[pos:]))
    return "".join(out)


def escape_braces(s):
    return s.replace("{", "{{").replace("}", "}}")


def unique_names(names):
    seen, out = Counter(), []
    for n in names:
        n = snake(n or "value")
        seen[n] += 1
        out.append(n if seen[n] == 1 else "%s%d" % (n, seen[n]))
    return out


# --------------------------------------------------------------------------
# Scanner
# --------------------------------------------------------------------------
def resource_of(rel):
    parts = rel.replace("\\", "/").split("/")
    if parts[0].startswith("["):
        return parts[1], "/".join(parts[2:])
    return parts[0], "/".join(parts[1:])


def namespace_of(res):
    return re.sub(r"[^a-z0-9_]", "_", res.lower())


def excluded_file(res, inner):
    ex = CFG["exclude"]
    if res in ex["resources"]:
        return ex["resources"][res]
    for pat, why in ex["files"].items():
        r, p = pat.split("/", 1)
        if r == res and re.fullmatch(p.replace(".", r"\.").replace("*", ".*"), inner):
            return why
    for pat, why in ex["paths"].items():
        if re.search(pat, inner):
            return why
    return None


class Scanner:
    def __init__(self):
        self.items = []
        self.excluded = Counter()
        self.excluded_why = {}
        self.logic = []
        self.render = []
        self.utf8 = []
        self.gta = []
        self.data = []
        self.sinks = {k: {int(a) for a in v} for k, v in CFG["sink_calls"].items()}
        self.helper_rx = re.compile(CFG["helper_call_regex"])
        self.debug_calls = set(CFG["debug_calls"])
        self.tech_calls = set(CFG["technical_calls"])
        self.fields = set(CFG["text_fields"])
        self.weak_fields = set(CFG["weak_text_fields"])
        self.list_owners = set(CFG["text_list_owners"])
        self.vars = set(CFG["text_vars"])
        self.event_rx = re.compile(CFG["notify_event_regex"])
        self.test_cmd_rx = re.compile(CFG["test_command_regex"])
        self.ui_parts = set(CFG["ui_name_parts"])
        self.tech_parts = set(CFG["tech_name_parts"])

    @staticmethod
    def sentence(text):
        """reads like UI text: 'Bring the patient here.', 'Front Bumper', '{player} is too far away.'"""
        t = text.strip()
        if not t or re.fullmatch(r"[A-Z0-9 ]+", t) and " " not in t:
            return False
        first = t[0]
        return (first.isupper() or first in "{[(\"'#€" or not first.isascii()) and (" " in t or re.search(r"[.!?…]$", t) is not None)

    def ui_name(self, name):
        """camelCase / snake_case name made of UI words: adminAlert, commandFeedback, drawSection"""
        if not name:
            return False
        parts = {p.lower() for p in re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])", name)}
        return bool(parts & self.ui_parts) and not (parts & self.tech_parts)

    # ---------------- walk ----------------
    def run(self):
        for dp, dns, fns in os.walk(RESOURCES):
            dns[:] = [d for d in dns if d not in ("node_modules", ".git")]
            for fn in fns:
                if not fn.endswith(".lua"):
                    continue
                path = os.path.join(dp, fn)
                rel = os.path.relpath(path, RESOURCES).replace("\\", "/")
                res, inner = resource_of(rel)
                why = excluded_file(res, inner)
                if why:
                    self.excluded[(res, why)] += 1
                    continue
                if os.path.getsize(path) > CFG["max_file_bytes"]:
                    self.excluded[(res, "generated data (file too large)")] += 1
                    continue
                with open(path, encoding="utf-8", errors="replace") as f:
                    src = f.read()
                self.scan_file(res, rel, inner, src)
        self.scan_data()

    def scan_file(self, res, rel, inner, src):
        lf = LuaFile(rel, src)
        self.mark_scopes(lf)
        seen = set()
        toks = lf.toks
        for i, t in enumerate(toks):
            if t.kind != "str" or i in seen:
                continue
            s, e, ops = lf.concat_span(i)
            for a, b in ops:
                if a == b and toks[a].kind == "str":
                    seen.add(a)
            self.handle_expr(lf, res, rel, inner, s, e, ops)
        self.measure_sites(lf, res, rel)
        self.utf8_sites(lf, res, rel, src)
        self.gta_sites(lf, res, rel)

    # ---------------- scopes: test commands / render functions ----------------
    def mark_scopes(self, lf):
        render_names = set()
        toks = lf.toks
        for i, t in enumerate(toks):
            if t.kind == "name" and t.value in ("addEventHandler", "addCommandHandler") and is_op(lf.tok(i + 1), "("):
                args = lf.call_args(i + 1)
                if not args:
                    continue
                first = toks[args[0][0]]
                if t.value == "addEventHandler" and first.kind == "str" and first.value in ("onClientRender", "onClientPreRender", "onClientHUDRender"):
                    if len(args) >= 3:
                        a = toks[args[2][0]]
                        if a.kind == "name":
                            render_names.add(a.value)
        for sc in lf.scopes:
            ctx = sc["ctx"]
            sc["render"] = False
            sc["test"] = False
            if ctx and ctx["name"] == "addEventHandler":
                args = lf.call_args(ctx["open"])
                if args and toks[args[0][0]].kind == "str" and toks[args[0][0]].value in ("onClientRender", "onClientPreRender", "onClientHUDRender"):
                    sc["render"] = True
            if ctx and ctx["name"] == "addCommandHandler":
                args = lf.call_args(ctx["open"])
                if args and toks[args[0][0]].kind == "str" and self.test_cmd_rx.search(toks[args[0][0]].value):
                    sc["test"] = True
            if sc["name"] in render_names:
                sc["render"] = True
        # functions called from render functions are render too (by name, file-local)
        by_name = defaultdict(list)
        for sid, sc in enumerate(lf.scopes):
            if sc["name"]:
                by_name[sc["name"]].append(sid)
        changed = True
        while changed:
            changed = False
            for sc in lf.scopes:
                if sc["render"]:
                    for c in sc["calls"]:
                        for sid in by_name.get(c, []):
                            if not lf.scopes[sid]["render"]:
                                lf.scopes[sid]["render"] = True
                                changed = True
        # inherit to nested scopes
        for sid, sc in enumerate(lf.scopes):
            p = sc["parent"]
            while p is not None:
                if lf.scopes[p]["test"]:
                    sc["test"] = True
                if lf.scopes[p]["render"]:
                    sc["render"] = True
                p = lf.scopes[p]["parent"]

    def in_test(self, lf, i):
        sid = lf.scope_of[i]
        return sid is not None and lf.scopes[sid]["test"]

    def in_render(self, lf, i):
        sid = lf.scope_of[i]
        return sid is not None and lf.scopes[sid]["render"]

    # ---------------- one expression ----------------
    def handle_expr(self, lf, res, rel, inner, s, e, ops):
        toks = lf.toks
        lits = [toks[a].value for a, b in ops if a == b and toks[a].kind == "str"]
        dynamic = any(not (a == b and toks[a].kind == "str") for a, b in ops)

        # ("fmt"):format(args) / string.format("fmt", args)
        fmt_args, outer_s, outer_e = None, s, e
        if not dynamic and len(ops) == 1:
            if is_op(lf.tok(s - 1), "(") and is_op(lf.tok(e + 1), ")") and is_op(lf.tok(e + 2), ":") \
                    and lf.tok(e + 3) and lf.tok(e + 3).value == "format" and is_op(lf.tok(e + 4), "("):
                fmt_args = lf.call_args(e + 4)
                outer_s, outer_e = s - 1, lf.pair.get(e + 4, e + 4)
            elif is_op(lf.tok(e + 1), ":") and lf.tok(e + 2) and lf.tok(e + 2).value == "format" and is_op(lf.tok(e + 3), "("):
                fmt_args = lf.call_args(e + 3)                       # "fmt":format() is invalid Lua, kept for safety
                outer_e = lf.pair.get(e + 3, e + 3)
            else:
                c = lf.context(s, e)
                if c["kind"] == "call" and c["full"] in ("string.format",) and c["arg"] == 1:
                    spans = lf.call_args(c["open"])
                    fmt_args = spans[1:]
                    outer_s, outer_e = c["open"] - 3, lf.pair.get(c["open"], e)

        text, params, template_ok = None, [], True
        if fmt_args is not None:
            names = unique_names([placeholder_name(toks[a:b + 1]) for a, b in fmt_args])
            text = format_to_template(lits[0], names)
            params = [(n, lf.text_of(a, b)) for n, (a, b) in zip(names, fmt_args)]
            if text is None:
                text, template_ok = lits[0], False
        elif dynamic:
            parts, raw_names, exprs = [], [], []
            for a, b in ops:
                if a == b and toks[a].kind == "str":
                    parts.append(("lit", toks[a].value))
                else:
                    raw_names.append(placeholder_name(toks[a:b + 1]))
                    exprs.append(lf.text_of(a, b))
                    parts.append(("par", None))
            names = unique_names(raw_names)
            k, buf = 0, []
            for kind, v in parts:
                if kind == "lit":
                    buf.append(escape_braces(v))
                else:
                    buf.append("{%s}" % names[k])
                    k += 1
            text = "".join(buf)
            params = list(zip(names, exprs))
        else:
            text = "".join(lits)

        literal_text = "".join(lits)
        if not literal_text.strip():
            return
        ctx = lf.context(outer_s, outer_e)
        if ctx["kind"] not in ("compare", "index"):
            xs, xe = outer_s, outer_e
            for _ in range(12):
                ns_, ne_ = lf.expr_span(xs, xe)
                if (ns_, ne_) != (xs, xe):
                    xs, xe = ns_, ne_
                    ctx = lf.context(xs, xe)
                    if ctx["kind"] == "compare":
                        ctx = {"kind": "other"}  # `a == b and "x"`: the text is a value, not compared
                        break
                if ctx["kind"] == "paren" and ctx.get("open") is not None and ctx["open"] in lf.pair:
                    # grouping parentheses: ( cond and "A" or "B" ) -> the context of the group
                    xs, xe = ctx["open"], lf.pair[ctx["open"]]
                    xe = lf.operand_end(xs)
                    ctx = lf.context(xs, xe)
                    continue
                break
        line = toks[s].line

        if self.in_test(lf, s):
            self.excluded[(res, "test command (not stored, D14)")] += 1
            return

        sink, strong = self.sink_of(lf, ctx, outer_s)
        if sink == "debug" or sink == "technical":
            return
        if ctx["kind"] in ("compare", "index"):
            if texty(literal_text, False):
                self.logic.append({"res": res, "file": rel, "line": line, "text": literal_text, "kind": ctx["kind"]})
            return

        # exclusions by field (D5 etc.)
        for rule in CFG["exclude"]["fields"]:
            if rule["resource"] == res and (rule.get("file") in (None, inner)) and ctx.get("field") in rule["fields"] \
                    and (rule.get("owner") is None or ctx.get("owner") == rule["owner"] or rule.get("owner") == "*"):
                self.excluded[(res, rule["why"])] += 1
                return

        check = FMT_RX.sub(" ", literal_text) if fmt_args is not None else literal_text
        if sink and (sink.startswith("list:") or sink.startswith("helper:") or sink.startswith("event:")) and re.fullmatch(r"[a-z][a-z0-9'\-]*", check.strip()):
            return              # value / command id passed next to the label: item("Save", "save")
        is_text = texty(check, strong)
        literal_text = check if fmt_args is not None else literal_text
        if not is_text:
            if sink and strong and LETTER.search(literal_text) and not technical(literal_text):
                status = "review"
            else:
                return
        else:
            status = "translate" if strong else "review"
            if not strong and ctx["kind"] in ("item", "field", "return", "assign") and self.sentence(text):
                status = "translate"
        if ctx["kind"] == "return" and not strong and status == "review" and not self.sentence(text):
            return              # lower-case internal error / code returned by an API
        if fmt_args is not None and not template_ok:
            status = "review"
        if sink is None and status == "translate":
            status = "review"

        hu = is_hungarian(literal_text)
        avi = res in CFG["confirm_resources"]
        self.items.append({
            "res": res, "ns": namespace_of(res), "file": rel, "inner": inner, "line": line,
            "text": text, "template": bool(params), "params": params, "template_ok": template_ok,
            "sink": sink or ctx["kind"], "ctx": ctx.get("name") or ctx.get("field") or ctx.get("var") or ctx.get("owner"),
            "field": ctx.get("field"), "owner": ctx.get("owner"),
            "status": status, "hu": hu, "confirm": avi,
            "render": self.in_render(lf, s), "side": side_of(inner, res),
        })

    def sink_of(self, lf, ctx, s):
        """(sink name | 'debug' | 'technical' | None, strong)"""
        k = ctx["kind"]
        if k == "call":
            name, full, arg = ctx["name"], ctx["full"], ctx["arg"]
            if name in self.debug_calls or full in self.debug_calls:
                return "debug", False
            if name in self.sinks:
                return (name, True) if (0 in self.sinks[name] or arg in self.sinks[name]) else ("technical", False)
            if name in ("triggerClientEvent", "triggerEvent", "triggerServerEvent", "triggerLatentClientEvent"):
                args = lf.call_args(ctx["open"]) if ctx["open"] is not None else []
                for a, b in args[:2]:
                    t = lf.toks[a]
                    if t.kind == "str" and self.event_rx.search(t.value):
                        evpos = [x for x in args[:2] if lf.toks[x[0]].kind == "str"]
                        evarg = args.index(evpos[0]) + 1 if evpos else 2
                        if arg > evarg + 1 or (name == "triggerServerEvent" and arg > evarg + 1):
                            return "event:" + t.value, True
                return "technical", False
            if name in self.tech_calls or full in self.tech_calls:
                return "technical", False
            if self.helper_rx.search(name) or self.ui_name(name):
                return "helper:" + name, True
            return None, False
        if k == "field":
            f = ctx["field"]
            if f in self.fields:
                return "field:" + f, True
            if f in self.weak_fields:
                return "field:" + f, False
            return None, False
        if k == "item":
            owner = ctx.get("owner") or ""
            if owner in self.list_owners or re.search(CFG["text_owner_regex"], owner) or self.ui_name(owner):
                return "list:" + owner, True
            return None, False
        if k == "assign":
            v = ctx.get("var") or ""
            if ctx.get("indexed") and (v in self.list_owners or re.search(CFG["text_owner_regex"], v)):
                return "list:" + v, True
            if v in self.vars or re.search(CFG["text_var_regex"], v or ""):
                return "var:" + v, True
            return None, False
        if k == "return":
            return "return", False
        return None, False

    # ---------------- side reports ----------------
    def measure_sites(self, lf, res, rel):
        for i, t in enumerate(lf.toks):
            if t.kind == "name" and t.value in ("dxGetTextWidth", "dxGetTextSize") and is_op(lf.tok(i + 1), "("):
                sid = lf.scope_of[i]
                self.render.append({"res": res, "file": rel, "line": t.line, "render": self.in_render(lf, i),
                                    "fn": lf.scopes[sid]["name"] if sid is not None else None})

    def utf8_sites(self, lf, res, rel, src):
        if "dxDrawText" not in src:
            return
        lines = src.split("\n")
        for no, ln in enumerate(lines, 1):
            code = ln.split("--")[0]
            hits = []
            if re.search(r":upper\(\)|string\.upper\(|:lower\(\)|string\.lower\(", code):
                hits.append("upper/lower")
            if re.search(r"\b(str|text|label|name|title|msg|line|word|desc|txt|s|cur|shown)\s*:sub\(|string\.sub\((str|text|label|name|title|msg|line|word|desc|txt|s)\b", code):
                hits.append("sub")
            if re.search(r"#(str|text|label|name|title|msg|line|word|desc|txt|shown|input_text)\b", code):
                hits.append("# length")
            if hits:
                self.utf8.append({"res": res, "file": rel, "line": no, "what": ", ".join(hits), "code": ln.strip()[:140]})

    def gta_sites(self, lf, res, rel):
        fonts = set(CFG["gta_fonts"])
        toks = lf.toks
        for i, t in enumerate(toks):
            if t.kind == "name" and t.value == "dxDrawText" and is_op(lf.tok(i + 1), "("):
                args = lf.call_args(i + 1)
                font = None
                for a, b in args[6:10]:
                    if a == b and toks[a].kind == "str" and toks[a].value in fonts:
                        font = toks[a].value
                    elif "logo" in lf.text_of(a, b).lower():
                        font = font or "FONT.logo (pricedown)"
                if font and args:
                    self.gta.append({"res": res, "file": rel, "line": t.line, "font": font,
                                     "text": lf.text_of(*args[0])[:80]})

    # ---------------- data files ----------------
    def scan_data(self):
        for rel_path in CFG["data_review"]:
            path = os.path.join(RESOURCES, rel_path)
            if not os.path.exists(path):
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                continue
            found = []

            def walk(x, key=None):
                if isinstance(x, dict):
                    for k, v in x.items():
                        walk(v, k)
                elif isinstance(x, list):
                    for v in x:
                        walk(v, key)
                elif isinstance(x, str) and key in ("name", "title", "label", "description", "desc", "text") and texty(x, False):
                    found.append((key, x))
            walk(data)
            self.data.append({"file": rel_path, "count": len(found), "sample": found[:6]})


def side_of(inner, res):
    p = inner.lower()
    if re.search(r"(^|/)(client|c_)|_c\.lua$|^c[_a-z]*\.lua$|client", p):
        return "client"
    if re.search(r"(^|/)(server|s_)|_s\.lua$|^s[_a-z]*\.lua$|server", p):
        return "server"
    return "shared/unknown"


# --------------------------------------------------------------------------
# Keys
# --------------------------------------------------------------------------
def slug(text, maxwords=6):
    t = re.sub(r"\{[^}]*\}", " ", text)
    t = re.sub(r"#[0-9a-fA-F]{6}", " ", t)
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()
    words = re.findall(r"[a-z0-9]+", t.lower())
    words = [w for w in words if w not in ("the", "a", "an")] or ["text"]
    return "_".join(words[:maxwords])[:48].strip("_") or "text"


def area_of(inner):
    stem = os.path.splitext(os.path.basename(inner))[0].lower()
    stem = re.sub(r"^(c|s|cl|sv)_", "", stem)
    stem = re.sub(r"_(c|s)$", "", stem)
    stem = re.sub(r"[^a-z0-9_]", "_", stem)
    if stem in ("client", "server", "main", "shared", "init", "core", "exports", "util", "utils"):
        d = os.path.basename(os.path.dirname(inner)).lower()
        d = re.sub(r"[^a-z0-9_]", "_", d)
        if d and d not in ("client", "server", "shared", ""):
            stem = d if stem in ("client", "server", "shared") else d + "_" + stem
    return stem or "main"


def norm(text):
    return re.sub(r"\s+", " ", text.strip())


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
def cmd_scan():
    global TECH
    TECH = compile_list("technical_patterns")
    sc = Scanner()
    sc.run()
    dec = load_json("decisions.json", {})
    item_over = dec.get("items", {})
    text_over = dec.get("texts", {})

    rules = []
    for r in dec.get("rules", []):
        rules.append({k: (re.compile(v) if k in ("file", "sink", "text", "owner", "ctx", "res") else v) for k, v in r.items()})

    def rule_status(it):
        for r in rules:
            ok = True
            for k in ("res", "file", "sink", "text", "owner", "ctx"):
                if k in r and not r[k].search(str(it.get(k) or "")):
                    ok = False
                    break
            if ok and "from" in r and it["status"] not in r["from"]:
                ok = False
            if ok:
                return r["status"]
        return None

    occ = Counter()
    for it in sc.items:
        base = "%s\0%s" % (it["file"], it["text"])
        occ[base] += 1
        it["id"] = hashlib.sha1(("%s\0%d" % (base, occ[base])).encode()).hexdigest()[:10]
        ov = item_over.get(it["id"]) or text_over.get(it["text"]) or rule_status(it)
        if ov:
            it["status"] = ov
            it["decided"] = True
        if it["confirm"] and it["status"] == "translate" and not it.get("decided"):
            it["status"] = "review"

    os.makedirs(OUT, exist_ok=True)
    sc.items.sort(key=lambda x: (x["res"], x["file"], x["line"]))
    save_json(os.path.join(OUT, "inventory.json"), sc.items)
    with open(os.path.join(OUT, "inventory.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "status", "resource", "file", "line", "sink", "hu", "render", "text"])
        for it in sc.items:
            w.writerow([it["id"], it["status"], it["res"], it["file"], it["line"], it["sink"], int(it["hu"]), int(it["render"]), it["text"]])
    write_reports(sc)
    st = Counter(it["status"] for it in sc.items)
    print("items: %d (translate %d, review %d, ignore %d), resources %d, HU %d" % (
        len(sc.items), st["translate"], st["review"], st["ignore"],
        len({i["res"] for i in sc.items}), sum(1 for i in sc.items if i["hu"])))
    return sc


def md_table(rows, header):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for r in rows:
        out.append("| " + " | ".join(str(c).replace("|", "\\|").replace("\n", "\\n") for c in r) + " |")
    return "\n".join(out)


def link(rel, line):
    return "[%s:%d](../../../../%s#L%d)" % (rel, line, rel.replace(" ", "%20").replace("[", "%5B").replace("]", "%5D"), line)


def write_report(name, title, body):
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write("# " + title + "\n\n" + body.rstrip() + "\n")


def write_reports(sc):
    items = sc.items
    live = [i for i in items if i["status"] in ("translate", "review")]

    # coverage
    per = defaultdict(Counter)
    for it in items:
        per[it["res"]][it["status"]] += 1
        if it["hu"]:
            per[it["res"]]["hu"] += 1
        if it["template"]:
            per[it["res"]]["dyn"] += 1
    rows = [(r, c["translate"], c["review"], c["ignore"], c["dyn"], c["hu"]) for r, c in sorted(per.items(), key=lambda x: -sum(x[1].values()))]
    tot = Counter()
    for c in per.values():
        tot.update(c)
    body = "Generated by `tools/locales.py scan`. translate = goes into the catalog, review = needs a decision " \
           "(tools/decisions.json), ignore = decided not to translate.\n\n"
    body += "Total: **%d** items — translate %d, review %d, ignore %d, dynamic %d, Hungarian %d.\n\n" % (
        len(items), tot["translate"], tot["review"], tot["ignore"], tot["dyn"], tot["hu"])
    body += md_table(rows, ["resource", "translate", "review", "ignore", "dynamic", "HU"])
    write_report("report_coverage.md", "Coverage per resource", body)

    # review list
    rows = [(i["id"], i["res"], link(i["file"], i["line"]), i["sink"], i["text"][:90] + (" [AVI-CONFIRM]" if i["confirm"] else ""))
            for i in items if i["status"] == "review"]
    write_report("report_review.md", "Items to review",
                 "Set the status in tools/decisions.json: `\"items\": {\"<id>\": \"translate\"|\"ignore\"}` or by text: "
                 "`\"texts\": {\"<text>\": \"ignore\"}`.\n\n" + md_table(rows, ["id", "resource", "where", "sink", "text"]))

    # duplicates
    by_text = defaultdict(list)
    by_fold = defaultdict(set)
    for it in live:
        by_text[norm(it["text"])].append(it)
        by_fold[norm(it["text"]).lower().rstrip(".!:")].add(norm(it["text"]))
    exact = [(t, sorted({i["res"] for i in v}), len(v)) for t, v in by_text.items() if len({i["res"] for i in v}) > 1]
    exact.sort(key=lambda x: (-len(x[1]), x[0]))
    common = [(t, len(r), ", ".join(r)) for t, r, _ in exact if len(r) >= 3]
    body = "## common.* candidates (same text in 3+ resources)\n\nNot merged automatically (DESIGN.md 8, 2. fázis 4.). " \
           "Approve in tools/decisions.json `\"common\": {\"common.cancel\": \"Cancel\"}`.\n\n"
    body += md_table(common, ["text", "resources", "where"]) + "\n\n"
    body += "## Same text in 2 resources\n\n" + md_table([(t, ", ".join(r)) for t, r, _ in exact if len(r) == 2], ["text", "resources"]) + "\n\n"
    variants = [(" / ".join(sorted(v)),) for k, v in by_fold.items() if len(v) > 1]
    body += "## Case / punctuation variants (one key + L.upper candidates)\n\n" + md_table(sorted(variants), ["variants"])
    write_report("report_duplicates.md", "Duplicates", body)

    # hungarian
    rows = [(i["res"], link(i["file"], i["line"]), i["status"], i["text"][:100]) for i in items if i["hu"]]
    write_report("report_hungarian.md", "Hungarian text in the source",
                 "These need an English source text (tools/hu_to_en.json); the Hungarian original goes to locales/hu.seed.\n\n"
                 + md_table(rows, ["resource", "where", "status", "text"]))

    # dynamic
    rows = [(i["res"], link(i["file"], i["line"]), i["status"], i["text"][:90], "; ".join("%s = %s" % (n, e[:40]) for n, e in i["params"]))
            for i in items if i["template"] or not i["template_ok"]]
    write_report("report_dynamic.md", "Dynamic texts (concatenation / format)",
                 "Proposed templates. `template_ok = false` (unsupported format such as %02d) are always review.\n\n"
                 + md_table(rows, ["resource", "where", "status", "template", "params"]))

    # logic
    rows = [(i["res"], link(i["file"], i["line"]), i["kind"], i["text"][:80]) for i in sc.logic]
    write_report("report_logic.md", "Displayed-looking text used as logic (D3)",
                 "Comparisons and table keys with user-text-looking strings. Each needs an id-based rewrite or a "
                 "confirmation that it is a protocol value (DESIGN.md 6).\n\n" + md_table(rows, ["resource", "where", "kind", "text"]))

    # utf8
    rows = [(i["res"], link(i["file"], i["line"]), i["what"], "`" + i["code"].replace("`", "'") + "`") for i in sc.utf8]
    write_report("report_utf8.md", "UTF-8 unsafe text handling (D6/D7)",
                 "Files that draw text and use byte-based string functions. Check each: on displayed text use "
                 "L.upper/L.lower/L.sub/L.len.\n\n" + md_table(rows, ["resource", "where", "what", "code"]))

    # render measure
    rows = [(i["res"], link(i["file"], i["line"]), "**yes**" if i["render"] else "", i["fn"] or "(anonymous)") for i in sc.render]
    nr = sum(1 for i in sc.render if i["render"])
    write_report("report_render_measure.md", "dxGetTextWidth call sites",
                 "%d sites, %d reached from a render handler (approximation: file-local call graph). Render ones -> "
                 "L.width / L.fit / L.wrap (cached).\n\n" % (len(sc.render), nr) + md_table(rows, ["resource", "where", "render", "function"]))

    # gta fonts
    rows = [(i["res"], link(i["file"], i["line"]), i["font"], "`" + i["text"].replace("`", "'") + "`") for i in sc.gta]
    write_report("report_gta_fonts.md", "Texts drawn with GTA fonts (D8)",
                 "pricedown / bankgothic / beckett / diploma have no ő/ű. Decide per line: translate (with a Roboto "
                 "fallback for the language) or keep (brand / number).\n\n" + md_table(rows, ["resource", "where", "font", "text arg"]))

    # exceptions
    rows = sorted(((r, why, n) for (r, why), n in sc.excluded.items()), key=lambda x: (x[0], x[1]))
    body = md_table(rows, ["resource", "reason", "files / strings"])
    body += "\n\n## Data files with display-looking texts (not built, decide per file)\n\n"
    body += md_table([(d["file"], d["count"], "; ".join("%s: %s" % kv for kv in d["sample"])[:160]) for d in sc.data], ["file", "texts", "sample"])
    write_report("report_exceptions.md", "Exceptions (DESIGN.md 3.2)", body)


def cmd_build(sc_items=None):
    items = sc_items
    if items is None:
        with open(os.path.join(OUT, "inventory.json"), encoding="utf-8") as f:
            items = json.load(f)
    dec = load_json("decisions.json", {})
    common = dec.get("common", {})                      # key -> text
    common_by_text = {norm(t): k for k, t in common.items()}
    hu_en = load_json("hu_to_en.json", {})
    lock = load_json("keys.lock.json", {})
    used_keys = set(lock.values())

    catalogs = defaultdict(dict)
    seed = defaultdict(dict)
    missing_en = []

    def key_for(ns, area, text):
        lk = ns + "|" + text
        if lk in lock:
            return lock[lk]
        base = "%s.%s.%s" % (ns, area, slug(text))
        k, n = base, 1
        while k in used_keys:
            n += 1
            k = "%s_%d" % (base, n)
        lock[lk] = k
        used_keys.add(k)
        return k

    for it in items:
        if it["status"] != "translate":
            continue
        src = it["text"]
        en = src
        if it["hu"]:
            en = hu_en.get(src)
            if en is None:
                missing_en.append(it)
                continue
        if not it["template"]:
            en = escape_braces(en)          # plain text: braces are literal
        ck = common_by_text.get(norm(en))
        if ck:
            catalogs["common"][ck] = common[ck]
            it["key"] = ck
            continue
        k = key_for(it["ns"], area_of(it["inner"]), en)
        it["key"] = k
        catalogs[it["ns"]][k] = en
        if it["hu"]:
            seed[it["ns"]][k] = src

    # rules.txt and other long texts
    files = []
    for res_rel, target in CFG["text_files"].items():
        srcp = os.path.join(RESOURCES, res_rel)
        if os.path.exists(srcp):
            dst = os.path.join(LOCALS, "locales", "en", "files", target)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(srcp, encoding="utf-8") as f:
                text = f.read().replace("\r", "")
            with open(dst, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            files.append("locales/en/files/" + target)

    endir = os.path.join(LOCALS, "locales", "en")
    for fn in os.listdir(endir):
        if fn.endswith(".json"):
            os.remove(os.path.join(endir, fn))
    if "common" not in catalogs:
        catalogs["common"] = {}
    for ns, cat in catalogs.items():
        save_json(os.path.join(endir, ns + ".json"), cat)
    seeddir = os.path.join(LOCALS, "locales", "hu.seed")
    os.makedirs(seeddir, exist_ok=True)
    for fn in os.listdir(seeddir):
        os.remove(os.path.join(seeddir, fn))
    for ns, cat in seed.items():
        save_json(os.path.join(seeddir, ns + ".json"), cat)
    save_json(os.path.join(HERE, "keys.lock.json"), lock)
    update_meta(sorted(catalogs), files)
    save_json(os.path.join(OUT, "inventory.json"), items)

    n = sum(len(c) for c in catalogs.values())
    print("built: %d keys in %d namespaces, %d text files, %d HU seeds%s" % (
        n, len(catalogs), len(files), sum(len(c) for c in seed.values()),
        (", %d Hungarian texts WITHOUT English (tools/hu_to_en.json)" % len(missing_en)) if missing_en else ""))
    if missing_en:
        save_json(os.path.join(OUT, "missing_hu_to_en.json"), {i["text"]: "" for i in missing_en})


def update_meta(namespaces, files):
    path = os.path.join(LOCALS, "meta.xml")
    with open(path, encoding="utf-8") as f:
        meta = f.read()
    start = meta.index('    <file src="locales/languages.json" />')
    end = meta.index("\n", meta.index("<!-- ================= EXPORTS: CLIENT"))
    end = meta.rfind("\n", 0, meta.index("    <!-- ================= EXPORTS: CLIENT"))
    lines = ['    <file src="locales/languages.json" />']
    lines += ['    <file src="locales/en/%s.json" />' % ns for ns in namespaces]
    lines += ['    <file src="%s" />' % p for p in files]
    meta = meta[:start] + "\n".join(lines) + "\n" + meta[end:]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(meta)


# --------------------------------------------------------------------------
# lint
# --------------------------------------------------------------------------
PH = re.compile(r"(?<!\{)\{([A-Za-z0-9_]+)(?:\|([A-Za-z0-9_]*))?\}")
KEY_RX = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)+$")


def cmd_lint():
    global TECH
    TECH = compile_list("technical_patterns")
    errors, warns = [], []
    base = os.path.join(LOCALS, "locales")
    langs = [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)) and re.fullmatch(r"[a-z]{2}(_[A-Z]{2})?", d)]
    cats = {}
    for lang in langs:
        cats[lang] = {}
        for fn in os.listdir(os.path.join(base, lang)):
            if fn.endswith(".json"):
                ns = fn[:-5]
                with open(os.path.join(base, lang, fn), encoding="utf-8") as f:
                    data = json.load(f)
                for k, v in data.items():
                    if not KEY_RX.match(k):
                        errors.append("%s/%s: bad key %s" % (lang, fn, k))
                    elif not k.startswith(ns + "."):
                        errors.append("%s/%s: key outside namespace: %s" % (lang, fn, k))
                    if not isinstance(v, str):
                        errors.append("%s/%s: %s is not a string" % (lang, fn, k))
                    cats[lang][k] = v
    en = cats.get("en", {})
    for lang, cat in cats.items():
        if lang == "en":
            continue
        for k, v in cat.items():
            if k not in en:
                warns.append("[%s] orphan key %s" % (lang, k))
                continue
            if sorted(PH.findall(v)) != sorted(PH.findall(en[k])):
                errors.append("[%s] %s: placeholders differ" % (lang, k))
            if sorted(re.findall(r"#[0-9a-fA-F]{6}", v.lower())) != sorted(re.findall(r"#[0-9a-fA-F]{6}", en[k].lower())):
                errors.append("[%s] %s: colour codes differ" % (lang, k))
    by_val = defaultdict(list)
    for k, v in en.items():
        by_val[(k.split(".")[0], v)].append(k)
    for (ns, v), ks in by_val.items():
        if len(ks) > 1:
            warns.append("same text on %d keys in %s: %r" % (len(ks), ns, v[:60]))

    # keys used in the code
    used, unknown = set(), []
    use_rx = re.compile(r"""(?:\bL|\bL\.forPlayer\s*\([^,]+,|\bL\.msg|translate\s*\([^,]*,?)\s*\(?\s*["']([a-z0-9_]+(?:\.[a-z0-9_]+)+)["']""")
    for dp, dns, fns in os.walk(RESOURCES):
        dns[:] = [d for d in dns if d not in ("node_modules", ".git")]
        for fn in fns:
            if fn.endswith(".lua"):
                p = os.path.join(dp, fn)
                if os.path.getsize(p) > CFG["max_file_bytes"]:
                    continue
                res_, inner_ = resource_of(os.path.relpath(p, RESOURCES).replace("\\", "/"))
                if excluded_file(res_, inner_):
                    continue
                with open(p, encoding="utf-8", errors="replace") as f:
                    src = f.read()
                for m in use_rx.finditer(src):
                    k = m.group(1)
                    used.add(k)
                    if k not in en and not k.startswith("__bench") and not k.startswith("t."):
                        unknown.append("%s: %s" % (os.path.relpath(p, RESOURCES), k))
    for u in unknown:
        errors.append("unknown key used: " + u)
    adopted = {k.split(".")[0] for k in used}
    for k in en:
        if k.split(".")[0] in adopted and k not in used:
            warns.append("unused key in a migrated namespace: " + k)

    # hard-coded texts left in migrated resources (phase 3)
    left = 0
    inv_path = os.path.join(OUT, "inventory.json")
    if adopted and os.path.exists(inv_path):
        sc = Scanner()
        sc.run()
        for it in sc.items:
            if it["ns"] in adopted and it["status"] == "translate":
                left += 1
                warns.append("hard-coded text in %s:%d: %r" % (it["file"], it["line"], it["text"][:60]))

    for e in errors:
        print("ERROR", e)
    for w in warns:
        print("WARN ", w)
    print("lint: %d errors, %d warnings, %d keys (en), %d languages" % (len(errors), len(warns), len(en), len(cats)))
    return 1 if errors else 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "scan":
        cmd_scan()
    elif cmd == "build":
        cmd_build()
    elif cmd == "all":
        sc = cmd_scan()
        cmd_build(sc.items)
    elif cmd == "lint":
        sys.exit(cmd_lint())
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
