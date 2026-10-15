# Runs the blood transport checks in Lua 5.1 (lupa): python tests/run.py
#   1. every Lua file of the blood transport resources compiles
#   2. unit tests of the pure logic (bt_stock/server/model.lua, bt_dispatch/server/logic.lua)
import glob, os, sys
from lupa import lua51

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
work = os.path.abspath(os.path.join(root, "..", "[work]", "work_bloodtransport")).replace("\\", "/")
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().BASE = root + "/"
lua.globals().WORK = work + "/"
failed = 0

check = lua.eval("function(src, name) local f, err = loadstring(src, name) return err end")
files = []
for base in [root, work]:
    for dirpath, _, names in os.walk(base):
        files += [os.path.join(dirpath, n) for n in names if n.endswith(".lua") and "tests" not in dirpath.replace("\\", "/").split("/")]
for path in sorted(files):
    with open(path, encoding="utf-8") as f:
        err = check(f.read(), os.path.basename(path))
    if err:
        print("SYNTAX", path, err)
        failed += 1
print("compiled", len(files), "files")

for name in ("test_logic.lua", "test_dispatch.lua"):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().BASE = root + "/"
    with open(root + "/tests/" + name, encoding="utf-8") as f:
        failed += lua.execute(f.read()) or 0
sys.exit(1 if failed else 0)
