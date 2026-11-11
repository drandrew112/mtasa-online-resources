"""police_system / modules/radio_voice/tools/test_builder.py

Offline test of the dispatcher voice: syntax of the module's Lua files, then client/builder.lua run on the real
data/voice.json with tools/test_builder.lua.   python tools/test_builder.py   (pip install lupa)
"""
import json
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
RESOURCE = os.path.dirname(os.path.dirname(MODULE))

L = lua51.LuaRuntime(unpack_returned_tuples=True)

for rel in ("shared/db.lua", "client/builder.lua", "client/player.lua", "server/voice.lua"):
    src = open(os.path.join(MODULE, rel), encoding="utf-8").read()
    ok, err = L.eval("function(s, n) local f, e = loadstring(s, n) return f ~= nil, e end")(src, "@" + rel)
    if not ok:
        print("SYNTAX", err)
        sys.exit(1)
print("syntax ok")


def to_lua(v):
    if isinstance(v, dict):
        t = L.table()
        for k, x in v.items():
            if x is not None:
                t[k] = to_lua(x)
        return t
    if isinstance(v, list):
        t = L.table()
        for i, x in enumerate(v):
            t[i + 1] = to_lua(x)
        return t
    return v


db = json.load(open(os.path.join(MODULE, "data", "voice.json"), encoding="utf-8"))
g = L.globals()
g.EXISTS = lambda p: os.path.exists(os.path.join(RESOURCE, p))
L.execute("VOICE = {}")
L.execute(open(os.path.join(MODULE, "shared", "db.lua"), encoding="utf-8").read())
g.VOICE.db = to_lua(db)
L.execute(open(os.path.join(MODULE, "client", "builder.lua"), encoding="utf-8").read())
L.execute(open(os.path.join(HERE, "test_builder.lua"), encoding="utf-8").read())
