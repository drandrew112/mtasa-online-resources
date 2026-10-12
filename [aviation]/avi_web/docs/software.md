# ATC software manual

**Document:** SACC-SW-1 · **Version:** 1.0 · **Effective:** 12 October 2026

The controller software of San Andreas Control: how to log in, what the radar scope shows, and how to
give commands. How to *use* it as a controller is in the [ATC Operations Manual](doc:ops-general).

---

## 1. Logging in

1. Go to an **ATC console**: a marker in the San Andreas Control building in San Fierro. Every
   position is worked from there; the airport control towers have no consoles.
2. Press **E**. The position list opens.
3. Pick a position and press **Log in**.

![The position list. Each console offers only its own positions. A position that someone else already works shows "Staffed" and their name.](img/login.jpg)

- You only see the positions you have the right for (TWR, APP, RADAR).
- Each console offers only its own positions:

| Console | Positions |
| --- | --- |
| ACC | SACC_CTR, SACC_N_CTR, SACC_S_CTR, SACC_U_CTR, SACC_NU_CTR, SACC_SU_CTR |
| Los Santos | SALS_TWR, SALS_APP |
| San Fierro | SASF_TWR, SASF_APP |
| Las Venturas | SALV_TWR, SALV_APP |

- Logging in to another position logs you out of the old one.

The scope opens straight away. **Hide** in the top bar (or **E** at the console again) hides it, but
you stay logged in. **Logout** ends your shift and pays you.

## 2. The scope

![San Andreas Control (SACC_CTR) with the whole FIR: the CTA, the three TMAs (solid) and CTRs (dashed), the fixes, the traffic and the flight lists on the right.](img/scope-centre.jpg)

The scope has four parts:

| Part | What it shows |
| --- | --- |
| **Top bar** | your position and its name, your sectors (Control only, `SECT NL SL`), the runways in use (`SALS ARR 27L DEP 27R`), the wind, the display buttons, the UTC time, and the List / Reset view / Hide / Logout buttons |
| **Map** | airspaces, airports, fixes, the traffic with labels |
| **Flight lists** | on the right (List: on / off) |
| **Bottom left** | the scale bar (in nm) and the world position under the cursor |

### 2.1 Default view of each position

| Position | View after login (and after **Reset view**) |
| --- | --- |
| Control | the whole FIR |
| Approach | its TMA |
| Tower | the airfield: runways, taxiways, stands |

![Los Santos Approach: the TMA, the CTR (dashed), the procedure points and an arrival on SANTA1A 27L.](img/scope-approach.jpg)

![Los Santos Tower: runways, taxiways, stands and the ground labels. LCX6979 and VCA502 wait for their IFR clearance (yellow frame, "REQ IFR" in the list).](img/scope-tower.jpg)

### 2.2 Mouse and keys

| Input | Action |
| --- | --- |
| **Mouse wheel** | zoom at the cursor |
| **Right drag** | move the map |
| **Left click** on a label or a target | open the command menu |
| **Left drag** on a label | move the label (the leader line follows) |
| **Right click** on a label | show / hide the route of the aircraft |
| **Right click** on an empty spot | hide every shown route |
| **Click** a row of a flight list | centre the map on that aircraft |
| **0 - 5** (also numpad) | speed vector length: 0 = off, 1-5 = 0.1-0.5 nm |

### 2.3 Display buttons

The buttons in the middle of the top bar (hover over them for help):

| Button | Action |
| --- | --- |
| **AT** | airspace names and limits on / off |
| **FIXL** | fix names on / off (the fixes of a shown route stay named) |
| **V-** / **V+** | shorter / longer speed vector |

### 2.4 Radar refresh

The targets move only when the radar picture is refreshed: Tower every **1 s**, Approach every
**2 s**, Control every **3 s**. Between refreshes they stand still.

### 2.5 What each position sees

| Position | Traffic shown |
| --- | --- |
| Tower, Approach | the arrivals and departures of their airport, every aircraft they control, and (Approach) everything inside or crossing its TMA. Airborne traffic only up to **7500 ft** |
| Control, lower or master | everything |
| Control, upper only (U, NU, SU) | traffic from **FL185** up, plus their own aircraft |

## 3. Targets and labels

![The airborne label, hovered so every line shows.](img/label-air.svg)

### 3.1 Airborne

The **target** is a small square. Behind it the **history dots** show its last positions (one every
3 s), and in front of it the **speed vector** shows where it will be (length set with 0-5 / V-, V+).

The **label** has up to five lines:

| Line | Example | Meaning |
| --- | --- | --- |
| 1 | `NRA9521 CS B763/H` | callsign, **controller** (white), aircraft type / wake category (L, M, H, J) |
| 2 | `330 340 CAYO` | altitude in hundreds of feet, ground speed in knots, destination |
| 3 | `330` | cleared level. Hidden when none is set |
| 4 | `VINEW1A 27L 270` | the direct-to fix or the procedure flown, and the assigned heading (`L270` / `R270` while a forced turn lasts). Hidden when empty |
| 5 | `3422 181 -1800` | squawk, heading, vertical speed (ft/min). Only while hovered |

Hovering a label gives it a grey background and shows every line, the empty ones as `CFL`, `DCT`,
`AHDG`.

**Controller codes** on line 1:

