-- police_system / modules/reports/server/templates/hu.lua
-- A jelentés vázlat mondatai magyarul (lásd en.lua).

REPORT_TEMPLATES = REPORT_TEMPLATES or {}

REPORT_TEMPLATES.hu = {
    types = { traffic_stop = "KÖZÚTI ELLENŐRZÉS", ped_stop = "IGAZOLTATÁS", pursuit = "ÜLDÖZÉS", arrest = "ELFOGÁS",
              backup = "ERŐSÍTÉS", other = "JELENTÉS" },
    intro = "{time}-kor a(z) {unit} egység ({members}) {what}.",
    what = {
        traffic_stop = "megállított egy {color}{model} járművet ({plate}), helyszín: {zone}",
        ped_stop = "igazoltatott egy gyalogost, {name}, helyszín: {zone}",
        pursuit = "üldözést kezdett: {name}, helyszín: {zone}",
        arrest = "elfogást hajtott végre, helyszín: {zone}",
        backup = "erősítésként vonult a(z) {for} egységhez",
        other = "szolgálatot teljesített",
    },
    lines = {
        query_person = "{time} {o} ellenőrizte {name} személyazonosságát.{warrant}",
        query_vehicle = "{time} {o} ellenőrizte a(z) {plate} rendszámú járművet ({model}).{flags}",
        test_bac = "{time} {name} alkoholszonda eredménye: {value} ezrelék.",
        test_drug = "{time} {name} drogteszt eredménye: {result}.",
        fine = "{time} {o} bírságot szabott ki {name} részére: {item} ({amount}).",
        warning = "{time} {o} figyelmeztette {name} személyt: {item}.",
        cuffed = "{time} {o} megbilincselte {name} személyt.",
        uncuffed = "{time} {o} levette {name} bilincsét.",
        escort = "{time} {o} kísérte {name} személyt.",
        placed = "{time} {name} a rendőrautóba került.",
        taken_out = "{time} {name} ki lett véve a rendőrautóból.",
        handover = "{time} {name} átadásra került: {station}.",
        released = "{time} {name} szabadon engedve.",
        order_out = "{time} A sofőrt kiszállították a járműből.",
        returned = "{time} {name} visszaszállt a járműbe.",
        pursuit_level = "{time} A gyanúsított körözési szintje {level}-re emelkedett.",
        evading = "{time} A gyanúsítottal megszakadt a vizuális kapcsolat.",
        caught = "{time} A gyanúsítottat elfogták.",
        lost = "{time} A gyanúsított elmenekült.",
        backup_arrived = "{time} {o} a helyszínre érkezett.",
        weapon_fired = "{time} {o} {count} lövést adott le.",
        weapon_drawn = "{time} {o} fegyvert vett elő.",
        surrendered = "{time} A gyanúsított megadta magát.",
        warrant_found = " Élő elfogató parancs.",
        flags_none = "",
        flag_stolen = " A jármű lopottként van nyilvántartva.",
        flag_inspection = " Műszaki: {value}.",
    },
    drug = { pos = "pozitív", neg = "negatív" },
}
