"""Strip the night vertex colors chunk (0x253F2F9) from a DFF, so the model has no
night lights / glowing windows. Usage: python dff_strip_nightcolors.py in.dff [out.dff]
(without out.dff the input is overwritten, a .bak copy is kept)."""
import struct, sys, shutil

NIGHT = 0x253F2F9
CONTAINERS = {0x10, 0xE, 0x1A, 0xF, 0x3, 0x14, 0x7, 0x8, 0x6}

def strip(d, o, end):
    out = bytearray(); removed = 0
    while o + 12 <= end:
        t, s, v = struct.unpack_from('<III', d, o)
        body = d[o + 12:o + 12 + s]
        if t == NIGHT:
            removed += 1
        else:
            if t in CONTAINERS:
                body, r = strip(d, o + 12, o + 12 + s); removed += r
            out += struct.pack('<III', t, len(body), v) + body
        o += 12 + s
    return bytes(out), removed

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else src
d = open(src, 'rb').read()
res, n = strip(d, 0, len(d))
if dst == src:
    shutil.copyfile(src, src + '.bak')
open(dst, 'wb').write(res)
print(f'removed {n} night color chunk(s): {len(d)} -> {len(res)} bytes')
