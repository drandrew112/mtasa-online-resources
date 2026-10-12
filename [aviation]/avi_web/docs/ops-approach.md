# ATC Operations Manual - Part 3: Approach control

**Document:** SACC-OPS-3 · **Version:** 1.0 · **Effective:** 12 October 2026

Approach works the **TMA** of its airport (SFC - 5500 ft, outside the CTR). It brings arrivals from
the TMA entry fix to the final, and climbs departures from the CTR to the TMA boundary. General
rules: [Part 1](doc:ops-general). Transfer points and levels: [Letter of Agreement](doc:loa).

---

## 1. What Approach sees

- the arrivals and departures of its airport, and every aircraft it controls;
- every aircraft inside or crossing its TMA or CTR;
- airborne traffic only up to **7500 ft** (the 5500 ft TMA ceiling + 2000 ft). Overflights above
  that are not shown.

The radar picture is refreshed every **2 seconds**. The targets jump between refreshes.

## 2. Arrivals

### 2.1 Arrival procedure (STAR)

Every STAR is named after its entry fix on the TMA boundary: `VINEW1A` starts at VINEW. One STAR
serves every runway end of the airport. The runway is given with it: **Arrival procedure → VINEW1A
27L**.

- Control normally gives the STAR before the transfer ([LOA](doc:loa) §2). Approach can give or
  change it too.
- The list shows the STARs of the airport. The **suggested** one (yellow) is the STAR whose entry fix
  is the last one in the flight plan.
- An arrival without a STAR asks for one 2500 m before its entry fix (**STAR**, yellow frame).
- A new STAR replaces the flight plan, the heading and any direct. The aircraft joins the STAR at the
  first fix still ahead of it.

### 2.2 Descent

The aircraft enters the TMA at **4000 ft or below** (3000 ft on the short STARs, Annex A). Clear it
to **1500 ft** as soon as it is yours and the traffic allows it.

Aircraft descend at their own rate. At 250 kts this is per nautical mile:

| Type | Descent per nm |
| --- | --- |
| Jets (A320, B738, E190 ...) | about 2400 ft |
| ATR 72, Dash 8 | about 1800 ft |
| PC-12, King Air | about 1400 ft |

Many STARs are short. Annex A shows from what level each one still works without extra track miles.
When the aircraft is too high, make its track longer with **headings**.

### 2.3 The final

![The final: the final fix is 1200 m before the threshold. The glide path is 1 ft per metre. Above 1700 ft at the final fix the aircraft goes around.](img/final-profile.svg)

| Item | Value |
| --- | --- |
| Final fix (`LS27L`, `SF04` ...) | 1200 m before the threshold, on the extended centre line |
| Ideal level at the final fix | **1200 ft above the field** (about 1250 ft) |
| Cleared level for the approach | **1500 ft** |
| Too high: go-around | more than **1700 ft above the field** at the final fix |
| Glide path | 1 ft per metre from the threshold (1200 ft at the final fix, 600 ft at the half final) |

On the glide path the aircraft can descend faster than the slope, so a little height above it is
lost again. Below the glide path it flies level until it meets the slope.

### 2.4 Cleared approach

**A controlled arrival never starts its final without "Cleared approach".** Without it, the aircraft
flies straight on through the final fix or the centre line, on its heading, and you have to vector it
back.

The pilots ask for it (**APP**, yellow frame) 3500 m before the final fix, or when your heading will
intercept the final. What the aircraft does after **Cleared approach** depends on where it is:

| The aircraft is ... | After "Cleared approach" |
| --- | --- |
| on a STAR or a go-around procedure | flies it to the final fix, then the final |
| on a heading that intercepts the extended centre line at **30° or less**, ahead of the threshold and close enough | keeps the heading and intercepts the final (any runway end of its destination) |
| anywhere else (flight plan, direct, a heading that does not intercept) | flies **directly to the nearest final fix** of its destination. If it is on the airport side of that fix, it goes round a base point first |

A new direct, a new STAR or a go-around cancels the approach clearance.

![Three ways to the final: on the STAR, intercepting on a heading (30° at most), or direct to the nearest final fix with a base point.](img/approach-geometry.svg)

