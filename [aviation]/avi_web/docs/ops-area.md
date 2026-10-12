# ATC Operations Manual - Part 4: Area control

**Document:** SACC-OPS-4 · **Version:** 1.0 · **Effective:** 12 October 2026

San Andreas Control works the **CTA**: the San Andreas FIR outside the TMAs, from the surface to
FL660. It has the overflights, and the arrivals and departures between the TMA boundary and the FIR
boundary. General rules: [Part 1](doc:ops-general). Transfer points: [Letter of Agreement](doc:loa).

---

## 1. Sectors and positions

![The CTA is split into North and South along ZEPHR - PALIS - VINEW - east edge, and into lower and upper at FL205.](img/centre-sectors.svg)

| Sector | Where | Chain: the first open position controls it |
| --- | --- | --- |
| **NL** North lower | north of the line, up to FL205 | SACC_N_CTR > SACC_CTR |
| **SL** South lower | south of the line, up to FL205 | SACC_S_CTR > SACC_CTR |
| **NU** North upper | north of the line, above FL205 | SACC_NU_CTR > SACC_U_CTR > SACC_N_CTR > SACC_CTR |
| **SU** South upper | south of the line, above FL205 | SACC_SU_CTR > SACC_U_CTR > SACC_S_CTR > SACC_CTR |

- **SACC_CTR** (master sector) alone has the whole CTA.
- Any other position can be opened on its own. It takes its sectors from the positions further down
  its chain. Example: SACC_CTR and SACC_U_CTR are open → SACC_U_CTR has NU + SU, SACC_CTR has NL + SL.
- The top bar of the scope shows the sectors you have now: `SECT NL SL`.
- The upper-only positions (U, NU, SU) see traffic only from **FL185** (FL205 - 2000 ft) upwards,
  plus their own aircraft.

The radar picture is refreshed every **3 seconds**.

## 2. Traffic

| Kind | What Control does |
| --- | --- |
| **Overflights** | Enter at the FIR boundary, cross the CTA on their flight plan, leave at another boundary point. Keep them separated, at their requested level if possible, and **at or above 6000 ft over a TMA** ([LOA](doc:loa) §4). |
| **Arrivals** | From the FIR boundary or from another airport, to the TMA entry fix. Give them their STAR and descend them to the LOA level ([LOA](doc:loa) §2). |
| **Departures** | From the SID exit fix (5000 ft) to the FIR boundary or to another TMA. Climb them to their requested level ([LOA](doc:loa) §3). |

- Aircraft from outside appear on the radar **5.5 nm before the FIR boundary**, flying towards their
  entry point.
- Aircraft that leave the FIR are gone from the radar a little after the boundary.

## 3. Arrivals

1. **Give the STAR early.** Arrival procedure → the STAR of the entry fix + the runway in use. The
   suggested STAR is yellow in the list. Without a STAR the pilots ask for one 2500 m before the
   entry fix (**STAR**, yellow frame).
2. **Descend in time.** The arrival has to cross the entry fix at 4000 ft or below (3000 ft on the
   short STARs). From the cruise level this takes distance: a jet descends about 2400 ft per nm, a
   PC-12 only about 1400 ft.
3. **Transfer before the entry fix.**

Arrivals between two airports of the FIR (for example Los Santos → Las Venturas) climb only a little:
their requested level is low, and the STAR starts soon.

## 4. Levels

- Cruise levels: **eastbound** (track 000-179°) odd thousands, **westbound** (track 180-359°) even
  thousands. The requested level (RFL) of the flight plan already follows this rule.
- **FL205** is the boundary of the lower and upper sectors. Transfer aircraft before they cross it
  ([LOA](doc:loa) §9).
- Below 10000 ft aircraft fly at most 250 kts.

## 5. Uncontrolled flights

When a sector has no open position, the aircraft in it fly on their own: overflights keep their
level and route, arrivals descend by their own plan and fly the STAR of their entry fix. When you
open a position, every aircraft in its sectors is yours from that moment, in the state it is in.
