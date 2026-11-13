"""wx_snow offline tests (python + lupa, Lua 5.1).

    python tests/test_snow.py

1. every Lua file of wx_snow + the touched files of other resources compiles
2. shared/coverage.lua: accumulation / melting / instant / dynamic week
3. server/state.lua + server/commands.lua with a mocked MTA: weekly value, override,
   week change clears the override, /snow parsing, weather restore
"""
import glob
import os
import sys

import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.dirname(HERE)                       # wx_snow
ROOT = os.path.dirname(os.path.dirname(RES))      # resources

OTHER = [
    "[core]/v_admin/client/panel/weekly.lua",
    "[core]/v_admin/server/pages/weekly.lua",
    "[core]/v_weekly/server/panel.lua",
    "[core]/v_weekly/server/admin.lua",
    "[core]/v_weekly/server/discord.lua",
    "[core]/v_weekly/client/panel.lua",
    "[ui]/ui_pause/c_pausemenu.lua",
    "[ui]/ui_pause/settings_shared.lua",
    "[graphics]/drawdistance/scripts/main_c.lua",
    "[maps]/maps_loader/client/main.lua",
]

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL", msg)


def new_lua():
    return lupa.LuaRuntime(unpack_returned_tuples=True)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


# ------------------------------------------------------------------ 1. syntax
lua = new_lua()
files = sorted(glob.glob(os.path.join(glob.escape(RES), "**", "*.lua"), recursive=True)) + [os.path.join(ROOT, p) for p in OTHER]
for path in files:
    ok, err = lua.execute("return function(src, name) local f, e = loadstring(src, name) return f ~= nil, e end")(read(path), os.path.basename(path))
    check(ok, f"syntax {os.path.relpath(path, ROOT)}: {err}")
print(f"syntax: {len(files)} files")

# ------------------------------------------------------------------ 1b. shaders (fxc, when installed)
import shutil
import subprocess
import tempfile


def find_fxc():
    hit = shutil.which("fxc")
    if hit:
        return hit
    kits = os.path.join("C:\\", "Program Files (x86)", "Windows Kits", "10", "bin")
    if os.path.isdir(kits):
        for ver in sorted(os.listdir(kits), reverse=True):
            cand = os.path.join(kits, ver, "x64", "fxc.exe")
            if os.path.isfile(cand):
                return cand
    return None


fxc = find_fxc()
if fxc:
    out = os.path.join(tempfile.gettempdir(), "wx_snow_fxc.out")
    fx_files = sorted(glob.glob(os.path.join(glob.escape(RES), "fx", "snow_*.fx")))
    for path in fx_files:
        r = subprocess.run([fxc, "/nologo", "/T", "fx_2_0", "/Fo", out, path], capture_output=True, text=True)
        check(r.returncode == 0, f"fxc {os.path.basename(path)}: {(r.stdout + r.stderr)[-400:]}")
    print(f"shaders: {len(fx_files)} files compiled with fxc")
else:
    print("shaders: fxc not found, skipped")

# ------------------------------------------------------------------ 2. coverage math
lua = new_lua()
lua.execute(read(os.path.join(RES, "shared", "config.lua")))
lua.execute(read(os.path.join(RES, "shared", "coverage.lua")))
g = lua.globals()
cov = g.snowCoverageAt
_dyn = g.snowDynamicLevel


def dyn(*a):
    r = _dyn(*a)
    return r[0] if isinstance(r, tuple) else r



change = g.snowStateChange
T0 = 1_000_000

