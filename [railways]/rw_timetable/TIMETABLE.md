# Sunline Rail – the current timetable

This is the timetable as it ran from `shared/config.lua` before the `rw_timetable` table existed.
It is also the **seed** (`TT.SEED`): when rw_timetable finds an empty `rw_timetable` table it
inserts these 6 rows, so the trains run exactly as before. On /gov → Public services →
**Railways** the rows can be changed, split up or extended.

## Routes (fixed in `TT.LINES`)

The minutes count from the departure at the first stop (arrival / departure). Dwell time is 1 min.

| Line | Train | Route (minutes) | Track | Can start at |
| --- | --- | --- | --- | --- |
| SL1 | RB, Sunline Regional, no. 1101 + 2n | Unity 0 – Market 2/3 – Cranberry 7 (hall track 4) | main line (1) | Unity |
| SL2 | RB, Sunline Regional, no. 1102 + 2n | Cranberry 0 (hall track 3) – Market 4/5 – Unity 7 | second track (2) | Cranberry |
| SL3 | IC, Sunline Circle clockwise, no. 2101 + 2n | Unity 0 – Market 2/3 – Cranberry 7/8 – Yellow Bell 12/13 – Linden 16/17 – Unity 21 | main line (1) | Unity, Cranberry, Yellow Bell, Linden |
| SL4 | IC, Sunline Circle anticlockwise, no. 2102 + 2n | Unity 0 – Linden 4/5 – Yellow Bell 8/9 – Cranberry 13/14 – Market 18/19 – Unity 21 | second track (2) | Unity, Cranberry |
| SL5 | IC, Sunline Circle clockwise from SF, no. 2201 + 2n | Cranberry 0 – Yellow Bell 4/5 – Linden 8/9 – Unity 13/14 – Market 16/17 – Cranberry 21 | main line (1) | Cranberry, Unity, Yellow Bell, Linden |
| SL6 | IC, Sunline Circle anticlockwise from SF, no. 2202 + 2n | Cranberry 0 – Market 4/5 – Unity 7/8 – Linden 12/13 – Yellow Bell 16/17 – Cranberry 21 | second track (2) | Cranberry, Unity |

A train may end at any later stop of its line. A trip can only start where rw_core has a spawn point
facing the right way (the "can start at" column, `origins` in the config).

## Timetable rows (every day, Mon–Sun)

| # | Line | From → To | Kind | First | Last | Every | Trains / day | Minutes past the hour |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SL1 | Unity → Cranberry | interval | 00:00 | 23:45 | 15 min | 96 | :00 :15 :30 :45 |
| 2 | SL2 | Cranberry → Unity | interval | 00:10 | 23:55 | 15 min | 96 | :10 :25 :40 :55 |
| 3 | SL3 | Unity → Unity | interval | 00:06 | 23:36 | 30 min | 48 | :06 :36 |
| 4 | SL4 | Unity → Unity | interval | 00:05 | 23:35 | 30 min | 48 | :05 :35 |
| 5 | SL5 | Cranberry → Cranberry | interval | 00:10 | 23:40 | 30 min | 48 | :10 :40 |
| 6 | SL6 | Cranberry → Cranberry | interval | 00:15 | 23:45 | 30 min | 48 | :15 :45 |

384 trains a day. Train numbers count up through the day per line: SL1 00:00 = RB 1101,
00:15 = RB 1103, ... (base + 2 × the n-th train of the line that day).

## Why these minutes (keep them when changing the timetable)

From the config comments – the lines share tracks, so other minutes may make trains meet:

- LS–SF corridor: 4 min headway between the RBs and the ICs.
- The two single-track stretches between Yellow Bell and Linden: SL4 :10–:13, SL5 :15–:18,
  SL3 :19–:22, SL6 :28–:31 (+30). Opposing ICs never meet there. A new IC departure that is not on
  a :30 rhythm with these may run into one of them.
- Cranberry throat: SL5 arrives ~:01, SL1 enters hall track 4 ~:07, SL2 leaves hall track 3 ~:10,
  SL3 passes ~:13, SL6 leaves ~:15, SL4 leaves ~:19 (+30).
- Cranberry hall tracks 3 / 4 are too short for the 4-coach ICs (they stay for the RBs).

Example of a thinner night and evening timetable on SL1 (instead of row 1): 00:00–05:30 every
30 min, 06:00–20:45 every 15 min, 21:00–23:30 every 30 min – three interval rows. A daily extra
train is a "single train" row, e.g. one SL3 train Cranberry → Linden a day (pick a minute that
fits the rules above), optionally with its own number (e.g. IC 2999).
