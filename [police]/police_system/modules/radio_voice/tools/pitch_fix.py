"""police_system / modules/radio_voice/tools/pitch_fix.py

Measures the voice pitch (f0) of every AREAS and PlateCheck clip (the ElevenLabs clone: each word was generated on its own, so some
came out an octave-ish deeper than the rest and than the original LSPDFR dispatcher) and writes tools/area_pitch.json:
  { "AREAS/AREA_X_01.wav": semitones to shift, ... }   (only clips that are off target; 0 / missing = leave alone)
build_db.py reads that file in its encode step (ffmpeg rubberband, formants preserved, length unchanged).

Run:  python tools/pitch_fix.py [--report]      (python 3 + numpy; source wavs stay untouched)
Two trackers: frame autocorrelation folded into one octave around TARGET (stable, but a deep voice folds up) and YIN
(lowest-lag, sees the deep voice but sometimes doubles). Rule: YIN 75-150 Hz and the folded value ~ 2 x YIN -> deep
voice, f0 = YIN; otherwise the folded value.
"""
import json
import math
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_ROOT = os.path.join(os.path.dirname(HERE), "sounds_source")
OUT = os.path.join(HERE, "area_pitch.json")
# folder -> (target Hz or None = median of the folder's own measured clips, deadband in semitones, max shift)
FOLDERS = {"AREAS": (180.0, 1.5, 6.0), "PlateCheck": (None, 1.0, 3.0),
           "NAMES_M": (None, 1.0, 3.0), "NAMES_F": (None, 1.0, 3.0), "NAMES_L": (None, 1.0, 3.0)}
TARGET = 180.0      # Hz, between the AREAS bulk (~172) and the original dispatcher (~185-200)
DEADBAND = 1.5      # semitones; closer than this is left alone
MAX_SHIFT = 6.0     # semitones


def load(p):
    w = wave.open(p)
    sr, n, ch = w.getframerate(), w.getnframes(), w.getnchannels()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768
    return (a.reshape(-1, ch).mean(1) if ch > 1 else a), sr


def fold(f):
    while f > TARGET * 2 ** 0.5:
        f /= 2
    while f < TARGET / 2 ** 0.5:
        f *= 2
    return f


def autocorr_f0(a, sr):
    fl, hop, lo, hi = int(sr * 0.05), int(sr * 0.01), int(sr / 450), int(sr / 70)
    thr = np.sqrt((a ** 2).mean()) * 0.7
    res = []
    for i in range(0, len(a) - fl, hop):
        x = a[i:i + fl]
        if np.sqrt((x ** 2).mean()) < thr:
            continue
        x = x - x.mean()
        ac = np.fft.irfft(np.abs(np.fft.rfft(x * np.hanning(fl), 1 << (2 * fl).bit_length())) ** 2)[:hi + 1]
        ac = ac / (ac[0] + 1e-12)
        seg = ac[lo:hi + 1]
        if seg[seg.argmax()] > 0.6:
            res.append(fold(sr / (lo + seg.argmax())))
    return float(np.median(res)) if len(res) >= 4 else 0.0


def yin_f0(a, sr, fmin=80, fmax=400, thr=0.15):
    if sr > 16000:
        a, sr = a[::sr // 16000], sr / (sr // 16000)
    W, hop, tmax, tmin = int(sr * 0.03), int(sr * 0.01), int(sr / fmin), int(sr / fmax)
    rms = np.sqrt((a ** 2).mean())
    res = []
    for i in range(0, len(a) - W - tmax - 1, hop):
        x = a[i:i + W]
        if np.sqrt((x ** 2).mean()) < rms * 0.5:
            continue
        d = np.zeros(tmax + 1)
        for t in range(1, tmax + 1):
            diff = x - a[i + t:i + t + W]
            d[t] = np.dot(diff, diff)
        dn = np.ones(tmax + 1)
        dn[1:] = d[1:] * np.arange(1, tmax + 1) / (np.cumsum(d[1:]) + 1e-12)
        t = tmin
        while t < tmax:
            if dn[t] < thr:
                while t + 1 < tmax and dn[t + 1] < dn[t]:
                    t += 1
                res.append(sr / t)
                break
            t += 1
    return float(np.median(res)) if len(res) >= 4 else 0.0


def main():
    global TARGET
    shifts, rows = {}, []
    for folder, (target, dead, cap) in FOLDERS.items():
        src = os.path.join(SRC_ROOT, folder)
        meas = []
        TARGET = target or 185.0                      # folding window while measuring
        for n in sorted(os.listdir(src)):
            if not n.lower().endswith(".wav"):
                continue
            a, sr = load(os.path.join(src, n))
            f, y = autocorr_f0(a, sr), yin_f0(a, sr)
            if f <= 0:
                continue                              # too short / unvoiced: no reliable pitch, leave alone
            meas.append((folder + "/" + n, y if (75 <= y <= 150 and abs(f / y - 2) < 0.12) else f))
        tgt = target or float(np.median([m[1] for m in meas]))
        n_shift = 0
        for name, f0 in meas:
            st = 12 * math.log2(tgt / f0)
            rows.append((f0, name, st))
            if abs(st) > dead:
                shifts[name] = round(max(-cap, min(cap, st)), 2)
                n_shift += 1
        v = np.array([m[1] for m in meas])
        print("%-11s %3d measured, %3d shifted | f0 p10 %.0f median %.0f p90 %.0f Hz | target %.0f" %
              (folder, len(meas), n_shift, *np.percentile(v, [10, 50, 90]), tgt))
    json.dump(shifts, open(OUT, "w"), indent=0, sort_keys=True)
    if "--report" in sys.argv:
        for f0, name, st in sorted(rows):
            print("%-48s %5.0f Hz %+5.1f st" % (name, f0, st))


if __name__ == "__main__":
    main()
