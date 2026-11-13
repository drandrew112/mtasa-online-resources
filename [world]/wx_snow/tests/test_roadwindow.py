"""Streamed lane map (client/roofmap.lua ROAD): the window the client fills from data/road/c_*.png must hold
exactly the pixels of the full data/roadmap*.png (4 layers: lanes, layer 2, heights, junction layer), and the
junction tables must load with the sizes of roadmap.json, for several camera positions (inside one chunk, across chunk
borders, at the map edge). MTA is mocked: textures are python pixel arrays.

    python tests/test_roadwindow.py
"""
import json
import os
import sys

import lupa.lua51 as lupa
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.dirname(HERE)

LAYERS = ("roadmap.png", "roadmap2.png", "roadmapz.png", "roadmapj.png")
full = [np.asarray(Image.open(os.path.join(RES, "data", n))) for n in LAYERS]
info = json.load(open(os.path.join(RES, "data", "roadmap.json")))[0]

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()


class Tex:
    def __init__(self, arr):
        self.arr = arr


def py_create_texture(*a):
    if isinstance(a[0], str):
        path = os.path.join(RES, a[0])
        if not os.path.exists(path):
            return None
        return Tex(np.array(Image.open(path).convert("RGBA")))
    return Tex(np.zeros((a[1], a[0], 4), dtype=np.uint8))


g.py_create_texture = py_create_texture
g.py_get_pixels = lambda t: Tex(t.arr.copy())
g.py_size = lambda t: (t.arr.shape[1], t.arr.shape[0])
g.py_set_pixels = lambda t, p: setattr(t, "arr", p.arr.copy())
g.py_get_color = lambda p, x, y: tuple(int(v) for v in p.arr[int(y), int(x)])
g.py_set_color = lambda p, x, y, r, gg, b, a: p.arr.__setitem__((int(y), int(x)), (int(r), int(gg), int(b), int(a)))
g.py_json = lambda s: lua.table_from(json.loads(s)[0]) if False else None
g.py_read = lambda path: open(os.path.join(RES, path), encoding="utf-8").read()

lua.execute('''
SNOW = { ROAD = { INFO = "data/roadmap.json", DIR = "data/road/", WINDOW = 128, MARGIN = 32, SNAP = 16, CACHE = 4, ROWS_PER_FRAME = 8 },
         ROOF = { FILE = "data/roofmap.png", INFO = "data/roofmap.json" } }
handlers = {}
function addEventHandler(ev, _, fn) handlers[#handlers + 1] = { ev = ev, fn = fn } end
timers = {}
function setTimer(fn, ms, n) timers[#timers + 1] = fn return fn end
function outputDebugString(s) print("DEBUG", s) end
function isElement(e) return e ~= nil end
function destroyElement() return true end
function snowChanged(r) changed = r end
function getTickCount() return 0 end
function fileExists() return true end
function fileOpen(p) return { path = p } end
function fileGetSize() return 0 end
function fileRead(f) return py_read(f.path) end
function fileClose() end
function fromJSON(s) return json_decode(s) end
function dxCreateTexture(...) return py_create_texture(...) end
function dxGetTexturePixels(t) return py_get_pixels(t) end
function dxSetTexturePixels(t, p) py_set_pixels(t, p) return true end
function dxGetPixelColor(p, x, y) return py_get_color(p, x, y) end
function dxSetPixelColor(p, x, y, r, g, b, a) py_set_color(p, x, y, r, g, b, a) return true end
shaderValues = {}
function dxSetShaderValue(_, name, ...) shaderValues[name] = { ... } return true end
function dxGetMaterialSize(t) return py_size(t) end
camX, camY = 0, 0
function getCameraMatrix() return camX, camY, 50 end
root, resourceRoot = {}, {}
''')


def to_lua(o):
    if isinstance(o, dict):
        return lua.table_from({k: to_lua(v) for k, v in o.items()})
    if isinstance(o, list):
        return lua.table_from([to_lua(v) for v in o])
    return o


