# ATC Operations Manual - Part 1: General

**Document:** SACC-OPS-1 · **Version:** 1.0 · **Effective:** 12 October 2026

This part covers what every controller in the San Andreas FIR has to know, whatever position they
work: the units, the airspace, who controls an aircraft, separation, levels and emergencies.

The other parts:
[Part 2 - Aerodrome control](doc:ops-aerodrome) ·
[Part 3 - Approach control](doc:ops-approach) ·
[Part 4 - Area control](doc:ops-area) ·
[Airspace and navigation](doc:nav) ·
[ATC software manual](doc:software) ·
[Letter of Agreement](doc:loa)

---

## 1. Units and positions

The San Andreas FIR has three kinds of units:

| Unit | Positions | Works | Right needed |
| --- | --- | --- | --- |
| San Andreas Control (area control) | SACC_CTR, SACC_N_CTR, SACC_S_CTR, SACC_U_CTR, SACC_NU_CTR, SACC_SU_CTR | the CTA, by radar | RADAR |
| Approach | SALS_APP, SASF_APP, SALV_APP | the TMA of the airport | APP |
| Tower | SALS_TWR, SASF_TWR, SALV_TWR | the CTR, the runways and the ground | TWR |

| Airport | ICAO | Short | Elevation |
| --- | --- | --- | --- |
| Los Santos International | SALS | LS | 41 ft |
| Easter Bay International (San Fierro) | SASF | SF | 43 ft |
| Las Venturas Airport | SALV | LV | 32 ft |

### 1.1 Rights

Every controller has the **TWR** right. The **APP** and **RADAR** rights come with promotion in the
ATC work. A position can be opened only by a controller who has its right, and each position can
have only one controller.

### 1.2 Where positions are opened

Every position is opened in the **San Andreas Control** building in San Fierro, at the **ATC
consoles** (markers, key **E**). There are no consoles in the airport control towers. Each console
offers only some positions: the console of an airport offers its Tower and Approach, the ACC console
offers the San Andreas Control positions. See the [ATC software manual](doc:software).

## 2. Airspace

| Airspace | Vertical limits | Unit |
| --- | --- | --- |
| **San Andreas FIR** | the whole San Andreas airspace | - |
| CTA | SFC - FL660, the FIR outside the TMAs | San Andreas Control |
| TMA (one per airport) | SFC - 5500 ft, outside the CTR | Approach |
| CTR (one per airport) | SFC - 2000 ft | Tower |

The CTA is split into four **centre sectors**: North / South (along the line ZEPHR - PALIS - VINEW -
east edge) and lower / upper (at FL205). See [Part 4](doc:ops-area). The TMA and CTR shapes are on
the airspace map of this site.

## 3. Who controls an aircraft

**The aircraft belongs to the unit whose airspace it is in.** The software hands every aircraft over
at the boundary automatically. Use **Transfer to** to hand it over earlier, as the
[Letter of Agreement](doc:loa) requires.

- **Ground and CTR** → the Tower of that airport.
- **On final** → the Tower of the destination, even above the 2000 ft CTR ceiling.
- **TMA** → the Approach of that airport.
- **CTA** → the centre sector it is in. The sector belongs to the first open position of its chain,
  see [Part 4](doc:ops-area).

An early transfer is valid only while the aircraft is still in your airspace. After that, the
normal rule applies again.

### 3.1 No top-down cover

**A closed unit is not covered by the unit above it.** When the Tower of an airport is closed, its
Approach does not work the CTR or the ground. When an Approach is closed, San Andreas Control does
not work its TMA. The aircraft in a closed unit's airspace are **uncontrolled**:

- the pilots fly their flight plan and the published procedures (SID / STAR) on their own;
- they descend for the approach and land without clearances;
- on the ground they wait a few seconds at every runway, then cross or enter it when it is free.

Before an aircraft leaves your airspace towards a closed unit, put it back on its procedure or
flight plan, at a level the pilots can continue with.

## 4. Separation

| Where | Minimum |
| --- | --- |
| TMA and CTA (airborne) | **0.1 nm horizontally or 1000 ft vertically** |
| Ground | no two aircraft head-on within **60 m** |

- When two airborne aircraft come closer than 0.1 nm horizontally **and** 1000 ft vertically, both
  labels show **STCA**. This is a separation loss.
- A separation loss is charged to the unit whose airspace the aircraft is in. It is deducted from
  that controller's pay (ground loss €500, TMA €700, CTA €1000). The same pair is charged again only
  10 s after the conflict ended.
- Aircraft on the ground keep their distance on their own when they follow each other. **Head-on**
  meetings on a taxiway are the Tower's responsibility.

## 5. Levels and speed

- Altitudes are in **feet**. On the labels they are in hundreds of feet: `045` = 4500 ft.
- Cleared levels go in **500 ft steps up to 20000 ft**, and in 1000 ft steps above. The highest level
  is **FL390**. The lowest one you can clear is 1000 ft.
- The requested cruise level of the flight plan (**RFL**) is shown in the lists and highlighted in
  the level menu.
- Cruise levels in the CTA: **eastbound** (track 000-179°) odd thousands, **westbound** (track
  180-359°) even thousands.
- Aircraft fly at most **250 kts below 10000 ft**. They slow down by themselves for the approach. No
  speed control is needed.
- Distances are in **nautical miles**. The scope has a scale bar.

## 6. Emergencies and alerts

The red text above a label is an alert:

| Alert | Meaning | What to do |
| --- | --- | --- |
| **EMRG** | Squawk 7700, emergency | Priority over every other aircraft. Clear the way, give the shortest route to land, tell the next units. |
| **COMS** | Squawk 7600, radio failure | The aircraft keeps its flight plan and procedures and does not answer. Keep the others clear of it. |
| **DUPE** | Two aircraft with the same squawk | Give one of them a new code. |
| **STCA** | Separation lost | Separate them immediately: a level or a heading. |
| **RAM** | More than 90° off its route for 40 s | Check whether it is flying a heading you gave. If not, give it a direct or a heading. |

## 7. Pay

When you log out of a position, you get an itemised receipt:

| Item | Amount |
| --- | --- |
| Actions | €700 for every accepted command, multiplied by 1 + 5% for each minute on position (at most ×3) |
| Controlled traffic | €500 for every different aircraft you gave a command to |
| Mistakes | minus the separation losses (section 4) |

A negative total is taken from your bank account. Every accepted command also gives ATC work XP.
