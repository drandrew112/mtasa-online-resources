"""police_system / modules/radio_voice/tools/build_db.py

Builds data/voice.json, the fixed radio_voice database (loaded once at resource start on both sides):
  clips     every wav under audio/: length, sample rate, measured lead/tail silence (trimmed at playback), level
  tokens    one spoken unit (a word / phrase / sound effect) -> its clip variants (random pick) + the English text
  maps      game data -> tokens: colours (reference RGB, nearest wins), GTA SA vehicle models, scene categories,
            call kinds, priorities, directions, plate characters, unit types
  phrases   the messages: an ordered sequence of tokens, variables and conditions (see FORMAT in the output)
  triggers  game event -> phrase, who hears it, priority, cooldown, time to live
  missing   what the audio set does not cover (fallback used meanwhile)

Run from anywhere:  python tools/build_db.py [--no-encode]     (python 3 + numpy, ffmpeg on PATH)
Encode: every unique clip -> sounds/<folder>/<name>.ogg (silence trimmed, voice brought to TARGET_RMS, mono 22 kHz
Vorbis); only missing / older files are encoded again. The <file> lines of police_system/meta.xml between the
radio_voice markers are rewritten from the list. The audio folder (the wav sources) is never changed.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import wave
from collections import OrderedDict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
RESOURCE = os.path.dirname(os.path.dirname(MODULE))     # police_system
AUDIO = os.path.join(MODULE, "audio")
SOUNDS = os.path.join(MODULE, "sounds")
OUT = os.path.join(MODULE, "data", "voice.json")
META = os.path.join(RESOURCE, "meta.xml")
REL = "modules/radio_voice/"                            # path of the module inside the resource

TARGET_RMS = -16.0  # dBFS, the level every spoken clip is brought to by the encode step
PEAK_MAX = -1.0     # dBFS, the gain never pushes a peak above this
NO_TRIM = {"FX.NOISE"}


# ------------------------------------------------------------------ measuring

def measure(path):
    w = wave.open(path)
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    win = max(1, int(sr * 0.01))
    k = len(a) // win
    env = np.sqrt((a[:k * win].reshape(k, win) ** 2).mean(axis=1)) if k else np.zeros(1)
    db = 20 * np.log10(np.maximum(env, 1e-9))
    peak = float(20 * np.log10(max(float(np.abs(a).max()) if len(a) else 0, 1e-9)))
    act = np.where(db > max(-45.0, peak - 35.0))[0]
    lead = int(act[0] * 10) if len(act) else 0
    tail = int((k - 1 - act[-1]) * 10) if len(act) else 0
    voiced = a[act[0] * win:(act[-1] + 1) * win] if len(act) else a
    rms = float(20 * np.log10(max(float(np.sqrt((voiced ** 2).mean())) if len(voiced) else 0, 1e-9)))
    md5 = hashlib.md5(open(path, "rb").read()).hexdigest()
    return OrderedDict(ms=int(round(n / sr * 1000)), sr=sr, ch=ch, lead=lead, tail=tail,
                       peak=round(peak, 1), rms=round(rms, 1), md5=md5)


# ------------------------------------------------------------------ token rules
# (folder, filename regex) -> token id, text. First match wins. {1} = first regex group.

RULES = [
    # sound effects (RESIDENT)
    ("RESIDENT", r"DISPATCH_INTRO_\d+", "FX.DISPATCH_INTRO", "[dispatch tone]"),
    ("RESIDENT", r"OFFICER_INTRO_\d+", "FX.OFFICER_INTRO", "[mic key-up]"),
    ("RESIDENT", r"INTRO_\d+", "FX.INTRO", "[radio open]"),
    ("RESIDENT", r"OUTRO_\d+", "FX.OUTRO", "[radio close]"),
    ("RESIDENT", r"INSERT_\d+", "FX.INSERT", "[static burst]"),
    ("RESIDENT", r"IN_\d+", "FX.CLICK", "[click]"),
    ("RESIDENT", r"NOISE_LOOP_\d+", "FX.NOISE", "[static loop]"),
    # openers
    ("ATTENTION_ALL_UNITS", r"ATTENTION_ALL_SWAT_UNITS_\d+", "OPEN.ATTENTION_SWAT", "Attention all SWAT units,"),
    ("ATTENTION_ALL_UNITS", r"DISPATCH_SWAT_UNITS_FROM_\d+", "OPEN.DISPATCH_SWAT_FROM", "Dispatching SWAT units from"),
    ("ATTENTION_ALL_UNITS", r"ATTENTION_ALL_UNITS_\d+", "OPEN.ATTENTION_ALL", "Attention all units,"),
    ("WE_HAVE", r"WE_HAVE_\d+", "REPORT.WE_HAVE", "we have"),
    ("WE_HAVE", r"CITIZENS_REPORT_\d+", "REPORT.CITIZENS", "citizens report"),
    ("WE_HAVE", r"OFFICERS_REPORT_\d+", "REPORT.OFFICERS", "officers report"),
    ("ASSISTANCE_REQUIRED", r"ASSISTANCE_REQUIRED_\d+", "ASSIST.REQUIRED", "assistance required"),
    ("REPORT_RESPONSE", r"REPORT_RESPONSE_COPY_\d+", "ACK.COPY", "Copy."),
    # responses
    ("UNITS_RESPOND", r"UNITS_RESPOND_CODE_02_\d+", "RESPOND.CODE_2", "Units respond code 2."),
    ("UNITS_RESPOND", r"UNITS_RESPOND_CODE_03_\d+", "RESPOND.CODE_3", "Units respond code 3."),
    ("UNITS_RESPOND", r"UNITS_RESPOND_CODE_99_\d+", "RESPOND.CODE_99", "All units respond code 99."),
    # suspect
    ("SUSPECT", r"SUSPECT_HEADING_\d+", "SUSPECT.HEADING", "Suspect heading"),
    ("SUSPECT", r"SUSPECT_IS_\d+", "SUSPECT.IS", "Suspect is"),
    ("SUSPECT", r"SUSPECT_LAST_SEEN_\d+", "SUSPECT.LAST_SEEN", "Suspect last seen"),
    ("LAST_SEEN", r"SUSPECT_LAST_SEEN_\d+", "SUSPECT.LAST_SEEN", "Suspect last seen"),
    ("SUSPECTS", r"SUSPECTS_ARE_\d+", "SUSPECTS.ARE", "Suspects are"),
    ("SUSPECTS", r"SUSPECTS_HEADING_\d+", "SUSPECTS.HEADING", "Suspects heading"),
    ("SUSPECTS", r"SUSPECTS_LAST_SEEN_\d+", "SUSPECTS.LAST_SEEN", "Suspects last seen"),
    ("ON_FOOT", r"ON_FOOT_\d+", "ON_FOOT", "on foot"),
    ("ATTEMPT_TO_FIND", r"ALL_UNITS_ATTEMPT_TO_REAQUIRE_\d+", "SEARCH.REACQUIRE", "All units, attempt to reacquire."),
    ("ATTEMPT_TO_FIND", r"REMAIN_IN_THE_AREA_\d+", "SEARCH.REMAIN", "Units remain in the area."),
    ("CROOK_ARRESTED", r"SUSPECT_APPREHENDED_\d+", "ARREST.APPREHENDED", "Suspect apprehended."),
    ("CROOK_ARRESTED", r"SUSPECT_ARRESTED", "ARREST.ARRESTED", "Suspect arrested."),
    ("CROOK_ARRESTED", r"SUSPECT_IN_CUSTODY", "ARREST.IN_CUSTODY", "Suspect in custody."),
    # directions
    ("DIRECTION", r"DIRECTION_BOUND_(\w+)_\d+", "DIR.BOUND.{1}", "{1l}bound"),
    ("DIRECTION", r"DIRECTION_HEADING_(\w+)_\d+", "DIR.HEADING.{1}", "{1l}"),
    # unit types (the same clips as the A / L plate letters)
    ("UNIT_TYPE", r"(ADAM|LINCOLN)", "UNIT.{1}", "{1c}"),
    # plate check
    ("PlateCheck", r"TargetPlate\d", "PLATE.TARGET", "Target plate"),
    ("PlateCheck", r"Stolen", "PLATE.STOLEN", "vehicle reported stolen"),
    ("PlateCheck", r"Warrant", "PLATE.WARRANT", "owner has an outstanding warrant"),
    ("PlateCheck", r"TrafficFelony", "PLATE.FELONY", "traffic felony"),
    ("PlateCheck", r"TrafficViolation", "PLATE.VIOLATION", "traffic violation"),
    ("PlateCheck", r"ProceedCaution", "PLATE.CAUTION", "proceed with caution"),
    ("PlateCheck", r"([0-9A-Z])", "CHAR.{1}", "{phon}"),
    # colours / vehicles
    ("COLOUR", r"COLOR_(\w+?)_\d+", "COLOR.{1}", "{1l}"),
    ("VEHICLE_CATEGORY", r"VEHICLE_CATEGORY_(\w+?)_\d+", "VEH.{1}", "{veh}"),
    # conjunctives
    ("CONJUNCTIVES", r"(IN_A|ON_A|DRIVING_A|CLOSE_TO|INSIDE|NEAR|OVER|AN|AT|IN|ON|A)_\d+", "CONJ.{1}", "{1l}"),
    # crimes
    ("CRIMES", r"CRIME_(\w+?)_\d+", "CRIME.{1}", "{crime}"),
    ("CRIMES", r"(MOTOR_VEHICLE_ACCIDENT|PUBLIC_INTOX|SUSPICIOUS_VEHICLE)", "CRIME.{1}", "{crime}"),
]

# LAPD phonetic alphabet (the PlateCheck letters say these words; A = Adam, L = Lincoln like the unit types)
PHONETIC = dict(A="Adam", B="Boy", C="Charles", D="David", E="Edward", F="Frank", G="George", H="Henry", I="Ida",
                J="John", K="King", L="Lincoln", M="Mary", N="Nora", O="Ocean", P="Paul", Q="Queen", R="Robert",
                S="Sam", T="Tom", U="Union", V="Victor", W="William", X="X-ray", Y="Young", Z="Zebra")
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

CRIME_TEXT = {
    "10_99_DAVID": "a 10-99 David",
    "11_351": "an 11-351",
    "2_42": "a 2-42",
    "AMBULANCE_REQUESTED": "an ambulance requested",
    "ASSAULT": "an assault",
    "ASSAULT_PEACE_OFFICER": "an assault on a peace officer",
    "ASSAULT_WITH_A_DEADLY_WEAPON": "an assault with a deadly weapon",
    "BRANDISHING_WEAPON": "a person brandishing a weapon",
    "DISTURBING_THE_PEACE": "a disturbance of the peace",
    "GRAND_THEFT_AUTO": "a grand theft auto",
    "GUNFIRE": "gunfire",
    "HIT_AND_RUN": "a hit and run",
    "OFFICER_IN_NEED_OF_ASSISTANCE": "an officer in need of assistance",
    "OFFICER_REQUESTS_AIR_SUPPORT": "an officer requesting air support",
    "OFFICER_REQUESTS_FIRE_DEPT": "an officer requesting the fire department",
    "OFFICER_REQUESTS_TRANSPORT": "an officer requesting prisoner transport",
    "RESIST_ARREST": "a suspect resisting arrest",
    "ROBBERY": "a robbery",
    "SHOTS_FIRED": "shots fired",
    "SHOTS_FIRED_AT_AN_OFFICER": "shots fired at an officer",
    "SUSPECT_ON_THE_RUN": "a suspect on the run",
    "THREATEN_OFFICER_WITH_FIREARM": "a suspect threatening an officer with a firearm",
    "MOTOR_VEHICLE_ACCIDENT": "a motor vehicle accident",
    "PUBLIC_INTOX": "a public intoxication",
    "SUSPICIOUS_VEHICLE": "a suspicious vehicle",
}

# transcripts not certain from the file name alone (listen once, then remove from here)
VERIFY = {
    "PLATE.TARGET": "three different phrasings (1.1-1.6 s)",
    "CRIME.10_99_DAVID": "code meaning on the recording",
    "CRIME.11_351": "LA radio code: narcotics possession for sale (H&S 11351)",
    "CRIME.2_42": "LA radio code: battery (PC 242)",
    "REPORT.CITIZENS": "maybe 'citizens report' / 'we have a report of'",
    "REPORT.OFFICERS": "maybe 'officers report'",
}

# vehicle category text
VEH_TEXT = {"SUV": "SUV", "MUSCLE_CAR": "muscle car", "OFF_ROAD_VEHICLE": "off-road vehicle"}


def text_of(tpl, m, token):
    g = m.group(1) if m.lastindex else ""
    if tpl == "{phon}":
        return DIGITS[int(g)] if g.isdigit() else PHONETIC[g]
    if tpl == "{crime}":
        return CRIME_TEXT.get(g, g.lower().replace("_", " "))
    if tpl == "{veh}":
        return VEH_TEXT.get(g, g.lower().replace("_", " "))
    return tpl.replace("{1l}", g.lower().replace("_", " ")).replace("{1c}", g.capitalize())


def token_of(folder, name):
    base = os.path.splitext(name)[0]
    for f, rx, tok, tpl in RULES:
        if f != folder:
            continue
        m = re.fullmatch(rx, base)
        if m:
            g = m.group(1) if m.lastindex else ""
            return tok.replace("{1}", g), text_of(tpl, m, tok)
    return None, None


# ------------------------------------------------------------------ maps

COLORS = OrderedDict([
    ("AQUA", (0, 200, 200)), ("BEIGE", (220, 200, 160)), ("BLACK", (15, 15, 15)), ("BLUE", (30, 60, 200)),
    ("BRONZE", (140, 95, 50)), ("BROWN", (100, 60, 30)), ("DARK_BLUE", (15, 25, 90)), ("DARK_BROWN", (60, 35, 20)),
    ("DARK_GREEN", (15, 70, 30)), ("DARK_GREY", (70, 70, 70)), ("DARK_MAROON", (70, 10, 20)),
    ("DARK_ORANGE", (200, 90, 10)), ("DARK_PURPLE", (60, 15, 80)), ("DARK_RED", (120, 10, 10)),
    ("DARK_SILVER", (120, 125, 130)), ("DARK_YELLOW", (170, 150, 20)), ("GOLD", (200, 160, 60)),
    ("GRAPHITE", (45, 48, 52)), ("GREEN", (30, 150, 50)), ("GREY", (128, 128, 128)), ("LIGHT_BLUE", (110, 170, 230)),
    ("LIGHT_BROWN", (160, 115, 70)), ("LIGHT_GREEN", (130, 220, 120)), ("LIGHT_GREY", (190, 190, 190)),
    ("LIGHT_MAROON", (150, 50, 70)), ("LIGHT_ORANGE", (255, 170, 80)), ("LIGHT_PURPLE", (170, 120, 210)),
    ("LIGHT_RED", (240, 90, 90)), ("LIGHT_SILVER", (200, 205, 210)), ("LIGHT_YELLOW", (250, 240, 130)),
    ("MAROON", (110, 20, 35)), ("ORANGE", (240, 120, 20)), ("PINK", (240, 120, 180)), ("PURPLE", (110, 40, 150)),
    ("RED", (190, 20, 20)), ("SILVER", (165, 170, 175)), ("WHITE", (240, 240, 240)), ("YELLOW", (240, 210, 30)),
])

# GTA SA model id -> vehicle category token (custom models keep their base id's category; override in VEH_OVERRIDE)
VEH_GROUPS = {
    "SEDAN": [404, 405, 409, 420, 421, 426, 438, 445, 458, 466, 467, 474, 479, 492, 507, 516, 529, 540, 546, 547,
              550, 551, 560, 561, 580, 585, 604],
    "COUPE": [401, 410, 419, 436, 491, 504, 517, 526, 527, 533, 534, 545, 555, 558, 575, 576],
    "HATCHBACK": [496, 565, 589],
    "MUSCLE_CAR": [402, 412, 434, 439, 475, 518, 536, 542, 549, 566, 567, 603],
    "SPORTS_CAR": [429, 477, 480, 506, 559, 562, 587, 602],
    "PERFORMANCE_CAR": [411, 415, 451, 494, 502, 503, 541],
    "SUV": [400, 470, 489, 505, 579],
    "OFF_ROAD_VEHICLE": [424, 444, 471, 495, 500, 556, 557, 568, 573],
    "TRUCK": [403, 414, 422, 443, 455, 456, 478, 499, 514, 515, 535, 543, 554, 578, 600, 605],
    "VAN": [413, 418, 440, 459, 482, 483, 498, 508, 582, 609],
    "SERVICE_VEHICLE": [408, 423, 428, 431, 437, 442, 485, 525, 574, 583, 588],
    "UTILITY_VEHICLE": [457, 552, 572],
    "INDUSTRIAL_VEHICLE": [406, 486, 524, 530, 531, 532],
    "MILITARY_VEHICLE": [432, 433],
    "POLICE_CAR": [427, 490, 528, 596, 597, 598, 599, 601],
    "AMBULANCE": [416],
    "FIRETRUCK": [407, 544],
    "MOTORCYCLE": [448, 461, 462, 463, 468, 521, 522, 523, 581, 586],
    "BICYCLE": [481, 509, 510],
    "HELICOPTER": [417, 425, 447, 469, 487, 488, 497, 548, 563],
    "BOAT": [430, 446, 452, 453, 454, 472, 473, 484, 493, 539, 595],
    "TRAIN": [449, 537, 538, 569, 570, 590],
}
VEH_OVERRIDE = {}   # { "<model>": "VEH.X" } for custom models whose look differs from their base

# v_scenemanager categories -> crime token (null = no crime word: "we have a report" + area)
SCENE_CRIME = OrderedDict([
    ("shooting", "CRIME.GUNFIRE"), ("armed", "CRIME.BRANDISHING_WEAPON"), ("brawl", "CRIME.ASSAULT"),
    ("wanted", "CRIME.SUSPECT_ON_THE_RUN"), ("dui", "CRIME.SUSPICIOUS_VEHICLE"), ("hitandrun", "CRIME.HIT_AND_RUN"),
    ("stolenvehicle", "CRIME.GRAND_THEFT_AUTO"), ("abandoned", "CRIME.SUSPICIOUS_VEHICLE"),
    ("robbery", "CRIME.ROBBERY"), ("burglary", "CRIME.ROBBERY"), ("shoplifting", "CRIME.ROBBERY"),
    ("domestic", "CRIME.2_42"), ("disturbance", "CRIME.DISTURBING_THE_PEACE"), ("drugs", "CRIME.11_351"),
    ("vandalism", "CRIME.DISTURBING_THE_PEACE"), ("suspicious", "CRIME.SUSPICIOUS_VEHICLE"),
    ("mva", "CRIME.MOTOR_VEHICLE_ACCIDENT"), ("motorcycle", "CRIME.MOTOR_VEHICLE_ACCIDENT"),
    ("mci", "CRIME.MOTOR_VEHICLE_ACCIDENT"), ("hitbycar", "CRIME.HIT_AND_RUN"), ("fall", "CRIME.AMBULANCE_REQUESTED"),
    ("heartattack", "CRIME.AMBULANCE_REQUESTED"), ("stroke", "CRIME.AMBULANCE_REQUESTED"),
    ("overdose", "CRIME.AMBULANCE_REQUESTED"), ("drowning", "CRIME.AMBULANCE_REQUESTED"), ("deadbody", None),
    ("false", None),
])
# approximations: the category has no clip of its own (listed in "missing" too)
SCENE_APPROX = ["dui", "abandoned", "burglary", "shoplifting", "vandalism", "suspicious", "deadbody", "domestic"]

# wanted reasons (police_system shared/reasons.lua ids) -> crime token, used in pursuits
REASON_CRIME = OrderedDict([
    ("shots_at_police", "CRIME.SHOTS_FIRED_AT_AN_OFFICER"), ("police_down", "CRIME.OFFICER_IN_NEED_OF_ASSISTANCE"),
    ("assault_officer", "CRIME.ASSAULT_PEACE_OFFICER"), ("homicide", "CRIME.ASSAULT_WITH_A_DEADLY_WEAPON"),
    ("public_shooting", "CRIME.GUNFIRE"), ("shots_near_police", "CRIME.SHOTS_FIRED"),
    ("shop_robbery", "CRIME.ROBBERY"), ("robbery", "CRIME.ROBBERY"), ("vehicle_theft", "CRIME.GRAND_THEFT_AUTO"),
    ("assault", "CRIME.ASSAULT"), ("ramming_police", "CRIME.ASSAULT_PEACE_OFFICER"),
    ("police_vehicle_destroyed", "CRIME.ASSAULT_PEACE_OFFICER"), ("escape_custody", "CRIME.RESIST_ARREST"),
    ("evading_arrest", "CRIME.RESIST_ARREST"), ("evading_police", "CRIME.SUSPECT_ON_THE_RUN"),
    ("failure_to_stop", "CRIME.SUSPECT_ON_THE_RUN"), ("reckless_driving", "CRIME.SUSPECT_ON_THE_RUN"),
])
# order = severity: the pursuit names the first reason of the suspect found in this list


# ------------------------------------------------------------------ phrases + triggers
# FORMAT of a sequence item:
#   "TOKEN"                         a token (random variant)
#   {"var": "plate"}                a variable expanded by the builder (VARS below)
#   {"opt": [...], "p": 0.5}        the items with probability p
#   {"any": [[...], [...]]}         one of the lists, random
#   {"if": "cond", "then": [...], "else": [...]}   cond = a truthy argument of the message (!cond = falsy)
#   {"pause": 120}                  silence in ms
# Every message is wrapped in FX: the dispatch opener + the closer come from the trigger's "frame".

VARS = OrderedDict([
    ("callsign", "unit callsign 'A-12' -> UNIT.ADAM CHAR.1 CHAR.2"),
    ("plate", "plate text -> CHAR.* one by one (spaces / dashes skipped, max 8)"),
    ("color", "'r,g,b' -> nearest maps.colors entry (redmean distance)"),
    ("vehicle", "model id -> maps.vehicles (no entry: the item is dropped)"),
    ("direction", "heading in degrees (0 = north, counter-clockwise like GTA rotZ) -> DIR.HEADING.*"),
    ("bound", "heading -> DIR.BOUND.*"),
    ("crime", "scene category / wanted reason -> maps.sceneCrime / maps.reasonCrime"),
    ("code", "call priority -> maps.priorityCode"),
    ("area", "getZoneName -> AREA.* (no audio yet: always dropped, with the item before it when that is a CONJ)"),
])

PHRASES = OrderedDict()
TRIGGERS = OrderedDict()


def phrase(pid, seq, trigger):
    PHRASES[pid] = seq
    TRIGGERS[pid] = trigger


# --- radio buttons (shared/radio.lua RADIO_IDS): the dispatcher acknowledges
phrase("ACK", ["ACK.COPY"],
       dict(hook="RD.handle: every radio id that worked and has no phrase of its own", audience="officer", priority=1,
            frame="short", ttl=4000, cooldown=1500, note="no officer voice: the key-up click then 'Copy.'"))
phrase("ACK_CODE_4", ["ACK.COPY", {"opt": [{"var": "callsign"}], "p": 0.5}],
       dict(hook="RD.handle CODE_4", audience="unit", priority=1, frame="short", ttl=4000))
phrase("ACK_AMBULANCE", ["ACK.COPY", "CRIME.AMBULANCE_REQUESTED"],
       dict(hook="RD.handle REQUEST_AMBULANCE ok", audience="unit", priority=2, frame="full", ttl=8000))
phrase("ACK_TRANSPORT", ["ACK.COPY", "CRIME.OFFICER_REQUESTS_TRANSPORT"],
       dict(hook="TR.request ok (POL.emit transport.requested)", audience="unit", priority=2, frame="full", ttl=8000))

# --- queries (modules/query): the result read back to the unit
phrase("QUERY_VEHICLE", [
    {"var": "callsign"}, {"pause": 120}, "PLATE.TARGET", {"var": "plate"}, {"pause": 150},
    {"if": "vehicle", "then": [{"var": "color"}, {"var": "vehicle"}]}, {"pause": 150},
    {"if": "stolen", "then": ["PLATE.STOLEN"]},
    {"if": "warrant", "then": ["PLATE.WARRANT"]},
    {"if": "felony", "then": ["PLATE.FELONY"]},
    {"if": "violation", "then": ["PLATE.VIOLATION"]},
    {"if": "caution", "then": ["PLATE.CAUTION"]},
], dict(hook="Q.vehicle send(unit, r)", audience="unit", priority=2, frame="full", ttl=15000,
        args="stolen = r.stolen, warrant = r.ownerWarrants > 0, violation = registration/inspection expired, "
             "caution = stolen or warrant, felony = stolen and warrant"))
phrase("QUERY_PERSON", [
    {"var": "callsign"}, {"pause": 120},
    {"if": "warrant", "then": ["PLATE.WARRANT", "PLATE.CAUTION"],
     "else": [{"if": "licence", "then": ["PLATE.VIOLATION"], "else": ["ACK.COPY"]}]},
    {"if": "wanted", "then": ["SUSPECT.IS", "CRIME.SUSPECT_ON_THE_RUN"]},
], dict(hook="Q.person send(unit, r)", audience="unit", priority=2, frame="full", ttl=15000,
        args="warrant = r.warrants > 0, licence = r.licence ~= 'valid', wanted = r.wanted > 0"))
# no ALPR phrase: the plate reader only shows its labels, the dispatcher speaks only when an officer asks (2026-11-12)

# --- calls (modules/callouts)
phrase("CALL_OFFER", [
    {"var": "callsign"}, {"pause": 100},
    {"any": [["REPORT.WE_HAVE"], ["REPORT.CITIZENS"]]},
    {"if": "crime", "then": [{"var": "crime"}]},
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]},
    {"var": "code"},
], dict(hook="callouts: a new offer popup of a unit (POL.emit callout.offered)", audience="unit", priority=3, frame="full",
        ttl=20000, args="crime = scene category, code = call priority"))
phrase("CALL_ALL_UNITS", [
    "OPEN.ATTENTION_ALL", {"any": [["REPORT.CITIZENS"], ["REPORT.WE_HAVE"]]}, {"var": "crime"},
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]}, {"var": "code"},
], dict(hook="callouts announce: a priority 1 call no unit could be offered", audience="onduty", priority=3, frame="full",
        ttl=30000))

# --- backup (modules/events/dispatch.lua)
phrase("BACKUP_REQUESTED", [
    "OPEN.ATTENTION_ALL", "REPORT.OFFICERS", "CRIME.OFFICER_IN_NEED_OF_ASSISTANCE",
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]}, "RESPOND.CODE_3",
], dict(hook="D.requestBackup ok (POL.emit backup.requested)", audience="onduty", priority=3, frame="full", ttl=20000))
phrase("BACKUP_ASSIGNED", [
    {"var": "callsign"}, "ASSIST.REQUIRED", {"if": "area", "then": ["CONJ.IN", {"var": "area"}]}, "RESPOND.CODE_3",
], dict(hook="D.requestBackup best unit", audience="unit", priority=3, frame="full", ttl=20000))
phrase("PANIC", [
    "OPEN.ATTENTION_ALL", "CRIME.OFFICER_IN_NEED_OF_ASSISTANCE",
    {"if": "shots", "then": ["CRIME.SHOTS_FIRED_AT_AN_OFFICER"]}, "RESPOND.CODE_99",
], dict(hook="POL.on('wanted.reasons'): shots_at_police / police_down added", audience="onduty", priority=4,
        frame="urgent", ttl=20000, cooldown=30000, note="interrupts the current message"))

# --- pursuit (modules/chase, modules/wanted)
phrase("PURSUIT_START", [
    "OPEN.ATTENTION_ALL", "REPORT.OFFICERS", {"var": "crime"},
    {"if": "onFoot", "then": ["SUSPECT.IS", "ON_FOOT"],
     "else": [{"if": "vehicle", "then": ["SUSPECT.IS", "CONJ.DRIVING_A", {"var": "color"}, {"var": "vehicle"}]}]},
    {"if": "direction", "then": ["SUSPECT.HEADING", {"var": "direction"}]},
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]}, "RESPOND.CODE_3",
], dict(hook="POL.on('chase.changed'): the first unit joined, 2 s later if the chase still runs", audience="onduty", priority=3, frame="full", ttl=15000,
        args="crime = first wanted reason (maps.reasonCrime) or SUSPECT_ON_THE_RUN"))
phrase("PURSUIT_UPDATE", [
    {"any": [["SUSPECT.HEADING"], ["SUSPECT.IS", "CONJ.DRIVING_A"]]}, {"var": "direction"},
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]},
], dict(hook="radio_voice 5 s tick: a chase whose heading changed, 30 s cooldown", audience="chase", priority=0, frame="short",
        ttl=5000, cooldown=25000, coalesce="pursuit"))
phrase("PURSUIT_LOST", [
    "SUSPECT.LAST_SEEN", {"if": "direction", "then": [{"var": "bound"}]},
    {"if": "area", "then": ["CONJ.IN", {"var": "area"}]},
    {"any": [["SEARCH.REACQUIRE"], ["SEARCH.REMAIN"]]},
], dict(hook="POL.on('wanted.phase') evading / POL.on('chase.ended') lost", audience="chase", priority=2, frame="full", ttl=10000,
        coalesce="pursuit"))
phrase("SWAT", ["OPEN.ATTENTION_SWAT", {"var": "crime"}, "RESPOND.CODE_3"],
       dict(hook="POL.on('wanted.changed') level reaches POLICE.VOICE.SWAT_LEVEL (the AI tank tier)", audience="chase",
            priority=2, frame="full", ttl=10000, cooldown=180000))
phrase("SUSPECT_ARRESTED", [{"any": [["ARREST.APPREHENDED"], ["ARREST.ARRESTED"], ["ARREST.IN_CUSTODY"]]}],
       dict(hook="POL.on('arrest.cuffed') of a chased / wanted suspect", audience="chase", priority=2,
            frame="full", ttl=8000, coalesce="pursuit"))
phrase("RESIST_ARREST", ["REPORT.OFFICERS", "CRIME.RESIST_ARREST"],
       dict(hook="POL.on('wanted.reasons'): evading_arrest / escape_custody added", audience="chase", priority=2,
            frame="full", ttl=8000, cooldown=30000))

FRAMES = OrderedDict([
    ("short", {"before": ["FX.CLICK"], "after": ["FX.OUTRO"], "noise": True}),
    ("full", {"before": ["FX.DISPATCH_INTRO", "FX.INTRO"], "after": ["FX.OUTRO"], "noise": True}),
    ("urgent", {"before": ["FX.INSERT", "FX.DISPATCH_INTRO"], "after": ["FX.OUTRO"], "noise": True}),
])

AUDIENCES = OrderedDict([
    ("officer", "only the officer who pressed / queried"),
    ("unit", "the members of the unit (POL.units.members)"),
    ("chase", "the members of every unit in the chase (CH.join)"),
    ("onduty", "every on-duty officer (POL.units.onDuty) - later: only within the radio zone / channel"),
])

MISSING = [
    {"what": "AREAS", "why": "getZoneName has no audio (audio/AREAS/no_audio_here.txt)",
     "fallback": "the 'in <area>' part is dropped", "need": "one clip per GTA SA zone name (~370), same voice"},
    {"what": "aircraft category", "why": "no VEHICLE_CATEGORY plane / aircraft clip",
     "fallback": "the vehicle part is dropped for planes, trailers, RC models, kart", "need": "VEHICLE_CATEGORY_PLANE"},
    {"what": "tow truck request", "why": "no 'tow' crime / request clip", "fallback": "ACK.COPY only",
     "need": "CRIME_OFFICER_REQUESTS_TOW"},
    {"what": "backup acknowledged to the requester", "why": "no 'backup on the way' clip",
     "fallback": "ACK.COPY + the all units call", "need": "UNIT_RESPONDING / BACKUP_EN_ROUTE"},
    {"what": "clean query result", "why": "no 'no record / clear' clip", "fallback": "ACK.COPY",
     "need": "NO_WANTS_OR_WARRANTS"},
    {"what": "person name / licence suspended", "why": "names cannot be spoken, no licence clip",
     "fallback": "TrafficViolation for a bad licence", "need": "LICENCE_SUSPENDED / LICENCE_EXPIRED"},
    {"what": "status codes", "why": "no '10-8 / en route / on scene / code 4' replies",
     "fallback": "ACK.COPY", "need": "STATUS_AVAILABLE, EN_ROUTE, ON_SCENE, CODE_4"},
    {"what": "scene categories without a crime clip", "why": ", ".join(SCENE_APPROX),
     "fallback": "the nearest crime (maps.sceneCrime), deadbody / false: no crime word",
     "need": "CRIME_DUI, BURGLARY, SHOPLIFTING, VANDALISM, DOMESTIC_DISTURBANCE, DEAD_BODY"},
    {"what": "unit numbers above 9", "why": "only digits 0-9", "fallback": "'Adam 1 2' digit by digit",
     "need": "optional: 10-99 as words"},
]


# ------------------------------------------------------------------ encode + meta

def encode(clips):
    done = 0
    for rel, info in clips.items():
        if "file" not in info:
            continue
        src = os.path.join(AUDIO, rel)
        dst = os.path.join(RESOURCE, info["file"])
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src) \
                and os.path.getmtime(dst) >= os.path.getmtime(__file__):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        cmd = ["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-ss", "%.3f" % (info["lead"] / 1000.0),
               "-t", "%.3f" % (info["len"] / 1000.0), "-ac", "1", "-ar", "22050",
               "-af", "volume=%.1fdB" % info["gain"], "-c:a", "libvorbis", "-q:a", "3", dst]
        subprocess.run(cmd, check=True)
        done += 1
    total = sum(os.path.getsize(os.path.join(RESOURCE, i["file"])) for i in clips.values() if "file" in i)
    print("encoded %d, sounds/ %.1f MB" % (done, total / 1048576.0))


META_BEGIN = "    <!-- radio_voice sounds: generated by modules/radio_voice/tools/build_db.py -->"
META_END = "    <!-- radio_voice sounds end -->"


def write_meta(clips):
    src = open(META, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in src else "\n"
    lines = [META_BEGIN] + ['    <file src="%s" />' % i["file"] for i in clips.values() if "file" in i] + [META_END]
    block = eol.join(lines)
    if META_BEGIN in src:
        a = src.index(META_BEGIN)
        b = src.index(META_END) + len(META_END)
        src = src[:a] + block + src[b:]
    else:
        anchor = "    <!-- ================= EXPORTS (server) ================= -->"
        src = src.replace(anchor, block + eol + eol + anchor)
    open(META, "w", encoding="utf-8", newline="").write(src)


# ------------------------------------------------------------------ build

def main():
    clips, tokens, unknown = OrderedDict(), OrderedDict(), []
    seen_md5 = {}
    for folder in sorted(os.listdir(AUDIO)):
        fp = os.path.join(AUDIO, folder)
        if not os.path.isdir(fp):
            continue
        for name in sorted(os.listdir(fp)):
            if not name.lower().endswith(".wav"):
                continue
            rel = folder + "/" + name
            info = measure(os.path.join(fp, name))
            tok, text = token_of(folder, name)
            if not tok:
                unknown.append(rel)
                continue
            dup = seen_md5.get(info["md5"])
            if dup:
                info["same"] = dup          # identical to an earlier file: never downloaded twice
            else:
                seen_md5[info["md5"]] = rel
            # level change to TARGET_RMS (the encode step applies it), sound effects keep their level
            if tok.startswith("FX."):
                info["gain"] = 0.0
            else:
                info["gain"] = round(min(TARGET_RMS - info["rms"], PEAK_MAX - info["peak"]), 1)
            if tok in NO_TRIM:
                info["lead"], info["tail"] = 0, 0
            # the playback length after trimming (what the client schedules with)
            info["len"] = max(20, info["ms"] - info["lead"] - info["tail"])
            if not dup:
                info["file"] = REL + "sounds/" + os.path.splitext(rel)[0] + ".ogg"
            clips[rel] = info
            t = tokens.setdefault(tok, OrderedDict(text=text, clips=[]))
            use = info.get("same") or rel
            if use not in t["clips"]:
                t["clips"].append(use)
    for tok, why in VERIFY.items():
        if tok in tokens:
            tokens[tok]["verify"] = why
    # long conjunctive variants: probably carry extra words, the short ones are used until checked
    for tok, t in tokens.items():
        if tok.startswith("CONJ."):
            long_ = [c for c in t["clips"] if clips[c]["ms"] - clips[c]["lead"] - clips[c]["tail"] > 1100]
            if long_ and len(long_) < len(t["clips"]):
                t["avoid"] = long_
                t["verify"] = "variants over 1.1 s spoken: maybe more words, avoided"
            elif long_:
                t["verify"] = "every variant over 1.1 s spoken: maybe more words"

    vehicles = OrderedDict()
    for cat, ids in VEH_GROUPS.items():
        for i in ids:
            assert str(i) not in vehicles, i
            vehicles[str(i)] = "VEH." + cat
    vehicles.update(VEH_OVERRIDE)

    db = OrderedDict()
    db["format"] = 1
    db["about"] = "police_system radio_voice database, generated by tools/build_db.py - do not edit by hand"
    db["audioRoot"] = "modules/radio_voice/audio/"
    db["settings"] = OrderedDict(targetRms=TARGET_RMS, gapMs=40, charGapMs=-20, pauseMs=120, noiseVolume=0.18,
                                 voiceVolume=1.0, maxQueue=4, fadeMs=60)
    db["varsHelp"] = VARS
    db["frames"] = FRAMES
    db["audiences"] = AUDIENCES
    db["phrases"] = PHRASES
    db["triggers"] = TRIGGERS
    db["maps"] = OrderedDict(
        unitType={"adam": "UNIT.ADAM", "lincoln": "UNIT.LINCOLN"},
        chars={c: "CHAR." + c for c in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"},
        colors=[{"token": "COLOR." + k, "rgb": list(v)} for k, v in COLORS.items()],
        directions={"heading": ["DIR.HEADING.NORTH", "DIR.HEADING.WEST", "DIR.HEADING.SOUTH", "DIR.HEADING.EAST"],
                    "bound": ["DIR.BOUND.NORTH", "DIR.BOUND.WEST", "DIR.BOUND.SOUTH", "DIR.BOUND.EAST"],
                    "note": "index = floor(((rotZ + 45) % 360) / 90) + 1; GTA rotZ 0 = north, 90 = west"},
        priorityCode={"1": "RESPOND.CODE_3", "2": "RESPOND.CODE_2", "3": "RESPOND.CODE_2", "panic": "RESPOND.CODE_99"},
        sceneCrime=SCENE_CRIME,
        callKindCrime={"phone": None, "agency": "ASSIST.REQUIRED"},
        reasonCrime=REASON_CRIME,
        reasonOrder=list(REASON_CRIME.keys()),   # severity order (JSON objects lose their order in Lua)
        vehicles=vehicles,
        areas={},
    )
    db["tokens"] = tokens
    db["clips"] = clips
    db["missing"] = MISSING

    # sanity: every token a phrase / map names exists
    names = set(tokens)
    refs = []

    def walk(seq):
        for it in seq:
            if isinstance(it, str):
                refs.append(it)
            elif isinstance(it, dict):
                for k in ("opt", "then", "else"):
                    if k in it:
                        walk(it[k])
                for alt in it.get("any", []):
                    walk(alt)
    for seq in PHRASES.values():
        walk(seq)
    for f in FRAMES.values():
        refs.extend(f["before"] + f["after"])
    refs.extend(v for v in SCENE_CRIME.values() if v)
    refs.extend(REASON_CRIME.values())
    refs.extend(vehicles.values())
    refs.extend(c["token"] for c in db["maps"]["colors"])
    refs.extend(db["maps"]["directions"]["heading"] + db["maps"]["directions"]["bound"])
    refs.extend(db["maps"]["chars"].values())
    refs.extend(v for v in db["maps"]["priorityCode"].values())
    bad = sorted(set(r for r in refs if r not in names))
    if unknown or bad:
        print("UNMATCHED FILES:", unknown)
        print("MISSING TOKENS:", bad)
        sys.exit(1)

    if "--no-encode" not in sys.argv:
        encode(clips)
        write_meta(clips)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=1, ensure_ascii=False)
    # the design page (docs/design.html) reads the same database as a script
    docs = os.path.join(MODULE, "docs")
    os.makedirs(docs, exist_ok=True)
    with open(os.path.join(docs, "voice_db.js"), "w", encoding="utf-8") as f:
        f.write("window.VOICE_DB = " + json.dumps(db, ensure_ascii=False, separators=(",", ":")) + ";\n")
    uniq = sum(1 for c in clips.values() if "same" not in c)
    print("clips %d (%d unique), tokens %d, phrases %d, vehicles %d -> %s" % (
        len(clips), uniq, len(tokens), len(PHRASES), len(vehicles), os.path.relpath(OUT, MODULE)))


if __name__ == "__main__":
    main()
