"""wx_snow asset generator (run from anywhere): tex/noise.png, tex/macro.png, tex/flake.png, tex/layer.png,
sounds/wind_loop.wav, and the empty roof map placeholder (data/roofmap.png + roofmap.json) when
no baked map exists yet.

    python tools/make_assets.py [--force-roofmap]
    python tools/make_assets.py --macro-only      only tex/macro.png (the other assets stay byte identical)

Needs numpy + Pillow. Everything is tileable / loopable.
"""
import json
import os
import sys
import wave

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(112)


def tile_noise(size, cells):
    """tileable value noise, smooth (cosine) interpolation, 0..1"""
    grid = rng.random((cells, cells))
    x = np.arange(size) / size * cells
    i0 = np.floor(x).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = x - np.floor(x)
    f = (1 - np.cos(f * np.pi)) / 2
    a = grid[i0][:, i0]
    b = grid[i0][:, i1]
    c = grid[i1][:, i0]
    d = grid[i1][:, i1]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, base, octaves):
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += tile_noise(size, base * 2 ** o) * amp
        total += amp
        amp *= 0.5
    out /= total
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / (hi - lo), 0, 1)


def save(img, rel):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print(rel, os.path.getsize(path), "bytes")


def noise_png():
    s = 256
    r = fbm(s, 4, 5)       # large patches
    g = fbm(s, 8, 4)       # medium
    b = fbm(s, 32, 3)      # fine grain
    a = rng.random((s, s)) # white noise (sparkle)
    rgba = np.stack([r, g, b, a], axis=-1)
    save(Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA"), "tex/noise.png")


def macro_png():
    """tex/macro.png: 1024 x 1024 tileable, every channel a multi scale fbm (shader: world / 256 m,
    so one texel = 0.25 m): r = snow height, g / b = domain warp x / y, a = spare. Own seed, so
    adding it never changes the other assets."""
    global rng
    old = rng
    rng = np.random.default_rng(2112)
    s = 1024
    chans = [fbm(s, 4, 8) for _ in range(4)]
    rng = old
    rgba = np.stack(chans, axis=-1)
    save(Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA"), "tex/macro.png")


def flake_png():
    s = 64
    y, x = np.mgrid[0:s, 0:s] + 0.5
    cx = cy = s / 2
    ang = np.arctan2(y - cy, x - cx)
    rad = np.hypot(x - cx, y - cy) / (s / 2)
    edge = 0.78 + 0.08 * np.sin(ang * 6) + 0.04 * np.sin(ang * 3 + 1)
    a = np.clip((edge - rad) / 0.45, 0, 1) ** 1.6
    rgb = np.ones((s, s, 3)) * np.array([0.97, 0.98, 1.0])
    rgba = np.concatenate([rgb, a[..., None]], axis=-1)
    save(Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA"), "tex/flake.png")


def layer_png():
    w, h = 512, 512
    a = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(900):
        cx, cy = rng.random() * w, rng.random() * h
        r = rng.choice([0.9, 1.2, 1.6, 2.2, 3.0], p=[0.35, 0.3, 0.2, 0.1, 0.05])
        strength = 0.45 + rng.random() * 0.55
        x0, x1 = int(cx - r - 2), int(cx + r + 3)
        y0, y1 = int(cy - r * 1.3 - 2), int(cy + r * 1.3 + 3)
        for ty in range(y0, y1):
            for tx in range(x0, x1):
                d = np.hypot((tx + 0.5 - cx) / r, (ty + 0.5 - cy) / (r * 1.3))
                v = max(0.0, 1 - d) ** 1.4 * strength
                if v > 0:
                    a[ty % h, tx % w] = max(a[ty % h, tx % w], v)
    rgb = np.ones((h, w, 3)) * np.array([0.96, 0.97, 1.0])
    rgba = np.concatenate([rgb, a[..., None]], axis=-1)
    save(Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA"), "tex/layer.png")


def wind_wav():
    rate, seconds = 22050, 12
    n = rate * seconds
    white = rng.standard_normal(n + rate)
    # brown-ish noise: leaky integrator, then band limit
    brown = np.zeros_like(white)
    acc = 0.0
    for i, v in enumerate(white):
        acc = acc * 0.995 + v * 0.06
        brown[i] = acc
    # slow gusts
    t = np.arange(len(brown)) / rate
    gust = 0.55 + 0.25 * np.sin(t * 2 * np.pi / 6.0) + 0.2 * np.sin(t * 2 * np.pi / 2.7 + 1.3)
    sig = brown * gust
    # loop: crossfade the extra second into the start
    fade = rate
    body = sig[:n].copy()
    tail = sig[n:n + fade]
    ramp = np.linspace(0, 1, fade)
    body[:fade] = body[:fade] * ramp + tail * (1 - ramp)
    body /= np.max(np.abs(body)) / 0.8
    pcm = (body * 32767).astype(np.int16)
    path = os.path.join(ROOT, "sounds", "wind_loop.wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(pcm.tobytes())
    print("sounds/wind_loop.wav", os.path.getsize(path), "bytes")


def roofmap_placeholder(force):
    info_path = os.path.join(ROOT, "data", "roofmap.json")
    if os.path.exists(info_path) and not force:
        print("data/roofmap.json exists, placeholder skipped")
        return
    save(Image.new("RGBA", (4, 4), (0, 0, 0, 255)), "data/roofmap.png")
    # MTA toJSON style ([ {...} ]); cells = 0 -> "not baked yet"
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump([{"minX": -3072, "minY": -3072, "size": 6144, "cells": 0,
                    "zMin": -60, "zMax": 1000, "baked": 0}], f, indent=4)
    print("data/roofmap.json placeholder")


if __name__ == "__main__":
    if "--macro-only" in sys.argv:
        macro_png()
        sys.exit(0)
    noise_png()
    macro_png()
    flake_png()
    layer_png()
    wind_wav()
    roofmap_placeholder("--force-roofmap" in sys.argv)
