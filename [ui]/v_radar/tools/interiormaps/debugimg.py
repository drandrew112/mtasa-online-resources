import json, sys, os
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(HERE, sys.argv[1] + ".json")))
nx, ny = d["nx"], d["ny"]
g = np.frombuffer(d["data"].encode(), dtype=np.uint8).reshape(ny, nx) - 48
img = np.zeros((ny, nx, 3), np.uint8)
img[:] = (40, 60, 40)                       # nothing
img[(g & 4) > 0] = (200, 200, 200)          # floor
img[((g & 4) > 0) & ((g & 8) > 0)] = (240, 240, 255)  # floor + ceiling = indoors
img[(g & 1) > 0] = (230, 140, 40)           # low hit only (furniture)
img[(g & 2) > 0] = (200, 0, 0)              # high hit
img[(g & 3) == 3] = (0, 0, 0)               # both = wall
img = img[::-1]                              # north up
im = Image.fromarray(img).resize((nx * 3, ny * 3), Image.NEAREST)
im.save(os.path.join(HERE, sys.argv[1] + "_dbg.png"))
print("saved", im.size)