st = change(None, 4, T0, False)                      # 0 -> heavy (0.85), not instant
check(abs(cov(st, T0) - 0) < 1e-9, "coverage starts at 0")
half = T0 + 10 * 60                                   # ACCUM_MIN 20 -> 0.5 after 10 min
check(abs(cov(st, half) - 0.5) < 1e-6, f"coverage after 10 min {cov(st, half)}")
check(abs(cov(st, T0 + 3600) - 0.85) < 1e-9, "coverage stops at the level cover")
st2 = change(st, 0, T0 + 3600, False)                 # melt from 0.85
check(abs(cov(st2, T0 + 3600) - 0.85) < 1e-9, "melt starts at the old coverage")
check(abs(cov(st2, T0 + 3600 + 20 * 60) - 0.35) < 1e-6, "melt 0.5 in 20 min (MELT_MIN 40)")
check(cov(st2, T0 + 99999) == 0, "melted to 0")
st3 = change(st2, 5, T0 + 3600, True)
check(abs(cov(st3, T0 + 3600) - 0.96) < 1e-9, "instant jumps to the cover")
check(g.snowCoverageEta(st, T0) > 0 and g.snowCoverageEta(st, T0 + 7200) == 0, "eta")
p, lvl = g.snowLevelParams(9)
check(lvl == 5, "level clamp high")
p, lvl = g.snowLevelParams(-3)
check(lvl == 0, "level clamp low")

# dynamic week: always 1..5 for base > 0, deterministic, 0 stays 0, uses every step at least once
seen = set()
for seg in range(200):
    t = T0 + seg * 3 * 3600 + 5
    a = dyn(3, T0, t)
    b = dyn(3, T0, t)
    check(a == b, "dynamic deterministic")
    check(2 <= a <= 4, f"dynamic 3 +-1, got {a}")
    seen.add(a)
check(seen == {2, 3, 4}, f"dynamic uses every step {seen}")
check(dyn(0, T0, T0 + 99999) == 0, "dynamic 0 stays 0")
check(all(1 <= dyn(1, T0, T0 + s * 10800) <= 2 for s in range(100)), "dynamic never below 1")
check(all(4 <= dyn(5, T0, T0 + s * 10800) <= 5 for s in range(100)), "dynamic never above 5")

# ------------------------------------------------------------------ 3. server with a mocked MTA
lua = new_lua()
lua.execute("""
MOCK = { now = 1000000, weather = 1, log = {}, clientEvents = {}, commands = {}, handlers = {}, week = { 500000, { custom = {} } },
         admin = 5, timers = {} }
function getRealTime() return { timestamp = MOCK.now } end
function getResourceFromName(n) return n end
function getResourceState(r) return "running" end
function getResourceName(r) return r end
function outputServerLog(s) MOCK.log[#MOCK.log + 1] = s end
function outputDebugString() end
function getWeather() return MOCK.weather end
function setWeatherBlended(w) MOCK.weather = w end
function setWeather(w) MOCK.weather = w end
function isElement(e) return e ~= nil end
function getElementType(e) return e == "console" and "console" or "player" end
function getPlayerName(p) return tostring(p) end
function triggerClientEvent(to, name, src, ...) MOCK.clientEvents[#MOCK.clientEvents + 1] = { to = to, name = name, args = { ... } } end
function addEvent() end
function addEventHandler(name, el, fn) MOCK.handlers[name] = MOCK.handlers[name] or {}; table.insert(MOCK.handlers[name], fn) end
function fire(name, ...) for _, fn in ipairs(MOCK.handlers[name] or {}) do fn(...) end end
function addCommandHandler(name, fn) MOCK.commands[name] = fn end
function setTimer(fn) MOCK.timers[#MOCK.timers + 1] = fn return {} end
function toJSON(t) return "{}" end
function pcall2(f) return pcall(f) end
resourceRoot, root = "resourceRoot", "root"
exports = setmetatable({}, { __index = function(_, res)
    return setmetatable({}, { __index = function(_, fn)
        return function(self, ...)
            if res == "v_weekly" and fn == "getCurrentWeek" then return MOCK.week[1], MOCK.week[2] end
            if res == "v_mysql" and fn == "getAccData" then return MOCK.admin end
            return nil
        end
    end })
end })
""")
for f in ("shared/config.lua", "shared/coverage.lua", "server/state.lua", "server/commands.lua"):
    lua.execute(read(os.path.join(RES, *f.split("/"))))
g = lua.globals()
mock = g.MOCK

# start with weekly level 3
lua.execute('MOCK.week[2].custom.snow = { level = 3, dynamic = false }')
lua.execute('for _, fn in ipairs(MOCK.handlers.onResourceStart) do fn("wx_snow") end')
check(g.getSnowLevel() == 3, "start: weekly level 3")
check(abs(g.getSnowCoverage() - 0.62) < 1e-9, "start: coverage instant at start")
check(mock.weather == 15, f"start: snow weather 15, got {mock.weather}")

