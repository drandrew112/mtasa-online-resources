"""eco_loan unit tests: python tests/run.py (needs `pip install lupa`, Lua 5.1 = MTA)."""
import os
import sys
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.dirname(HERE)

FILES = [
    "tests/stubs.lua",
    "shared/config.lua", "shared/calc.lua",
    "server/db.lua", "server/notify.lua", "server/loans.lua", "server/collect.lua", "server/exports.lua",
    "tests/loan_test.lua",
]
# syntax only (MTA client / start-up code)
SYNTAX = ["client.lua", "server/main.lua"]


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = lua.eval("function(src, name) local f, e = loadstring(src, '@' .. name); if not f then error(e) end; return f end")
    for rel in SYNTAX + FILES:
        with open(os.path.join(RES, rel), encoding="utf8") as f:
            fn = load(f.read(), rel)
        if rel in FILES:
            fn()
    res = lua.eval("TEST.result")
    for line in res["lines"].values():
        print(line)
    print(f"{res['pass']} passed, {res['fail']} failed")
    sys.exit(1 if res["fail"] else 0)


if __name__ == "__main__":
    main()
