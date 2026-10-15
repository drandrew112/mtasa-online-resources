"""Dev helper: texts of the work_bloodtransport tutorial (namespace work_bloodtransport, en + hu).
usage: python tools/loc_tutorial.py"""
from locadd import add

c = "work_bloodtransport.tut.card."
sv = "work_bloodtransport.tut.server."
st = "work_bloodtransport.tut.steps."

en = {
    c + "title": "Blood transport tutorial",
    c + "skip": "Skip tutorial",
    c + "click_again_to_skip": "Click again to skip the tutorial",
    c + "press_for_cursor": "Press {cursor_key} for the cursor  ·  /{command} skip",

    sv + "already_running": "The tutorial is already running.",
    sv + "cannot_start_now": "You cannot start the tutorial now.",
    sv + "log_in_first": "Log in first.",
    sv + "system_not_running": "The blood transport system is not running, the tutorial cannot start.",
    sv + "end_service_first": "End your blood transport service first.",
    sv + "hands_not_free": "Put down what you are holding first.",
    sv + "could_not_start": "The tutorial could not be started.",
    sv + "task_failed": "The tutorial task could not be created, the tutorial ends.",
    sv + "completed": "Tutorial completed. Have a good service!",
    sv + "skipped": "Tutorial skipped. You can start it again with /{command}.",
    sv + "no_problem": "No problem. You can start the tutorial any time with /{command}.",
    sv + "signed_off_early": "You ended the service before the task was done. Sign on again in the vehicle.",
    sv + "ended_died": "The tutorial ended because you died.",
    sv + "vehicle_destroyed": "The tutorial vehicle was destroyed. Start again with /{command}.",
    sv + "not_running": "The tutorial is not running.",

    st + "label_panel": "Step 1/8 · Transport panel",
    st + "label_task": "Step 2/8 · The task",
    st + "label_box": "Step 3/8 · Blood box and inventory",
    st + "label_pickup": "Step 4/8 · Pickup",
    st + "label_drive": "Step 5/8 · On the road",
    st + "label_deliver": "Step 6/8 · Delivery",
    st + "label_signoff": "Step 7/8 · End of service",
    st + "label_done": "Step 8/8 · Finished",
    st + "next": "Next",
    st + "skip": "Skip",
    st + "start": "Start tutorial",
    st + "finish": "Finish",

    st + "offer": "Is this your first blood transport service? The tutorial shows the transport panel, a task, the blood box and the inventory, a pickup and a delivery (about 5 minutes, with a short drive).\n\nYou can start it later with /{command}.",

    st + "panel_small": "You are sitting in a blood transport vehicle in front of {from}.\n\nBottom right is the transport panel. Its small view shows whether you are in service and the cargo you are carrying.",
    st + "panel_open": "Press {panel} to open the big view of the panel.",
    st + "panel_sign_on": "This is the big view. A service starts with Sign on, in your own blood transport vehicle; your unit id is its plate.\n\nPress Sign on.",

    st + "task_header": "You are in service. The header shows your unit, the state and the service time; Wind down and End service are on the right.\n\nThe tiles count the delivered tasks, the cargo in transit, the waiting tasks and the pay so far.",
    st + "task_waiting": "The tasks are given out automatically. Wait a moment, one is coming.",
    st + "task_row": "A new task arrived (it also came as a notification). A task shows what to carry (blood product, blood group, units), its tag (URGENT, planned, lab sample...), where from and where to, and its number.\n\nWaiting means the cargo is still at the pickup place.",
    st + "task_route": "Press Route: the pickup place becomes your target on the radar and the map. After the pickup the route points to the destination. Pressing it again switches it off.",
    st + "task_more": "With more tasks, the arrows on the left set their order, and Hand over gives a waiting task to another transporter standing within 6 m (they have 20 seconds to accept).\n\nClose the big view with {panel}.",

    st + "box_get_out": "The cargo travels in the blood box of the vehicle. Get out of the vehicle.",
    st + "box_take": "Go to the rear of the vehicle: the menu of the transport box appears there. Choose Take the blood box.",
    st + "box_hud": "The box is in your hand. The list on the right shows what is in your hands and on your back, with the details of the box.\n\n{drop} puts down what you hold, {inventory} opens your inventory. You can never get into a vehicle with something in your hands.",
    st + "box_open_inventory": "Press {inventory} to open your inventory.",
    st + "box_slots": "At the top are your slots: left hand, right hand and back (only backpacks go on the back). The blood box is a container: it shows how many kg of its capacity are used.",
    st + "box_container": "Below is the content of the open container. Items move with drag and drop or a double click; Shift moves one piece, and dragging an item out of the window puts it down.\n\nClose the inventory with {inventory} or ESC.",

    st + "pickup_port": "The red B marker is the storage port of {from}, a few metres away. Stand in it with the box in your hand and press {port}.",
    st + "pickup_window": "This is the storage window of the port: you and your box on the left, the port on the right. The yellow bar tells you what to do here.",
    st + "pickup_drag": "Your cargo is marked « TAKE. Drag it into the box on the left, or double click it.",
    st + "pickup_done": "Picked up! The task is now in transit and the route points to the destination. Only your own cargo can be moved, and only the whole amount.\n\nClose the window.",

    st + "drive_put_back": "Put the box back: at the rear of the vehicle choose Put the blood box back.",
    st + "drive_get_in": "Get into the vehicle.",
    st + "drive_go": "Drive to {to}, following the route on the radar. Take your time: the vehicle cannot be damaged in the tutorial.",

    st + "deliver_take": "You have arrived. Get out and take the blood box from the rear of the vehicle.",
    st + "deliver_port": "The blue H marker is the storage port of the hospital. Stand in it and press {port}.",
    st + "deliver_drag": "Your cargo is marked PUT IN ». Drag it from the box onto the port on the right.",
    st + "deliver_done": "Delivered! Close the window and put the box back into the vehicle.",

    st + "signoff_open": "The task is done. Open the big view with {panel}.",
    st + "signoff_pay": "Delivered shows 1 now, and the pay grows with it. At the end of a service you get {base} if you delivered at least one task, {delivered} for every delivery, and {in_transit} for every cargo still on its way.",
    st + "signoff_types": "Other tasks: lab samples go from a hospital to a blood bank, urgent medicine between two hospitals, and the blood banks resupply the hospitals.\n\nWind down: you get no new tasks, but you finish the ones you have.",
    st + "signoff_press": "A service also ends when your work duty ends, the vehicle is lost or you die; the open tasks are cancelled then.\n\nPress End service. In the tutorial you get no money, only the receipt.",

    st + "receipt_total": "Total (not paid in the tutorial)",
    st + "done_title": "Tutorial complete",
    st + "done_text": "In short:\n1. Duty marker, then the vehicle marker, then {panel}: Sign on.\n2. Tasks come by themselves: Route to the pickup place.\n3. Box from the rear of the vehicle, {port} in the port, cargo into the box.\n4. Box back, drive, cargo onto the port at the destination.\n5. End service when you are done.\n\n/{command} starts this tutorial again.",

    st + "note_take_box": "Take the blood box out of the vehicle first.",
    st + "note_distance": "Distance: {m} m",
    st + "note_close_window": "Close the window.",
    st + "note_put_back": "Put the box back into the vehicle (rear of the vehicle).",
    st + "note_get_in": "Get into the blood transport vehicle.",
    st + "note_open_panel": "Press {panel} to open the big view again.",
    st + "note_open_inventory": "Open your inventory with {inventory}.",
    st + "note_open_port": "Open the storage window: stand in the marker and press {port}.",
}