### 2.5 Vectoring

- **Fly heading**, **Turn left heading**, **Turn right heading**: the heading picker of the scope
  shows the turn and the predicted path (see the [software manual](doc:software)).
- A heading replaces the route. The aircraft keeps it until you give a direct, a STAR, **Resume own
  navigation**, or it intercepts the final with an approach clearance.
- The intercept heading must be **30° or less** off the runway heading. Give it so that the aircraft
  meets the centre line **before the final fix**, at 1500 ft.
- The aircraft turns at 6° per second. At 250 kts this is a turn of about 0.2 nm radius. Turn it
  early enough.

### 2.6 Transfer to Tower

Transfer the arrival to the Tower **no later than the final fix** ([LOA](doc:loa) §5). On final it is
the Tower's aircraft anyway.

## 3. Departures

- The departure comes from the Tower once airborne. Its SID and initial level (3000 ft) come with the
  IFR clearance.
- Climb it to **5000 ft** by the SID exit fix, and transfer it to Control before the exit fix
  ([LOA](doc:loa) §3).
- A SID is named after its exit fix: `VINEW1D` ends at VINEW. You can take the aircraft off the SID
  with a heading or a direct. It then continues its flight plan after the direct.

## 4. Go-arounds

A go-around climbs to **3000 ft** on the go-around procedure (`GA 27L`, see
[Airspace and navigation](doc:nav)). The Tower transfers it to you as soon as it is out of the CTR.

- Keep **3000 ft** free near the airport.
- The aircraft stays at 3000 ft until you clear it lower. On the procedure, it accepts a new
  **Cleared approach** and flies the rest of it to the final fix.
- You may take it off the procedure with a heading or a direct at any time.

---

## Annex A - STAR entry levels

*Track* is the length of the STAR from the entry fix to the final fix. *Highest entry* is the
highest level at the entry fix from which **every aircraft type** still reaches 1500 ft by the final
fix on the STAR alone, cleared to 1500 ft at the entry fix (measured in the traffic simulation; the
PC-12 is usually the slowest). *LOA entry* is the agreed level ([LOA](doc:loa) §2). Where it is above
the highest entry, make the track longer with headings. **(short)** marks the STARs where the LOA
entry is 3000 ft.

### Los Santos (SALS)

| STAR | RWY | Track | Highest entry | LOA entry |
| --- | --- | --- | --- | --- |
| VINEW1A | 09L | 0.73 nm | 2500 ft | 4000 ft |
| VINEW1A | 09R | 0.79 nm | 2500 ft | 4000 ft |
| VINEW1A | 27R | 1.93 nm | 4000 ft | 4000 ft |
| VINEW1A | 27L | 1.99 nm | 4250 ft | 4000 ft |
| GROVE1A | 09L | 1.57 nm | 3500 ft | 4000 ft |
| GROVE1A | 09R | 1.63 nm | 3750 ft | 4000 ft |
| GROVE1A | 27R | 1.01 nm | 2750 ft | 4000 ft |
| GROVE1A | 27L | 1.07 nm | 3000 ft | 4000 ft |
| PLAYA1A | 09L | 2.52 nm | 5000 ft | 4000 ft |
| PLAYA1A | 09R | 2.57 nm | 5000 ft | 4000 ft |
| PLAYA1A | 27R | 0.66 nm | 2500 ft | 4000 ft |
| PLAYA1A | 27L | 0.70 nm | 2500 ft | 4000 ft |
| OCEAN1A | 09L | 2.81 nm | 5500 ft | 4000 ft |
| OCEAN1A | 09R | 2.75 nm | 5250 ft | 4000 ft |
| OCEAN1A **(short)** | 27R | 0.59 nm | 2250 ft | 3000 ft |
| OCEAN1A **(short)** | 27L | 0.57 nm | 2250 ft | 3000 ft |
| MARLN1A | 09L | 1.87 nm | 4000 ft | 4000 ft |
| MARLN1A | 09R | 1.80 nm | 4000 ft | 4000 ft |
| MARLN1A | 27R | 0.93 nm | 2750 ft | 4000 ft |
| MARLN1A | 27L | 0.87 nm | 2500 ft | 4000 ft |
| REEFS1A | 09L | 0.89 nm | 2750 ft | 4000 ft |
| REEFS1A | 09R | 0.83 nm | 2500 ft | 4000 ft |
| REEFS1A | 27R | 2.04 nm | 4250 ft | 4000 ft |
| REEFS1A | 27L | 1.98 nm | 4250 ft | 4000 ft |
| SANTA1A **(short)** | 09L | 0.46 nm | 1750 ft | 3000 ft |
| SANTA1A **(short)** | 09R | 0.46 nm | 1750 ft | 3000 ft |
| SANTA1A | 27R | 2.73 nm | 5250 ft | 4000 ft |
| SANTA1A | 27L | 2.77 nm | 5250 ft | 4000 ft |

