"""police_system / modules/radio_voice / tools/split_names.py

Splits the ElevenLabs name batches (clone "Dispatch Famale", eleven_v4, "[slowly] [clearly]", one name per
"[long pause]") into one clip per name: sounds_source/NAMES_M|NAMES_F|NAMES_L/NAME_<ID>_01.wav (32 kHz mono,
like every other source). The batches go together on purpose: one generation = one voice state, so the pitch
and the pace are the same for the whole list (names generated one by one came out an octave apart).

Run:  python tools/split_names.py <dir with the mp3 batches: m1 m2 m3 f1 f2 l1 l2 l3 .mp3>
A batch whose clip count differs from its list is refused (then re-generate that batch or fix the list).
"""
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "sounds_source")
SR = 32000

# batch file -> (folder, names in spoken order). The id (file name) is the name upper-cased, letters only.
BATCHES = {
    "m1": ("NAMES_M", "James Michael Robert David Daniel Anthony Marcus Carlos Luis Jose Miguel Andre Darnell Tyrone "
                      "Kevin Brian Jason Eric Ryan"),
    "m2": ("NAMES_M", "Jacob Tyler Brandon Victor Hector Rafael Diego Ivan Nikolai Dmitri Tomas Mateo Lucas Noah Ethan "
                      "Samuel Isaac Kenji Hiro"),
    "m3": ("NAMES_M", "Wei Jin Omar Karim Sean Patrick Liam Connor Frank Tony Vincent Leon Malik Jamal Terrell Ricky "
                      "Johnny Eddie"),
    "f1": ("NAMES_F", "Maria Jessica Ashley Emily Sarah Jennifer Amanda Stephanie Nicole Elizabeth Lauren Rachel Megan "
                      "Hannah Olivia Sophia Isabella Camila Valeria Lucia Gabriela Carmen"),
    "f2": ("NAMES_F", "Rosa Ana Elena Natalia Irina Yuki Mei Lin Aaliyah Keisha Tanisha Jasmine Destiny Brianna Chloe "
                      "Grace Zoe Mia Lily Kate Erin Molly"),
    "l1": ("NAMES_L", "Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez "
                      "Wilson Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson"),
    "l2": ("NAMES_L", "White Harris Sanchez Clark Ramirez Lewis Robinson Walker Young Allen King Wright Scott Torres "
                      "Nguyen Hill Flores Green Adams Nelson Baker Hall"),
    "l3": ("NAMES_L", "Rivera Campbell Mitchell Carter Roberts Delgado Vasquez Moreno Petrov Ivanov Kowalski Novak "
                      "Tanaka Sato Chen Wong Kim Park O'Brien Murphy Kelly Sullivan"),
}

FRAME = 0.01          # s
FLOOR_DB = -48.0      # below this a frame is silence
MIN_GAP = 0.30        # s of silence that separates two names
PAD_HEAD = 0.06
PAD_TAIL = 0.12


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16)


def segments(a):
    n = int(SR * FRAME)
    frames = len(a) // n
    x = a[:frames * n].astype(np.float32).reshape(frames, n) / 32768
    db = 20 * np.log10(np.sqrt((x ** 2).mean(1)) + 1e-9)
    act = db > FLOOR_DB
    segs, i = [], 0
    while i < frames:
        if act[i]:
            j = i
            gap = 0
            k = i
            while k < frames:
                if act[k]:
                    j, gap = k, 0
                else:
                    gap += 1
                    if gap * FRAME >= MIN_GAP:
                        break
                k += 1
            segs.append((i, j + 1))
            i = k
        else:
            i += 1
    return segs, n


def main():
    d = sys.argv[1]
    bad = 0
    for key, (folder, names) in BATCHES.items():
        names = names.split()
        a = decode(os.path.join(d, key + ".mp3"))
        segs, n = segments(a)
        if len(segs) != len(names):
            print("%s: %d clips for %d names - REFUSED" % (key, len(segs), len(names)))
            bad += 1
            continue
        out = os.path.join(SRC, folder)
        os.makedirs(out, exist_ok=True)
        info = []
        for idx, (s, e) in enumerate(segs):
            lo = max(0, int((s * FRAME - PAD_HEAD) * SR))
            hi = min(len(a), int((e * FRAME + PAD_TAIL) * SR))
            if idx + 1 < len(segs):                                   # never reach into the next name
                hi = min(hi, int((segs[idx + 1][0] * FRAME + e * FRAME) / 2 * SR))
            if idx:
                lo = max(lo, int((segs[idx - 1][1] * FRAME + s * FRAME) / 2 * SR))
            cid = "".join(c for c in names[idx].upper() if c.isalpha())
            with wave.open(os.path.join(out, "NAME_%s_01.wav" % cid), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(SR)
                w.writeframes(a[lo:hi].tobytes())
            info.append((names[idx], (e - s) * FRAME))
        print("%s -> %s: %d clips, %s" % (key, folder, len(info),
                                          " ".join("%s=%.2f" % (nm, ln) for nm, ln in info)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
