"""
v_modloader/tools/txdopt.py - re-encodes RenderWare (GTA:SA, D3D9) TXD files for the game engine:

  * uncompressed (A8R8G8B8 / X8R8G8B8 / ...) and mip-less DXT textures are decoded,
  * optionally scaled down to --max (keeps the aspect ratio, power of two halving),
  * a full mip chain is generated (box filter on linear light is overkill here: Lanczos per level),
  * every level is DXT1 (opaque) or DXT5 (any alpha < 250) compressed,
  * textures that are already DXT with mipmaps are copied byte for byte.

Texture names, mask names, addressing (wrap / clamp) and the dictionary order stay the same,
so the DFF keeps finding its materials - only the pixel storage changes.

  python tools/txdopt.py objects/5708.txd                 (in place, max 1024)
  python tools/txdopt.py in.txd -o out.txd --max 2048
  python tools/txdopt.py objects/*.txd --dry-run          (report only)

Needs Pillow >= 11 (DDS DXT1 / DXT5 writing) and numpy.
"""
import argparse, io, struct, sys
from PIL import Image

RW_VERSION = 0x1803FFFF
D3DFMT_A8R8G8B8, D3DFMT_X8R8G8B8, D3DFMT_R5G6B5, D3DFMT_A1R5G5B5, D3DFMT_A4R4G4B4 = 21, 22, 23, 25, 26
FOURCC = {b'DXT1': 'DXT1', b'DXT3': 'DXT3', b'DXT5': 'DXT5'}


def chunks(data, off, end):
    while off + 12 <= end:
        t, size, ver = struct.unpack_from('<III', data, off)
        yield t, off, size, ver
        off += 12 + size


def chunk(t, payload, ver=RW_VERSION):
    return struct.pack('<III', t, len(payload), ver) + payload


def dds_header(w, h, fourcc, size):
    # minimal legacy DDS header so Pillow can decode a compressed level
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000
    pf = struct.pack('<II4s5I', 32, 0x4, fourcc, 0, 0, 0, 0, 0)
    hdr = struct.pack('<7I', 124, flags, h, w, size, 0, 1) + b'\0' * 44 + pf + struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    return b'DDS ' + hdr


def decode_level0(fmt, w, h, data):
    """-> RGBA PIL image of the first level, or None when the format is not handled."""
    if fmt in (b'DXT1', b'DXT3', b'DXT5'):
        im = Image.open(io.BytesIO(dds_header(w, h, fmt, len(data)) + data))
        return im.convert('RGBA')
    code = struct.unpack('<I', fmt)[0]
    n = w * h
    if code == D3DFMT_A8R8G8B8:
        return Image.frombuffer('RGBA', (w, h), data[:n * 4], 'raw', 'BGRA', 0, 1).copy()
    if code == D3DFMT_X8R8G8B8:
        return Image.frombuffer('RGB', (w, h), data[:n * 4], 'raw', 'BGRX', 0, 1).convert('RGBA')
    if code == D3DFMT_R5G6B5:
        return Image.frombuffer('RGB', (w, h), data[:n * 2], 'raw', 'BGR;16', 0, 1).convert('RGBA')
    if code == D3DFMT_A1R5G5B5:
        return Image.frombuffer('RGBA', (w, h), data[:n * 2], 'raw', 'BGRA;15', 0, 1).copy()
    if code == D3DFMT_A4R4G4B4:
        return Image.frombuffer('RGBA', (w, h), data[:n * 2], 'raw', 'BGRA;4B', 0, 1).copy()
    return None


def encode(im, fourcc):
    buf = io.BytesIO()
    src = im.convert('RGB') if fourcc == 'DXT1' else im
    src.save(buf, format='DDS', pixel_format=fourcc)
    raw = buf.getvalue()
    hdr = 128 + (20 if raw[84:88] == b'DX10' else 0)
    return raw[hdr:]


