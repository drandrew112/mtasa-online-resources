"""v_locals offline tests (Lua 5.1 through lupa, MTA functions stubbed).

    python tests/run.py

1. syntax check of every .lua file of the resource
2. builds the injected lib exactly like shared/loader.lua and runs tests/test_lib.lua
"""
import os
import sys
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LIB_COMMON = ["lib/utf8x.lua", "lib/template.lua", "lib/formats.lua", "lib/core.lua"]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def lib_source(side, name="L"):
    # mirrors shared/loader.lua buildSource() + import()
    parts = [
        'if type(_G[__LOCALS_NAME]) == "table" and rawget(_G[__LOCALS_NAME], "__v_locals") then return end',
        'local LIB = { side = "%s", defaultLang = "en", cacheMax = 4000 }' % side,
    ]
    parts += [read(p) for p in LIB_COMMON + ["lib/%s.lua" % side]]
    parts.append("_G[__LOCALS_NAME] = LIB.L")
    return 'local __LOCALS_NAME = "%s"\n' % name + "\n".join(parts)


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = lua.eval("function(src, name) local f, e = loadstring(src, name); return f or false, e or \"\" end")

    bad = 0
    for dp, _, files in os.walk(ROOT):
        for fn in files:
            if fn.endswith(".lua"):
                rel = os.path.relpath(os.path.join(dp, fn), ROOT).replace("\\", "/")
                ok, err = load(read(rel), "@" + rel)
                if not ok:
                    print("SYNTAX", err)
                    bad += 1
    for side in ("client", "server"):
        ok, err = load(lib_source(side), "@lib-" + side)
        if not ok:
            print("SYNTAX lib", side, err)
            bad += 1
    print("syntax: %s" % ("OK" if bad == 0 else "%d errors" % bad))
    if bad:
        sys.exit(1)

    lua.globals().LIB_SOURCE_CLIENT = lib_source("client")
    lua.globals().LIB_SOURCE_SERVER = lib_source("server")
    ok, err = load(read("tests/test_lib.lua"), "@tests/test_lib.lua")
    if not ok:
        print(err)
        sys.exit(1)
    failed = ok()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