| Code | Controller |
| --- | --- |
| `T` / `A` | the Tower / Approach of your own airport |
| `SF_T`, `LS_A` ... | the Tower / Approach of another airport |
| `CM` | SACC_CTR (master sector) |
| `CN`, `CS`, `CU`, `CNU`, `CSU` | the other centre positions |
| `--` | nobody (uncontrolled) |

**Colours:** a label is **blue** when the aircraft is yours, **grey** when it is not. You can see the
information of any aircraft, but only its controller can give it commands.

### 3.2 Ground

![Ground labels: blue = departure, green = arrival. The yellow frame means the aircraft waits for a clearance.](img/label-ground.svg)

Ground labels always have a background: **blue** for departures, **green** for arrivals, grey when not
known. Lines: callsign, speed and squawk, type / wake. Ground traffic is hidden when you zoom out far.

### 3.3 Frames and alerts

| Frame / text | Meaning |
| --- | --- |
| **Yellow frame** | one of your aircraft is waiting for a clearance (the request is also shown in the list, for example `REQ IFR`) |
| **Red frame + red text above** | an alert: EMRG, COMS, DUPE, STCA, RAM (see [Part 1, section 6](doc:ops-general)) |

## 4. The command menu

Click a label or a target. The top of the menu shows the flight: callsign, type, squawk, departure →
destination, its state and what it needs now, its route, procedure (with the suggested one) and its
controller.

The commands are grouped. A command that cannot be given now is **grey**. A command the aircraft is
asking for is **yellow**. On the ground the whole flow is listed in order.

![The menu of an airborne aircraft under SACC_CTR.](img/menu.jpg)

### 4.1 Airborne commands

| Group | Command | Who |
| --- | --- | --- |
| LEVEL & ROUTE | **Cleared altitude** › list of levels (current yellow, requested level green) | its controller |
| | **Fly heading** / **Turn left heading** / **Turn right heading** › heading picker | its controller |
| | **Direct to** › the fixes of its route, the final fix of the runway in use, the nearest other fixes | its controller |
| | **Arrival procedure** › STAR + runway (suggested yellow) | Approach, Control |
| | **Resume own navigation** (when on a heading), **Cancel direct** | its controller |
| APPROACH & LANDING | **Cleared approach** | its controller |
| | **Cleared to land**, **Vacate via** › exits | Tower |
| | **Go around** | its controller |
| COORDINATION | **Transfer to** › open positions | its controller |
| DISPLAY | **Show route** / **Hide route**, **Reset label position**, **Close** | anyone |

### 4.2 Ground commands

![The menu of a departure at its stand: only the IFR clearance is active now.](img/menu-ground.jpg)

| Group | Command |
| --- | --- |
| DELIVERY | **IFR clearance** › SID (suggested yellow, the runways not in use marked) › initial level |
| GROUND | **Pushback approved**, **Taxi** › runway end (departures), **Taxi to stand** › stand (arrivals) |
| RUNWAY | **Cross runway**, **Backtrack runway**, **Line up and wait**, **Cleared for take-off** (departures), **Vacate via** (arrivals) |

![The IFR clearance: first the SID. The suggested one is at the top in yellow, the SIDs of runways not in use are marked.](img/menu-sid.jpg)

Long lists scroll with the **mouse wheel**. **< Back** returns to the main menu.

### 4.3 The heading picker

**Fly heading**, **Turn left heading** and **Turn right heading** open a compass ring around the
aircraft instead of a list:

![The heading picker: the cyan line is the predicted path of the turn, with a dot every 30 s.](img/hdgpicker.jpg)

| Input | Action |
| --- | --- |
| **Mouse direction** | picks the heading in 5° steps |
| **Mouse wheel** | ±5° |
| **Left click** | gives the heading |
| **Right click** / **Esc** | back to the menu |

The box shows the new heading, the turn (`LEFT 110°`) and how long it takes. *Fly heading* turns the
shorter way. *Turn left / right* turn that way even when it is the longer way round.

## 5. Flight lists

| Position | Lists |
| --- | --- |
| Tower, Approach | **DEPARTURES** and **ARRIVALS** of the airport |
| Control | **DEPARTURES** (on the ground or in the departure TMA), **ARRIVALS** (in the arrival TMA or landed), **SECTOR** (every other airborne aircraft) |

| Column | Meaning |
| --- | --- |
| CS, TYPE | callsign, type / wake |
| ADEP, ADES | departure, destination |
| FIRST WP / LAST WP / ENTRY / EXIT | first / last fix of the flight plan |
| ALT | altitude (×100 ft). On the ground the state (GATE, PUSHBAC, TAXI_OU ...) or **REQ ...** in yellow when it waits for you |
| CFL, RFL | cleared level, requested cruise level |
| CTRL | its controller |

Your own aircraft are at the top, in blue. Click a row to centre the map on the aircraft.

## 6. Transfers

**Transfer to** hands the aircraft to another open position before it leaves your airspace. The new
controller has it while it is still in your airspace. Once it crosses the boundary, the normal rule
applies: the unit of the airspace it is in. See the [Letter of Agreement](doc:loa).

## 7. Logging out and pay

**Logout** (or leaving the server) ends the shift. You get an itemised receipt: actions, controlled
traffic and mistakes. See [Part 1, section 7](doc:ops-general).
