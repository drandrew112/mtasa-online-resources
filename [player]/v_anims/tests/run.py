# Offline checks: Lua 5.1 syntax of every script + tests/test_server.lua. Needs `pip install lupa`.
import glob, os
from lupa import lua51

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..")).replace("\\", "/")
lua = lua51.LuaRuntime()
bad = 0
for path in sorted(glob.glob(ROOT + "/**/*.lua", recursive=True)):
    src = open(path, encoding="utf-8").read()
    res = lua.globals().loadstring(src, "@" + os.path.relpath(path, ROOT))
    if res is None or (isinstance(res, tuple) and res[0] is None):
        bad += 1
        print("SYNTAX", path, res)
print("syntax errors:", bad)
lua.globals().ROOT = ROOT
lua.execute('if not L then end')
lua.globals().dofile(ROOT + "/tests/test_server.lua")