### San Fierro (SASF)

| STAR | RWY | Track | Highest entry | LOA entry |
| --- | --- | --- | --- | --- |
| MISTY1A **(short)** | 04 | 0.57 nm | 2250 ft | 3000 ft |
| MISTY1A | 22 | 2.61 nm | 5000 ft | 4000 ft |
| ANGPI1A **(short)** | 04 | 0.61 nm | 2250 ft | 3000 ft |
| ANGPI1A | 22 | 2.26 nm | 4500 ft | 4000 ft |
| DOHER1A **(short)** | 04 | 0.78 nm | 2250 ft | 3000 ft |
| DOHER1A | 22 | 1.79 nm | 3750 ft | 4000 ft |
| FLINT1A | 04 | 1.26 nm | 3000 ft | 4000 ft |
| FLINT1A | 22 | 1.06 nm | 2750 ft | 4000 ft |
| GARCI1A | 04 | 1.91 nm | 4000 ft | 4000 ft |
| GARCI1A **(short)** | 22 | 0.41 nm | 1750 ft | 3000 ft |
| BAYSD1A | 04 | 2.50 nm | 4750 ft | 4000 ft |
| BAYSD1A **(short)** | 22 | 0.58 nm | 2250 ft | 3000 ft |
| GANTN1A | 04 | 2.20 nm | 4500 ft | 4000 ft |
| GANTN1A | 22 | 0.81 nm | 2750 ft | 4000 ft |
| JUNIP1A | 04 | 1.51 nm | 3500 ft | 4000 ft |
| JUNIP1A | 22 | 1.41 nm | 3250 ft | 4000 ft |
| PALIS1A | 04 | 0.87 nm | 3000 ft | 4000 ft |
| PALIS1A | 22 | 2.16 nm | 4250 ft | 4000 ft |

### Las Venturas (SALV)

| STAR | RWY | Track | Highest entry | LOA entry |
| --- | --- | --- | --- | --- |
| SHADY1A | 18 | 2.29 nm | 4500 ft | 4000 ft |
| SHADY1A **(short)** | 36 | 0.73 nm | 2250 ft | 3000 ft |
| MONTG1A | 18 | 2.50 nm | 4750 ft | 4000 ft |
| MONTG1A **(short)** | 36 | 0.46 nm | 2000 ft | 3000 ft |
| SPRNG1A | 18 | 2.33 nm | 4500 ft | 4000 ft |
| SPRNG1A | 36 | 0.83 nm | 2750 ft | 4000 ft |
| KACCY1A | 18 | 1.22 nm | 3000 ft | 4000 ft |
| KACCY1A | 36 | 1.39 nm | 3250 ft | 4000 ft |
| DESRT1A | 18 | 0.83 nm | 2750 ft | 4000 ft |
| DESRT1A | 36 | 2.33 nm | 4500 ft | 4000 ft |
| PRCKL1A **(short)** | 18 | 0.47 nm | 2000 ft | 3000 ft |
| PRCKL1A | 36 | 2.50 nm | 4750 ft | 4000 ft |
| BONEC1A **(short)** | 18 | 0.46 nm | 2000 ft | 3000 ft |
| BONEC1A | 36 | 1.88 nm | 4000 ft | 4000 ft |
| GARCI2A | 18 | 1.61 nm | 3500 ft | 3000 ft (LOA §8) |
| GARCI2A **(short)** | 36 | 0.66 nm | 2250 ft | 3000 ft |