def rebuild_native(struct_payload, ext_chunk, max_size, stats):
    p = struct_payload
    platform, = struct.unpack_from('<I', p, 0)
    if platform != 9:
        stats['skipped'] += 1
        return None
    filt, addr = p[4], p[5]
    name = p[8:40]
    mask = p[40:72]
    raster_fmt, = struct.unpack_from('<I', p, 72)
    fmt = p[76:80]
    w, h, depth, levels, rtype, flags = struct.unpack_from('<HHBBBB', p, 80)
    pal = raster_fmt & 0x6000
    tname = name.split(b'\0')[0].decode('latin1')
    if pal or rtype != 4 or flags & 0x2:   # paletted / not a texture / cube map: leave it
        stats['skipped'] += 1
        return None
    if fmt in FOURCC and levels > 1 and max(w, h) <= max_size:
        stats['kept'] += 1
        return None
    off = 88
    size0, = struct.unpack_from('<I', p, off)
    data0 = p[off + 4:off + 4 + size0]
    im = decode_level0(fmt, w, h, data0)
    if im is None:
        stats['skipped'] += 1
        return None
    # non power of two sizes: D3D9 cards with NONPOW2CONDITIONAL cannot mipmap them -> nearest power
    # of two per side (UVs are normalised, the material looks the same)
    def pot(n):
        lo = 1
        while lo * 2 <= n:
            lo *= 2
        return lo if n - lo <= lo * 2 - n else lo * 2
    if (im.size[0] & (im.size[0] - 1)) or (im.size[1] & (im.size[1] - 1)):
        im = im.resize((max(4, pot(im.size[0])), max(4, pot(im.size[1]))), Image.LANCZOS)
    while max(im.size) > max_size:
        im = im.resize((max(4, im.size[0] // 2), max(4, im.size[1] // 2)), Image.LANCZOS)
    W, H = im.size
    if W % 4 or H % 4:
        stats['skipped'] += 1
        return None
    alpha = im.getchannel('A').getextrema()[0] < 250
    fourcc = 'DXT5' if alpha else 'DXT1'
    levels_data = []
    lvl = im
    # already DXT at the right size: the first level is kept byte for byte (no second lossy pass),
    # only the missing mip levels are generated in the same format
    keep0 = fmt in FOURCC and (W, H) == (w, h) and not (fmt == b'DXT1' and alpha)
    if keep0:
        fourcc = FOURCC[fmt]
        levels_data.append(bytes(data0))
        lvl = lvl.resize((max(1, W // 2), max(1, H // 2)), Image.LANCZOS)
        if lvl.size[0] < 4 or lvl.size[1] < 4:
            stats['kept'] += 1
            return None
    while True:
        levels_data.append(encode(lvl, fourcc))
        nw, nh = lvl.size[0] // 2, lvl.size[1] // 2
        if nw < 4 or nh < 4:
            break
        lvl = lvl.resize((nw, nh), Image.LANCZOS)
    new_raster = (0x300 if alpha else 0x200) | 0x8000          # 4444 / 565 class + has mipmaps
    new_flags = (0x1 if alpha else 0) | 0x8                       # alpha, compressed
    if keep0:
        new_raster = (raster_fmt & 0x0F00) | 0x8000               # same raster class, mipmaps added
        new_flags = (flags & 0x1) | 0x8
    out = bytearray()
    out += struct.pack('<I', 9)
    out += bytes([0x06, addr]) + p[6:8]                          # linear-mip-linear, same addressing
    out += name + mask
    out += struct.pack('<I', new_raster)
    out += fourcc.encode('ascii')
    out += struct.pack('<HHBBBB', W, H, 16, len(levels_data), 4, new_flags)
    for d in levels_data:
        out += struct.pack('<I', len(d)) + d
    stats['converted'] += 1
    stats['log'].append('%-34s %5dx%-5d %-10s -> %5dx%-5d %s, %d mips' % (
        tname, w, h, FOURCC.get(fmt, str(struct.unpack('<I', fmt)[0])), W, H, fourcc, len(levels_data)))
    return chunk(0x15, chunk(0x01, bytes(out)) + ext_chunk)


def process(path, out_path, max_size, dry):
    data = open(path, 'rb').read()
    stats = {'converted': 0, 'kept': 0, 'skipped': 0, 'log': []}
    t, off, size, ver = next(chunks(data, 0, len(data)))
    if t != 0x16:
        raise SystemExit(path + ': not a TXD')
    body = bytearray()
    for t2, o2, s2, v2 in chunks(data, off + 12, off + 12 + size):
        whole = data[o2:o2 + 12 + s2]
        if t2 == 0x15:
            parts = list(chunks(data, o2 + 12, o2 + 12 + s2))
            st = next((c for c in parts if c[0] == 0x01), None)
            ext = b''.join(data[c[1]:c[1] + 12 + c[2]] for c in parts if c[0] != 0x01) or chunk(0x03, b'')
            new = rebuild_native(data[st[1] + 12:st[1] + 12 + st[2]], ext, max_size, stats) if st else None
            body += new if new else whole
        else:
            body += whole
    result = chunk(0x16, bytes(body), ver)
    before, after = len(data), len(result)
    print('%s: %.2f MB -> %.2f MB (converted %d, kept %d, skipped %d)' % (
        path, before / 1e6, after / 1e6, stats['converted'], stats['kept'], stats['skipped']))
    for line in stats['log']:
        print('   ' + line)
    if not dry and stats['converted']:
        open(out_path or path, 'wb').write(result)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('-o', '--out')
    ap.add_argument('--max', type=int, default=1024)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    if a.out and len(a.files) > 1:
        sys.exit('-o works with one input file only')
    for f in a.files:
        process(f, a.out, a.max, a.dry_run)
