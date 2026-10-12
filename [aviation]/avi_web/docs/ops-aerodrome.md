# ATC Operations Manual - Part 2: Aerodrome control

**Document:** SACC-OPS-2 · **Version:** 1.0 · **Effective:** 12 October 2026

The Tower works the **CTR** (SFC - 2000 ft), the **runways** and the **ground** of its airport, and
the arrivals on final. Every clearance on the ground and every landing clearance comes from the
Tower. General rules: [Part 1](doc:ops-general).

---

## 1. Runways

| Airport | Runways | Use |
| --- | --- | --- |
| Los Santos (SALS) | 09L/27R, 09R/27L | **09R/27L arrivals**, **09L/27R departures** |
| San Fierro (SASF) | 04/22 | arrivals and departures |
| Las Venturas (SALV) | 18/36 | arrivals and departures |

- The **runway in use** follows the wind: the end with the most headwind. It is shown in the top bar
  of the scope (`SALS ARR 27L DEP 27R`) and on the home page of this site.
- When the runway in use changes, tell Approach. Aircraft already cleared keep their runway.
- **San Fierro 22** has no taxiway to its threshold. Departures there need a **backtrack**.

### 1.1 The runway zone

The runway plus 5 m on both sides and 30 m beyond both ends is the **runway zone**. **No aircraft
enters it without a clearance.** Aircraft stop at the edge of the zone (holding short) and ask:

| Request | When | Clearances |
| --- | --- | --- |
| **CROSS** | the taxi route only crosses this runway | Cross runway |
| **T/O** | it is the departure runway, entered within 80 m of the threshold | Line up and wait, Cleared for take-off |
| **BKTRK** | it is the departure runway, entered more than 80 m from the threshold | Backtrack runway, then Cleared for take-off |

One clearance is valid for one runway only. On a runway aircraft taxi at 50 kts, on the taxiways
at 25 kts.

## 2. Departures step by step

The command menu of a ground aircraft lists the whole flow in order. The step the aircraft is at now
is active, the others are grey. A **yellow frame** around the label means the aircraft is waiting
for the next clearance.

### 2.1 IFR clearance (at the stand)

**IFR clearance** gives the departure:

- its **SID**: the list shows the SIDs of the airport, the suggested one (whose exit fix is the first
  fix of the flight plan) in yellow. *No SID* is possible too: the aircraft then turns towards its
  first fix after the climb-out;
- its **initial level**: standard **3000 ft** ([LOA](doc:loa) §6). The list goes up to 10000 ft.

The IFR clearance accepts the route. Without it the aircraft does not ask for pushback.

### 2.2 Pushback

**Pushback approved**: the aircraft is pushed tail first onto the nearest taxiway, nose towards the
departure runway. Make sure the taxiway behind it is free.

### 2.3 Taxi

**Taxi** gives the runway (end) to taxi to. The aircraft takes the shortest route on the taxiways.
On the way it stops:

- **behind other taxiing aircraft**: 60 m behind the one ahead on its path. Queues form by themselves;
- **at every runway it crosses**: it holds short and asks for **CROSS**;
- **at its departure runway**: it holds short and asks for **T/O** or **BKTRK**.

Two aircraft meeting **head-on** on a taxiway stop each other. Avoid this with the order of the taxi
clearances. It counts as a ground separation loss.

### 2.4 Line up and take-off

- **Line up and wait**: it enters the runway, lines up at the threshold and waits.
- **Backtrack runway**: it enters, taxis back to the threshold, turns round and is lined up.
- **Cleared for take-off**: given while holding short (no backtrack needed) or lined up. The take-off
  clearance is accepted **only at the runway**.

After take-off the aircraft flies **runway heading up to 800 ft above the field**, then follows its
SID and climbs to the initial level. Transfer it to Approach **once airborne**, no later than
when it leaves the CTR ([LOA](doc:loa) §6).

## 3. Arrivals step by step

### 3.1 Final and landing clearance

- The arrival comes from Approach with **Cleared approach**, at or before the **final fix** (1200 m
  before the threshold). On final it belongs to you even above 2000 ft.
- The pilots call for the landing clearance (**LAND**, yellow frame) 1500 m before the final fix and
  on final.
- **Cleared to land** must be given **no later than 400 m before the threshold**. Without it the
  aircraft **goes around**.
- Check that the runway is free: no aircraft lined up, crossing or vacating.

### 3.2 Vacating

**Vacate via** (optional, also before landing) names the taxiway where the aircraft leaves the
runway. The list shows the exits with their distance from the threshold. Without it the aircraft
takes the first exit towards the terminal.

### 3.3 Taxi to stand

After vacating, the aircraft waits for **Taxi to stand**. Choose a stand, or let the pilots take the
first free one. It crosses runways only with a **Cross runway** clearance, like departures.

## 4. Go-around

An arrival goes around when:

- it is more than 1700 ft above the field at the final fix (too high);
- it has no landing clearance 400 m before the threshold;
- you give **Go around** (for example the runway is not free).

It then flies the **go-around procedure** of the runway (`<ICAO>GA`, label `GA 27L`) and climbs to
**3000 ft**. The procedure goes straight ahead to the opposite half final, round the circuit and
back to the final fix. All its turns are 90°. Transfer it to Approach **as soon as it climbs out of
the CTR** ([LOA](doc:loa) §7). Diagram: [Airspace and navigation](doc:nav).

## 5. Uncontrolled ground traffic

When the Tower is closed, aircraft taxi, cross and take off on their own: at every runway they wait
a few seconds, then go when it is free. When you open the Tower, every aircraft on the ground is
yours from that moment, in the state it is in.