hu = {
    c + "title": "Vérszállító oktatás",
    c + "skip": "Oktatás kihagyása",
    c + "click_again_to_skip": "Kattints újra a kihagyáshoz",
    c + "press_for_cursor": "{cursor_key}: kurzor  ·  /{command} skip",

    sv + "already_running": "Az oktatás már fut.",
    sv + "cannot_start_now": "Most nem indíthatod el az oktatást.",
    sv + "log_in_first": "Előbb jelentkezz be.",
    sv + "system_not_running": "A vérszállító rendszer nem fut, az oktatás nem indítható.",
    sv + "end_service_first": "Előbb fejezd be a vérszállító szolgálatodat.",
    sv + "hands_not_free": "Előbb tedd le, ami a kezedben van.",
    sv + "could_not_start": "Az oktatást nem sikerült elindítani.",
    sv + "task_failed": "Az oktató feladatot nem sikerült létrehozni, az oktatás véget ér.",
    sv + "completed": "Oktatás teljesítve. Jó szolgálatot!",
    sv + "skipped": "Oktatás kihagyva. Újra elindíthatod: /{command}.",
    sv + "no_problem": "Semmi gond. Az oktatást bármikor elindíthatod: /{command}.",
    sv + "signed_off_early": "A feladat előtt befejezted a szolgálatot. Lépj újra szolgálatba az autóban.",
    sv + "ended_died": "Az oktatás véget ért, mert meghaltál.",
    sv + "vehicle_destroyed": "Az oktató autó megsemmisült. Kezdd újra: /{command}.",
    sv + "not_running": "Az oktatás nem fut.",

    st + "label_panel": "1/8. lépés · Szállítási panel",
    st + "label_task": "2/8. lépés · A feladat",
    st + "label_box": "3/8. lépés · Vérdoboz és tárgyak",
    st + "label_pickup": "4/8. lépés · Felvétel",
    st + "label_drive": "5/8. lépés · Úton",
    st + "label_deliver": "6/8. lépés · Átadás",
    st + "label_signoff": "7/8. lépés · Szolgálat vége",
    st + "label_done": "8/8. lépés · Kész",
    st + "next": "Tovább",
    st + "skip": "Kihagyás",
    st + "start": "Oktatás indítása",
    st + "finish": "Kész",

    st + "offer": "Ez az első vérszállító szolgálatod? Az oktatás bemutatja a szállítási panelt, egy feladatot, a vérdobozt és a tárgykezelést, egy felvételt és egy átadást (kb. 5 perc, egy rövid vezetéssel).\n\nKésőbb is elindíthatod: /{command}.",

    st + "panel_small": "Egy vérszállító autóban ülsz a(z) {from} előtt.\n\nJobbra lent van a szállítási panel. A kis nézete mutatja, hogy szolgálatban vagy-e, és milyen szállítmány van nálad.",
    st + "panel_open": "Nyomd meg a(z) {panel} gombot a panel nagy nézetéhez.",
    st + "panel_sign_on": "Ez a nagy nézet. A szolgálat a Szolgálatba lépés gombbal indul, a saját vérszállító autódban; az egységazonosítód a rendszáma.\n\nNyomd meg a Szolgálatba lépés gombot.",

    st + "task_header": "Szolgálatban vagy. A fejlécben az egységed, az állapotod és a szolgálati idő látszik; jobbra a Befejezés és a Szolgálat vége gomb.\n\nA csempék az átadott feladatokat, a szállítás alatt lévő és a felvételre váró szállítmányokat, valamint az eddigi keresetet mutatják.",
    st + "task_waiting": "A feladatokat a rendszer magától osztja ki. Várj egy kicsit, már jön is egy.",
    st + "task_row": "Új feladatot kaptál (értesítésben is megjelent). A feladat mutatja, mit kell vinni (vérkészítmény, vércsoport, egység), a címkéjét (SÜRGŐS, tervezett, laborminta...), honnan hová, és a számát.\n\nA felvételre vár azt jelenti, hogy a szállítmány még a felvételi helyen van.",
    st + "task_route": "Nyomd meg az Útvonal gombot: a felvételi hely lesz a célpont a radaron és a térképen. Felvétel után az útvonal a célállomásra mutat. Újra megnyomva kikapcsol.",
    st + "task_more": "Több feladatnál a bal oldali nyilakkal állíthatod a sorrendet, az Átad gombbal pedig egy felvételre váró feladatot adhatsz át egy 6 méteren belül álló másik szállítónak (20 másodperce van elfogadni).\n\nZárd be a nagy nézetet: {panel}.",

    st + "box_get_out": "A szállítmány az autó vérdobozában utazik. Szállj ki az autóból.",
    st + "box_take": "Menj az autó hátuljához: ott jelenik meg a szállítódoboz menüje. Válaszd a Vérdoboz kivétele pontot.",
    st + "box_hud": "A doboz a kezedben van. A jobb oldali lista mutatja, mi van a kezedben és a hátadon, a doboz adataival együtt.\n\n{drop}: leteszed, ami a kezedben van, {inventory}: megnyitod a tárgyaidat. Ha valami a kezedben van, nem szállhatsz be járműbe.",
    st + "box_open_inventory": "Nyomd meg a(z) {inventory} gombot a tárgyaid megnyitásához.",
    st + "box_slots": "Fent vannak a helyeid: bal kéz, jobb kéz és hát (a hátadra csak hátizsák kerülhet). A vérdoboz tároló: mutatja, hány kg-ot használsz a kapacitásából.",
    st + "box_container": "Alatta a megnyitott tároló tartalma. A tárgyakat húzással vagy dupla kattintással mozgathatod; Shifttel egy darabot, és ha egy tárgyat kihúzol az ablakból, leteszed.\n\nZárd be a tárgyakat: {inventory} vagy ESC.",

    st + "pickup_port": "A piros B jelölő a(z) {from} tároló portája, néhány méterre tőled. Állj bele a dobozzal a kezedben, és nyomd meg a(z) {port} gombot.",
    st + "pickup_window": "Ez a porta tároló ablaka: bal oldalt te és a dobozod, jobb oldalt a porta. A sárga sáv mondja meg, mi a dolgod itt.",
    st + "pickup_drag": "A szállítmányod « ELVESZ jelölést kapott. Húzd a bal oldali dobozba, vagy kattints rá duplán.",
    st + "pickup_done": "Felvéve! A feladat most szállítás alatt van, az útvonal a célállomásra mutat. Csak a saját szállítmányodat mozgathatod, és csak egyben.\n\nZárd be az ablakot.",

    st + "drive_put_back": "Tedd vissza a dobozt: az autó hátuljánál válaszd a Vérdoboz betétele pontot.",
    st + "drive_get_in": "Szállj be az autóba.",
    st + "drive_go": "Vezess a(z) {to} intézményhez a radaron látható útvonal szerint. Nem kell sietned: az oktatásban az autó nem sérülhet.",

    st + "deliver_take": "Megérkeztél. Szállj ki, és vedd ki a vérdobozt az autó hátuljából.",
    st + "deliver_port": "A kék H jelölő a kórház tároló portája. Állj bele, és nyomd meg a(z) {port} gombot.",
    st + "deliver_drag": "A szállítmányod BETESZ » jelölést kapott. Húzd át a dobozból a jobb oldali portára.",
    st + "deliver_done": "Átadva! Zárd be az ablakot, és tedd vissza a dobozt az autóba.",

    st + "signoff_open": "A feladat kész. Nyisd meg a nagy nézetet: {panel}.",
    st + "signoff_pay": "Az Átadva most 1-et mutat, és vele nő a kereset is. A szolgálat végén {base} jár, ha legalább egy feladatot átadtál, minden átadásért {delivered}, és minden még úton lévő szállítmányért {in_transit}.",
    st + "signoff_types": "További feladatok: a laborminták kórházból vérellátóba mennek, a sürgős gyógyszer két kórház között, a vérellátók pedig feltöltik a kórházak készletét.\n\nBefejezés: nem kapsz új feladatot, de a meglévőket befejezed.",
    st + "signoff_press": "A szolgálat akkor is véget ér, ha lejár a munkád, elveszíted az autót vagy meghalsz; a nyitott feladatok ilyenkor törlődnek.\n\nNyomd meg a Szolgálat vége gombot. Az oktatásban nem kapsz pénzt, csak a számlát látod.",

    st + "receipt_total": "Összesen (az oktatásban nem fizetjük ki)",
    st + "done_title": "Oktatás teljesítve",
    st + "done_text": "Röviden:\n1. Munkajelölő, aztán a járműjelölő, majd {panel}: Szolgálatba lépés.\n2. A feladatok maguktól jönnek: Útvonal a felvételi helyhez.\n3. Doboz az autó hátuljából, {port} a portában, szállítmány a dobozba.\n4. Doboz vissza, vezetés, a célállomáson szállítmány a portára.\n5. Ha végeztél: Szolgálat vége.\n\n/{command}: az oktatás újraindítása.",

    st + "note_take_box": "Előbb vedd ki a vérdobozt az autóból.",
    st + "note_distance": "Távolság: {m} m",
    st + "note_close_window": "Zárd be az ablakot.",
    st + "note_put_back": "Tedd vissza a dobozt az autóba (az autó hátuljánál).",
    st + "note_get_in": "Szállj be a vérszállító autóba.",
    st + "note_open_panel": "Nyomd meg a(z) {panel} gombot a nagy nézethez.",
    st + "note_open_inventory": "Nyisd meg a tárgyaidat: {inventory}.",
    st + "note_open_port": "Nyisd meg a tároló ablakot: állj a jelölőbe, és nyomd meg a(z) {port} gombot.",
}

add("work_bloodtransport", en, hu)
