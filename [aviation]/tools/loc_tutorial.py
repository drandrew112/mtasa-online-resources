"""Dev helper: texts of the work_atc tutorial (namespace work_atc, en + hu).
Uses the catalog merger of [bloodtransport]/tools/locadd.py.
usage: python tools/loc_tutorial.py"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "[bloodtransport]", "tools"))
from locadd import add

c = "work_atc.tut.card."
sv = "work_atc.tut.server."
st = "work_atc.tut.steps."

en = {
    c + "title": "Air traffic control tutorial",
    c + "skip": "Skip tutorial",
    c + "click_again_to_skip": "Click again to skip the tutorial",
    c + "press_for_cursor": "Press {cursor_key} for the cursor  ·  /{command} skip",

    sv + "already_running": "The tutorial is already running.",
    sv + "cannot_start_now": "You cannot start the tutorial now.",
    sv + "log_in_first": "Log in first.",
    sv + "system_not_running": "The air traffic control system is not running, the tutorial cannot go on.",
    sv + "log_out_first": "Log out of your ATC position first.",
    sv + "could_not_start": "The tutorial could not be started.",
    sv + "aircraft_failed": "The tutorial aircraft could not be created, the tutorial ends.",
    sv + "aircraft_lost": "The tutorial aircraft was removed, a new one comes.",
    sv + "completed": "Tutorial completed. Have a good shift!",
    sv + "skipped": "Tutorial skipped. You can start it again with /{command}.",
    sv + "no_problem": "No problem. You can start the tutorial any time with /{command}.",
    sv + "logged_out_early": "You logged out before the end. Log in again at the console ({console}).",
    sv + "ended_died": "The tutorial ended because you died.",
    sv + "not_running": "The tutorial is not running.",

    st + "step_console": "Step 1/9 · The console",
    st + "step_scope": "Step 2/9 · The radar scope",
    st + "step_label": "Step 3/9 · Labels and the menu",
    st + "step_delivery": "Step 4/9 · Delivery",
    st + "step_ground": "Step 5/9 · Taxi",
    st + "step_air": "Step 6/9 · Take-off",
    st + "step_arrival": "Step 7/9 · Arrival",
    st + "step_alerts": "Step 8/9 · Alerts and pay",
    st + "step_done": "Step 9/9 · Finished",
    st + "next": "Next",
    st + "skip": "Skip",
    st + "start": "Start",
    st + "finish": "Finish",
    st + "offer": "Would you like a short tutorial? You will control a departure and an arrival as a tower controller, with nobody else's traffic around. It takes about 15 minutes, and you can skip it any time.\n\n/{command} starts it later.",

    st + "console_walk": "You are in the operations room of San Andreas Control. Every ATC position is opened here; the airport towers have no consoles.\n\nWalk into the blue marker of the {airport} consoles and press {console}.",
    st + "console_login": "The login window lists the positions of this console. You start as a tower controller ({position}): the tower controls the aircraft on the ground, on the runway and in the CTR around the airport.\n\nClick Log in.",

    st + "scope_intro": "This is the radar scope of {position}. You look at the airspace from above: the CTR of {airport} around the runways, the TMA of the approach around it, fixes (triangles), the runways, and later the aircraft.\n\nIn the tutorial only your own two aircraft fly here.",
    st + "scope_topbar": "The top bar shows your position and the runways in use: ARR = landing runway, DEP = take-off runway (now {arr_rwy} / {dep_rwy}), then the wind (from where, knots). The runways follow the wind.",
    st + "scope_tools": "AT shows / hides the names of the airspaces, FIXL the fix names. V- / V+ (or the keys 0-5) set the length of the speed vector ahead of every airborne aircraft.",
    st + "scope_view": "Mouse wheel: zoom where the cursor is. Right mouse button held: move the map. Taxiways, stands and ground traffic appear only when you zoom in. Distances are in nautical miles (scale bar), altitudes in feet, speeds in knots.",
    st + "scope_list": "On the right are the Departures and Arrivals of your airport. Your aircraft are blue. When an aircraft asks you for something, its ALT column shows REQ in yellow. Clicking a row centres the map on it.",
    st + "scope_buttons": "List: on/off hides the lists, Reset view brings the map back. Hide closes the scope but you stay logged in ({console} at the console shows it again). Logout ends the session and pays you (not now, it comes at the end).",

    st + "label_wait": "A departure ({dep}) is coming to a stand of {airport}...",
    st + "label_ground": "{dep} is at its stand. A ground label shows the callsign, the speed and the squawk code, then the type and the wake category. The colour tells departure or arrival.\n\nA yellow frame means it asks you for something now.",
    st + "label_air": "Airborne labels are longer: callsign + controller, type / wake; altitude in hundreds of feet (045 = 4500 ft), speed, destination; the cleared level (when set); the waypoint or heading; squawk (on hover) and vertical speed. A grey label is not yours.\n\nYou can drag a label with the left mouse button; right click on it shows its route.",
    st + "label_menu": "Click the label of {dep}: the command menu opens.",
    st + "label_menu_info": "At the top is the flight: type, route, procedure, who controls it. Below are the commands in groups. On the ground the whole flow is listed in order: only the step it is at now can be clicked, the rest is grey. Yellow = what the pilots ask for.",

    st + "delivery_ifr": "First the IFR clearance: in the menu choose IFR clearance >, then the departure procedure (SID). The yellow one is suggested: it starts the filed route from the runway in use. Then the initial level: 3000 ft is the standard.",
    st + "delivery_push": "Cleared! The label now asks for PUSH. Open the menu again and choose Pushback approved.",
    st + "delivery_pushing": "{dep} is pushed back tail first onto the taxiway, nose towards the runway. When it stops, it asks for taxi (TAXI).",

    st + "ground_taxi": "Choose Taxi > and the runway: the one in use ({dep_rwy}) is marked. The pilots find the way on the taxiways by themselves.",
    st + "ground_rules": "While taxiing: aircraft keep 60 m behind each other in a queue, and nobody enters a runway without your clearance: they stop before it (holding short) and ask.\n\nTwo aircraft facing each other on a taxiway is a separation loss (a fine) - plan the taxi routes.",
    st + "ground_takeoff": "It holds short and asks (yellow in the menu): CROSS = Cross runway; BKTRK = Backtrack runway (it rolls to the threshold on the runway and turns round); T/O = Line up and wait or Cleared for take-off. Take-off clearance is accepted only at the runway.\n\nClear {dep} for take-off.",

    st + "air_wait": "{dep} is rolling. After take-off it flies the runway heading up to 800 ft above the field, then its SID, and climbs to the initial level.",
    st + "air_leave": "Your sector is the CTR of {airport}: the ground, the runway and a strip of air around it. The tower does not give a departure levels or headings: it got its initial level with the IFR clearance, and only approach (APP) climbs it further. When {dep} leaves the CTR, it belongs to approach; approach is closed now, so the pilots fly their flight plan alone and the label turns grey.",

    st + "arr_wait": "An arrival ({arr}) is coming on the final of runway {arr_rwy}...",
    st + "arr_land": "{arr} comes from approach (APP), already cleared for the approach: it flies to the final fix and on to the runway. Its label is grey until it reaches your CTR / the final; then it is yours and asks for the landing clearance (LAND, yellow). Give Cleared to land before it is 400 m from the threshold, otherwise it goes around.",
    st + "arr_vacate": "With Vacate via > you can name the runway exit; without it the pilots take the first one towards the terminal. Go around sends it round again if the runway is not free.\n\nWait for the landing.",
    st + "arr_taxi": "{arr} has landed. Off the runway it asks for taxi: Taxi to stand > any free stand, or a named one.",
    st + "arr_parked": "{arr} taxies to the stand. Wait until it parks.",

    st + "alerts_emrg": "The red EMRG above the label is an alert: {arr} squawks 7700, an emergency. Others: COMS = 7600 radio failure, DUPE = two aircraft with the same squawk, STCA = separation loss, RAM = the aircraft left its route.",
    st + "alerts_fines": "Separation losses are fined, but only in your own sector: two ground aircraft head-on {gnd}; closer than 0.1 nm and 1000 ft in a TMA {tma}, in the CTA {cta}. Fines are taken from your pay, even when the total is negative.",
    st + "alerts_pay": "You are paid when you log out: {per_action} for every accepted command, more the longer you stay (+{bonus}% per minute, at most x{max}), and {per_aircraft} for every aircraft you controlled. Every command also gives work XP.\n\nYou start as a tower controller; approach (APP) comes at level {app}, radar (centre) at level {radar}.",
    st + "alerts_logout": "Press Logout in the top right corner. In the tutorial nothing is paid, you only see the receipt.",

    st + "receipt_total": "Total (not paid in the tutorial)",
    st + "done_title": "Tutorial completed",
    st + "done_text": "In short:\n1. Go on duty, then the console in the SA Control room: {console}, Log in.\n2. Departures: IFR clearance, Pushback, Taxi, Take-off; leaving the CTR they go to approach.\n3. Arrivals (from approach): Cleared to land, Taxi to stand.\n4. Yellow = they ask, red = alert. Watch the separation.\n5. Logout pays.\n\nRead the documents on sanandreascontrol.eu (in-game browser): NAV, SW, OPS, then LOA.\n/{command}: the tutorial again.",

    st + "note_open_console": "Stand in the console marker and press {console}.",
    st + "note_open_scope": "The scope is hidden: press {console} at the console marker.",
    st + "note_holding": "Holding short of {rwy}, asks for {req}.",
    st + "note_fast": "Fast forward x{scale}: nobody is waiting for you.",
    st + "note_go_around": "It went around: it flies the go-around procedure (GA) up to 3000 ft and comes back for a new approach. Clear it again (approach, then landing).",
    st + "note_phase": "Now: {phase}",
}

hu = {
    c + "title": "Légiforgalmi irányítás oktatás",
    c + "skip": "Oktatás kihagyása",
    c + "click_again_to_skip": "Kattints újra az oktatás kihagyásához",
    c + "press_for_cursor": "{cursor_key}: kurzor  ·  /{command} skip",

    sv + "already_running": "Az oktatás már fut.",
    sv + "cannot_start_now": "Most nem indíthatod el az oktatást.",
    sv + "log_in_first": "Előbb jelentkezz be.",
    sv + "system_not_running": "A légiforgalmi irányító rendszer nem fut, az oktatás nem folytatható.",
    sv + "log_out_first": "Előbb jelentkezz ki az ATC pozíciódról.",
    sv + "could_not_start": "Az oktatást nem sikerült elindítani.",
    sv + "aircraft_failed": "Az oktatás repülőgépét nem sikerült létrehozni, az oktatás véget ér.",
    sv + "aircraft_lost": "Az oktatás repülőgépe eltűnt, jön egy új.",
    sv + "completed": "Oktatás teljesítve. Jó szolgálatot!",
    sv + "skipped": "Oktatás kihagyva. A /{command} paranccsal bármikor újraindíthatod.",
    sv + "no_problem": "Rendben. Az oktatást bármikor elindíthatod a /{command} paranccsal.",
    sv + "logged_out_early": "Kijelentkeztél a végé előtt. Jelentkezz be újra a konzolnál ({console}).",
    sv + "ended_died": "Az oktatás véget ért, mert meghaltál.",
    sv + "not_running": "Az oktatás nem fut.",

    st + "step_console": "1/9. lépés · A konzol",
    st + "step_scope": "2/9. lépés · A radarkép",
    st + "step_label": "3/9. lépés · Címkék és a menü",
    st + "step_delivery": "4/9. lépés · Engedély (delivery)",
    st + "step_ground": "5/9. lépés · Gurulás",
    st + "step_air": "6/9. lépés · Felszállás",
    st + "step_arrival": "7/9. lépés · Érkezés",
    st + "step_alerts": "8/9. lépés · Riasztások és fizetés",
    st + "step_done": "9/9. lépés · Kész",
    st + "next": "Tovább",
    st + "skip": "Kihagyom",
    st + "start": "Indítás",
    st + "finish": "Befejezés",
    st + "offer": "Kérsz egy rövid oktatást? Toronyirányítóként egy induló és egy érkező gépet irányítasz, más forgalom nélkül. Kb. 15 perc, és bármikor kihagyhatod.\n\nKésőbb a /{command} paranccsal indíthatod.",

    st + "console_walk": "A San Andreas Control irányítótermében vagy. Minden ATC pozíciót itt nyitnak meg; a repülőterek tornyaiban nincs konzol.\n\nÁllj be a(z) {airport} konzolok kék jelölőjébe, és nyomd meg a(z) {console} gombot.",
    st + "console_login": "A bejelentkező ablak a konzol pozícióit mutatja. Toronyirányítóként kezdesz ({position}): a torony irányítja a földön, a futópályán és a repülőtér körüli CTR-ben lévő gépeket.\n\nKattints a Log in gombra.",

    st + "scope_intro": "Ez a(z) {position} radarképe. Felülről látod a légteret: a(z) {airport} CTR-jét a futópályák körül, körülötte a bevezető irányítás TMA-ját, a fixeket (háromszögek), a futópályákat, később pedig a gépeket.\n\nAz oktatásban csak a saját két géped repül itt.",
    st + "scope_topbar": "A felső sávon a pozíciód és a használt futópályák: ARR = leszálló pálya, DEP = felszálló pálya (most {arr_rwy} / {dep_rwy}), utána a szél (honnan fúj, csomó). A pályák a szélhez igazodnak.",
    st + "scope_tools": "Az AT a légterek neveit, a FIXL a fixek neveit kapcsolja. A V- / V+ (vagy a 0-5 gombok) a repülő gépek előtti sebességvektor hosszát állítják.",
    st + "scope_view": "Egérgörgő: nagyítás a kurzornál. Nyomva tartott jobb egérgomb: a térkép mozgatása. A gurulóutak, az állóhelyek és a földi forgalom csak ráközelítve látszanak. A távolság tengeri mérföld (lépték), a magasság láb, a sebesség csomó.",
    st + "scope_list": "Jobb oldalon a repülőtered induló (Departures) és érkező (Arrivals) gépei. A tieid kékek. Ha egy gép kér tőled valamit, az ALT oszlopában sárga REQ áll. Egy sorra kattintva a térkép rá áll.",
    st + "scope_buttons": "A List: on/off elrejti a listákat, a Reset view visszahozza a térképet. A Hide bezárja a radarképet, de bejelentkezve maradsz (a konzolnál {console} újra megmutatja). A Logout befejezi a munkamenetet és kifizet (most nem, a végén jön).",

    st + "label_wait": "Egy induló gép ({dep}) érkezik a(z) {airport} egyik állóhelyére...",
    st + "label_ground": "A(z) {dep} az állóhelyén áll. A földi címkén a hívójel, a sebesség és a transzponderkód (squawk), alatta a típus és a turbulencia-kategória. A színe mutatja, hogy induló vagy érkező.\n\nA sárga keret azt jelenti, hogy most kér tőled valamit.",
    st + "label_air": "A levegőben lévő gépek címkéje hosszabb: hívójel + irányító, típus / kategória; magasság száz lábban (045 = 4500 láb), sebesség, cél; az engedélyezett szint (ha van); a fix vagy az irány; squawk (rámutatáskor) és függőleges sebesség. A szürke címke nem a tiéd.\n\nA címkét bal egérgombbal húzhatod; jobb kattintás rá mutatja az útvonalát.",
    st + "label_menu": "Kattints a(z) {dep} címkéjére: megnyílik a parancsmenü.",
    st + "label_menu_info": "Felül a járat adatai: típus, útvonal, eljárás, ki irányítja. Alatta csoportokban a parancsok. A földön a teljes folyamat sorrendben látszik: csak az aktuális lépés kattintható, a többi szürke. Sárga = amit a pilóták kérnek.",

    st + "delivery_ifr": "Először az IFR engedély: a menüben válaszd az IFR clearance > pontot, aztán az indulási eljárást (SID). A sárga a javasolt: a használt pályáról a bejelentett útvonalra vezet. Végül a kezdeti szint: 3000 láb a szokásos.",
    st + "delivery_push": "Megvan! A címke most PUSH-t kér. Nyisd meg újra a menüt, és válaszd a Pushback approved pontot.",
    st + "delivery_pushing": "A(z) {dep}-t farral előre kitolják a gurulóútra, orral a pálya felé. Ha megállt, gurulást kér (TAXI).",

    st + "ground_taxi": "Válaszd a Taxi > pontot és a pályát: a használt ({dep_rwy}) meg van jelölve. A gurulóutakon a pilóták maguk találják meg az utat.",
    st + "ground_rules": "Gurulás közben: a gépek 60 m-re sorban állnak egymás mögött, és engedélyed nélkül senki nem lép pályára: előtte megállnak (holding short) és kérnek.\n\nKét egymással szembe guruló gép elkülönítés-sértés (bírság) - tervezd meg a gurulási útvonalakat.",
    st + "ground_takeoff": "Megállt a pálya előtt és kér (sárga a menüben): CROSS = Cross runway; BKTRK = Backtrack runway (a pályán a küszöbig gurul és megfordul); T/O = Line up and wait vagy Cleared for take-off. Felszállási engedélyt csak a pályánál fogad el.\n\nAdj felszállási engedélyt a(z) {dep}-nak.",

    st + "air_wait": "A(z) {dep} nekifut. Felszállás után pályairányban emelkedik 800 lábig a repülőtér fölé, aztán a SID-jét repüli, és a kezdeti szintre emelkedik.",
    st + "air_leave": "A szektorod a(z) {airport} CTR-je: a föld, a pálya és körülötte egy sáv levegő. A torony nem ad az induló gépnek szintet vagy irányt: a kezdeti szintet az IFR engedéllyel megkapta, tovább csak a bevezető irányítás (APP) emelheti. Amikor a(z) {dep} elhagyja a CTR-t, a bevezető irányításé; az most zárva van, ezért a pilóták egyedül repülik a tervüket, és a címke szürke lesz.",

    st + "arr_wait": "Egy érkező gép ({arr}) jön a(z) {arr_rwy} pálya finalján...",
    st + "arr_land": "A(z) {arr} a bevezető irányítástól (APP) jön, már megközelítési engedéllyel: a final fixre, onnan a pályára repül. A címkéje szürke, amíg el nem éri a CTR-edet / a finalt; onnan a tiéd, és leszállási engedélyt kér (LAND, sárga). Add meg a Cleared to land paranccsal, mielőtt 400 m-re ér a küszöbtől, különben átstartol.",
    st + "arr_vacate": "A Vacate via > ponttal megadhatod a lekanyarodót; nélküle a pilóták az első, terminál felé eső kijáratot választják. A Go around újra körbeküldi, ha a pálya nem szabad.\n\nVárd meg a leszállást.",
    st + "arr_taxi": "A(z) {arr} leszállt. A pályát elhagyva gurulást kér: Taxi to stand > bármelyik szabad vagy egy megnevezett állóhely.",
    st + "arr_parked": "A(z) {arr} az állóhelyre gurul. Várd meg, amíg leparkol.",

    st + "alerts_emrg": "A címke fölötti piros EMRG egy riasztás: a(z) {arr} 7700-at squawkol, vészhelyzet. A többi: COMS = 7600 rádióhiba, DUPE = két gép azonos kóddal, STCA = elkülönítés-sértés, RAM = a gép letért az útvonaláról.",
    st + "alerts_fines": "Az elkülönítés-sértésért bírság jár, de csak a saját szektorodban: két szembe guruló gép a földön {gnd}; 0,1 tengeri mérföldnél és 1000 lábnál közelebb a TMA-ban {tma}, a CTA-ban {cta}. A bírság a fizetésedből megy le, akkor is, ha az összeg negatív lesz.",
    st + "alerts_pay": "Kijelentkezéskor fizetünk: minden elfogadott parancsért {per_action}, minél tovább maradsz, annál többet (+{bonus}% percenként, legfeljebb x{max}), és minden irányított gépért {per_aircraft}. Minden parancs munka XP-t is ad.\n\nToronyirányítóként kezdesz; a bevezető irányítás (APP) a(z) {app}. szinten, a radar (körzeti) a(z) {radar}. szinten jön.",
    st + "alerts_logout": "Nyomd meg a jobb felső sarokban a Logout gombot. Az oktatásban nem fizetünk, csak a számlát látod.",

    st + "receipt_total": "Összesen (az oktatásban nem fizetjük ki)",
    st + "done_title": "Oktatás teljesítve",
    st + "done_text": "Röviden:\n1. Szolgálatba lépés, aztán a konzol az SA Control teremben: {console}, Log in.\n2. Induló gépek: IFR clearance, Pushback, Taxi, Take-off; a CTR-ből kilépve az approaché.\n3. Érkező gépek (az approachtól): Cleared to land, Taxi to stand.\n4. Sárga = kérnek, piros = riasztás. Figyelj az elkülönítésre.\n5. A Logout fizet.\n\nOlvasd el a dokumentumokat a sanandreascontrol.eu oldalon (játékbeli böngésző): NAV, SW, OPS, aztán LOA.\n/{command}: az oktatás újra.",

    st + "note_open_console": "Állj a konzol jelölőjébe, és nyomd meg a(z) {console} gombot.",
    st + "note_open_scope": "A radarkép rejtve van: a konzolnál nyomd meg a(z) {console} gombot.",
    st + "note_holding": "A(z) {rwy} pálya előtt vár, {req}-t kér.",
    st + "note_fast": "Gyorsítás x{scale}: senki nem vár rád.",
    st + "note_go_around": "Átstartolt: az átstartolási eljárást (GA) repüli 3000 lábig, aztán visszajön egy új megközelítésre. Adj neki újra engedélyt (megközelítés, aztán leszállás).",
    st + "note_phase": "Most: {phase}",
}

add("work_atc", en, hu)
