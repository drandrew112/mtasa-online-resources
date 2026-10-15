# Runs the v_inventory unit tests in Lua 5.1 (lupa): python tests/run.py
import os
import sys
from lupa import lua51

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/") + "/"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().TEST_BASE = base
with open(base + "tests/test_server.lua", encoding="utf-8") as f:
    src = f.read()
failures = lua.execute(src)
sys.exit(1 if failures else 0)