# a client says hello -> gets the state
lua.execute('client = "p1"; fire("wx_snow:hello"); client = nil')
ev = mock.clientEvents[len(mock.clientEvents)]
check(ev.name == "wx_snow:state" and ev.args[1].level == 3, "hello -> state")

# /snow global 5 instant (admin)
lua.execute('MOCK.commands.snow("p1", "snow", "global", "5")')
check(g.getSnowLevel() == 5 and abs(g.getSnowCoverage() - 0.96) < 1e-9, "global 5 instant")
ev = mock.clientEvents[len(mock.clientEvents)]
check(ev.name == "wx_snow:notify" and ev.args[1] == "wx_snow.cmd.global_set", "global -> notify")
prev = len(mock.clientEvents)
# broadcast went to the ready player
check(any(mock.clientEvents[i].name == "wx_snow:state" and mock.clientEvents[i].args[1].level == 5
          for i in range(1, prev + 1)), "global change broadcast")

# not an admin -> ignored
lua.execute('MOCK.admin = 2; MOCK.commands.snow("p2", "snow", "global", "0")')
check(g.getSnowLevel() == 5, "non admin ignored")
lua.execute('MOCK.admin = 5')

# local preview goes to the client only
lua.execute('MOCK.commands.snow("p1", "snow", "2")')
ev = mock.clientEvents[len(mock.clientEvents)]
check(ev.name == "wx_snow:cmd" and ev.args[1] == "preview" and ev.args[2].level == 2 and ev.args[2].instant, "local preview instant by default")
lua.execute('MOCK.commands.snow("p1", "snow", "2", "slow")')
ev = mock.clientEvents[len(mock.clientEvents)]
check(ev.args[2].instant is False, "local preview slow")
check(g.getSnowLevel() == 5, "local preview leaves the server")

# bad input -> usage
lua.execute('MOCK.commands.snow("p1", "snow", "7")')
ev = mock.clientEvents[len(mock.clientEvents)]
check(ev.args[1] == "wx_snow.cmd.usage", "level 7 -> usage")

# week change clears the override, new weekly level 1, coverage melts (not instant)
lua.execute('MOCK.week = { 1104800, { custom = { snow = { level = 1 } } } }; MOCK.now = MOCK.now + 60; fire("onWeeklyChanged", 1104800)')
check(g.getSnowLevel() == 1, f"week change: level 1, got {g.getSnowLevel()}")
info = g.snowInfo()
check(info.override is False or info.override is None, "week change cleared the override")
check(abs(g.getSnowCoverage() - 0.96) < 1e-6, "week change: melting starts from 0.96")
lua.execute('MOCK.now = MOCK.now + 40 * 60')
check(abs(g.getSnowCoverage() - 0) < 1e-6, f"melted after 40 min: {g.getSnowCoverage()}")

# level 0 -> weather restored
lua.execute('MOCK.week = { 1104800, { custom = {} } }; fire("onWeeklyChanged", 1104800)')
check(g.getSnowLevel() == 0, "weekly cleared -> 0")
check(mock.weather == 1, f"weather restored to 1, got {mock.weather}")

# global reset falls back to the weekly value
lua.execute('MOCK.commands.snow("p1", "snow", "global", "4"); MOCK.commands.snow("p1", "snow", "global", "reset")')
check(g.getSnowLevel() == 0, "global reset -> weekly 0")

# dynamic week through the minute timer
lua.execute('MOCK.week = { 1104800, { custom = { snow = { level = 3, dynamic = true } } } }; fire("onWeeklyChanged", 1104800)')
check(2 <= g.getSnowLevel() <= 4, f"dynamic level {g.getSnowLevel()}")
levels = set()
for i in range(60):
    lua.execute('MOCK.now = MOCK.now + 3 * 3600; for _, fn in ipairs(MOCK.timers) do fn() end')
    levels.add(g.getSnowLevel())
check(levels <= {2, 3, 4} and len(levels) >= 2, f"dynamic varies over segments {levels}")

print("tests:", "OK" if not failures else f"{len(failures)} FAILED")
sys.exit(1 if failures else 0)