g.json_decode = lambda s: to_lua(json.loads(s)[0])
source = open(os.path.join(RES, "client", "roofmap.lua"), encoding="utf-8").read()
# only the lane map part (the roof map part needs more mocks)
source = source[source.index("-------------------------------------------------------------------------------- lane map"):]
source = source.replace("loadRoof(1)", "").replace("ROOF.unload()", "")
lua.execute(source)

ROAD = g.ROAD
follow = None
failures = []


def run_follow_until_ready(cam_x, cam_y):
    g.camX, g.camY = cam_x, cam_y
    # the 400 ms timer of onClientResourceStart: first registered timer
    lua.execute("timers[1]()")
    steps = 0
    render = [h for h in g.handlers.values() if h.ev == "onClientRender"][0].fn
    while ROAD.job is not None and steps < 2000:
        render()
        steps += 1
    return steps


def check(cam_x, cam_y):
    steps = run_follow_until_ready(cam_x, cam_y)
    w = ROAD.win
    ox, oy = int(w.ox), int(w.oy)
    ok = True
    for l in range(len(LAYERS)):
        arr = ROAD.textures[l + 1].arr
        for j in range(128):
            for i in range(128):
                gi, gj = ox + i, oy + j
                exp = full[l][gj, gi] if 0 <= gi < 1536 and 0 <= gj < 1536 else (0, 0, 0, 0)
                if tuple(arr[j, i]) != tuple(exp):
                    ok = False
                    failures.append(f"cam {cam_x},{cam_y} layer {l} cell {gi},{gj}: {tuple(arr[j, i])} != {tuple(exp)}")
                    break
            if not ok:
                break
    print(f"cam ({cam_x}, {cam_y}) window origin cell ({ox}, {oy}) in {steps} frames:", "OK" if ok else "FAIL")


lua.execute("ROAD.load()")
lua.execute('addEventHandler("onClientResourceStart", resourceRoot, function() end)')
lua.execute("timers[#timers + 1] = nil")
# the real start handler registered ROAD.load + setTimer(follow): emulate it
start = [h for h in g.handlers.values() if h.ev == "onClientResourceStart"][0].fn
lua.execute("timers = {}")
start()

for cam in [(1500, -1700), (1100, -1700), (-2900, -2900), (2900, 2900), (0, 0)]:
    check(*cam)
# staying put must not start another fill
g.camX, g.camY = 0, 0
lua.execute("timers[1]()")
if ROAD.job is not None:
    failures.append("window refilled although the camera did not move")
# moving a little (inside the margin) must not either
g.camX, g.camY = 20, 20
lua.execute("timers[1]()")
if ROAD.job is not None:
    failures.append("window refilled for a small move")

# junction tables: loaded once, sizes as in roadmap.json, handed to the shader
if ROAD.jpaths is None or ROAD.jlists is None:
    failures.append("junction tables not loaded")
else:
    if tuple(g.py_size(ROAD.jpaths)) != tuple(info["jPathSize"]) or tuple(g.py_size(ROAD.jlists)) != tuple(info["jListSize"]):
        failures.append("junction table sizes differ from roadmap.json")
lua.execute("ROAD.apply({})")
sv = g.shaderValues
if sv["gJOn"] is None or sv["gJOn"][1] != 1:
    failures.append("gJOn not set to 1")
if sv["gRoadJTex"] is None or sv["gRoadJTex"][1] is not ROAD.textures[4]:
    failures.append("gRoadJTex is not the 4th window texture")
if tuple(sv["gJSize"].values()) != tuple(info["jPathSize"] + info["jListSize"]):
    failures.append(f"gJSize {tuple(sv['gJSize'].values())}")
print("junction tables:", "OK" if not failures else "FAIL")

if failures:
    print("\n".join(failures[:10]))
    sys.exit(1)
print("lane window: OK")
