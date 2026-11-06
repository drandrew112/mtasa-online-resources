-- ER intervention codes (plan: Beavatkozás-kódok, 147 codes). HK-<group><number>: points, the lowest rank that may
-- perform it, the per-case limit (points stop after it). Names: v_locals med_docs.code.hk_<code>.
-- Generated from the plan artifact table; edit here.

ERC.CODES = {
    ["HK-A01"] = { points = 4, rank = "nurse", limit = 1 },  -- Triage besorolás
    ["HK-A02"] = { points = 2, rank = "nurse", limit = 1 },  -- Kórházi felvétel (regisztráció)
    ["HK-A03"] = { points = 1, rank = "resident", limit = 1 },  -- Kezelőként átvétel
    ["HK-A04"] = { points = 3, rank = "nurse", limit = 1 },  -- Mentős beteg átvétele
    ["HK-A05"] = { points = 6, rank = "resident", limit = 1 },  -- Ambuláns lap lezárása
    ["HK-A06"] = { points = 5, rank = "resident", limit = 1 },  -- Osztályos felvétel
    ["HK-A07"] = { points = 8, rank = "physician", limit = 1 },  -- Intenzív osztályos felvétel
    ["HK-A08"] = { points = 6, rank = "physician", limit = 1 },  -- Áthelyezés szervezése, S1
    ["HK-A09"] = { points = 4, rank = "resident", limit = 1 },  -- Áthelyezés szervezése, S2
    ["HK-A10"] = { points = 3, rank = "resident", limit = 1 },  -- Hazabocsátás
    ["HK-A11"] = { points = 4, rank = "physician", limit = 1 },  -- Exitus rögzítése
    ["HK-A12"] = { points = 3, rank = "nurse", limit = 1 },  -- Halott leadása
    ["HK-A13"] = { points = 2, rank = "resident", limit = 1 },  -- Konzílium kérése (NPC)
    ["HK-A14"] = { points = 3, rank = "nurse", limit = 1 },  -- Beteg visszavétele az elfekvőből
    ["HK-A15"] = { points = 4, rank = "physician", limit = 1 },  -- Halottvizsgálati bizonyítvány
    ["HK-A16"] = { points = 3, rank = "nurse", limit = 1 },  -- Beteg átadása mentőnek (áthelyezés)
    ["HK-V01"] = { points = 4, rank = "nurse", limit = 2 },  -- Primer vizsgálat (ABCDE)
    ["HK-V02"] = { points = 8, rank = "resident", limit = 2 },  -- Teljes fizikális vizsgálat (fejtől talpig)
    ["HK-V03"] = { points = 3, rank = "nurse", limit = 2 },  -- Kikérdezés, anamnézis
    ["HK-V04"] = { points = 3, rank = "nurse", limit = 2 },  -- Neurológiai vizsgálat (GCS, pupillák)
    ["HK-V05"] = { points = 5, rank = "resident", limit = 2 },  -- NIHSS
    ["HK-V06"] = { points = 1, rank = "nurse", limit = 2 },  -- Fájdalomskála (NRS)
    ["HK-V07"] = { points = 2, rank = "nurse", limit = 2 },  -- Vércukormérés
    ["HK-V08"] = { points = 1, rank = "nurse", limit = 2 },  -- Testhőmérséklet
    ["HK-V09"] = { points = 2, rank = "nurse", limit = 2 },  -- Vérnyomás mindkét karon
    ["HK-V10"] = { points = 3, rank = "resident", limit = 2 },  -- Has vizsgálata
    ["HK-V11"] = { points = 3, rank = "resident", limit = 2 },  -- Mellkas vizsgálata (hallgatózás, kopogtatás)
    ["HK-V12"] = { points = 2, rank = "nurse", limit = 2 },  -- Végtag vizsgálata (keringés, mozgás, érzés)
    ["HK-V13"] = { points = 3, rank = "resident", limit = 2 },  -- Gerinc vizsgálata
    ["HK-V14"] = { points = 3, rank = "resident", limit = 2 },  -- Toxidrom felmérése
    ["HK-V15"] = { points = 4, rank = "nurse", limit = 2 },  -- Megfigyelés (időzített kontrollok)
    ["HK-V16"] = { points = 2, rank = "nurse", limit = 2 },  -- BE-FAST stroke-szűrés
    ["HK-L01"] = { points = 4, rank = "nurse", limit = 4 },  -- Vénás vérvétel
    ["HK-L02"] = { points = 3, rank = "resident", limit = 3 },  -- Kis labor (vérkép, ionok, vesefunkció)
    ["HK-L03"] = { points = 4, rank = "resident", limit = 3 },  -- Trauma panel
    ["HK-L04"] = { points = 4, rank = "resident", limit = 3 },  -- Kardiális panel (troponin, CK-MB)
    ["HK-L05"] = { points = 3, rank = "resident", limit = 3 },  -- Koaguláció (INR, APTI, fibrinogén)
    ["HK-L06"] = { points = 5, rank = "resident", limit = 3 },  -- Artériás vérgáz
    ["HK-L07"] = { points = 4, rank = "resident", limit = 3 },  -- Toxikológia
    ["HK-L08"] = { points = 3, rank = "resident", limit = 3 },  -- Vércsoport és ellenanyagszűrés
    ["HK-L09"] = { points = 3, rank = "resident", limit = 3 },  -- Keresztpróba
    ["HK-L10"] = { points = 3, rank = "nurse", limit = 3 },  -- Hemokultúra
    ["HK-L11"] = { points = 2, rank = "nurse", limit = 3 },  -- Vizeletvizsgálat
    ["HK-L12"] = { points = 3, rank = "resident", limit = 3 },  -- Gyulladásos panel (CRP, PCT, laktát)
    ["HK-L13"] = { points = 2, rank = "nurse", limit = 3 },  -- Terhességi teszt
    ["HK-L14"] = { points = 2, rank = "resident", limit = 3 },  -- Véralkohol
    ["HK-L16"] = { points = 8, rank = "resident", limit = 2 },  -- Teljes labor (minden panel)
    ["HK-L15"] = { points = 2, rank = "resident", limit = 3 },  -- D-dimer
    ["HK-K01"] = { points = 5, rank = "nurse", limit = 3 },  -- Röntgen: mellkas
    ["HK-K02"] = { points = 4, rank = "nurse", limit = 3 },  -- Röntgen: felső végtag
    ["HK-K03"] = { points = 4, rank = "nurse", limit = 3 },  -- Röntgen: alsó végtag
    ["HK-K04"] = { points = 5, rank = "nurse", limit = 3 },  -- Röntgen: medence, csípő
    ["HK-K05"] = { points = 5, rank = "nurse", limit = 3 },  -- Röntgen: gerinc
    ["HK-K06"] = { points = 3, rank = "nurse", limit = 3 },  -- Kontroll röntgen gipszben
    ["HK-K10"] = { points = 8, rank = "nurse", limit = 2 },  -- CT koponya natív
    ["HK-K11"] = { points = 7, rank = "nurse", limit = 2 },  -- CT nyaki gerinc
    ["HK-K12"] = { points = 8, rank = "nurse", limit = 2 },  -- CT mellkas
    ["HK-K13"] = { points = 9, rank = "nurse", limit = 2 },  -- CT has-kismedence
    ["HK-K14"] = { points = 9, rank = "nurse", limit = 2 },  -- CT angiográfia
    ["HK-K15"] = { points = 14, rank = "nurse", limit = 2 },  -- Politrauma teljes test CT
    ["HK-K20"] = { points = 8, rank = "resident", limit = 3 },  -- FAST ultrahang
    ["HK-K21"] = { points = 4, rank = "resident", limit = 3 },  -- eFAST tüdő
    ["HK-K22"] = { points = 4, rank = "resident", limit = 3 },  -- Ultrahang: szívburok (célzott)
    ["HK-K23"] = { points = 3, rank = "resident", limit = 3 },  -- Képlelet megírása (orvosi)
    ["HK-E01"] = { points = 5, rank = "nurse", limit = 3 },  -- 12-elvezetéses EKG
    ["HK-E02"] = { points = 2, rank = "nurse", limit = 3 },  -- Folyamatos monitorozás
    ["HK-E03"] = { points = 6, rank = "nurse", limit = 3 },  -- Defibrillálás
    ["HK-E04"] = { points = 8, rank = "physician", limit = 3 },  -- Szinkron kardioverzió
    ["HK-E05"] = { points = 8, rank = "physician", limit = 3 },  -- Külső pacing
    ["HK-E06"] = { points = 3, rank = "resident", limit = 3 },  -- EKG értelmezése (orvosi lelet)
    ["HK-E07"] = { points = 2, rank = "resident", limit = 3 },  -- Vagus-manőver
    ["HK-R01"] = { points = 8, rank = "nurse", limit = 4 },  -- Kardiopulmonális reanimáció
    ["HK-R02"] = { points = 8, rank = "physician", limit = 4 },  -- ROSC utáni ellátás
    ["HK-R03"] = { points = 2, rank = "nurse", limit = 4 },  -- Oxigénterápia
    ["HK-R04"] = { points = 6, rank = "resident", limit = 4 },  -- Szupraglottikus légút
    ["HK-R05"] = { points = 15, rank = "physician", limit = 4 },  -- RSI és intubáció
    ["HK-R06"] = { points = 8, rank = "physician", limit = 4 },  -- Gépi lélegeztetés indítása
    ["HK-R07"] = { points = 10, rank = "resident", limit = 4 },  -- Tűdekompresszió
    ["HK-R08"] = { points = 15, rank = "physician", limit = 4 },  -- Mellkasi drain
    ["HK-R09"] = { points = 2, rank = "nurse", limit = 4 },  -- Leszívás
    ["HK-R10"] = { points = 3, rank = "nurse", limit = 4 },  -- Inhalációs kezelés
    ["HK-R11"] = { points = 6, rank = "resident", limit = 4 },  -- Noninvazív lélegeztetés (CPAP)
    ["HK-R12"] = { points = 15, rank = "physician", limit = 4 },  -- Pericardiocentesis
    ["HK-C01"] = { points = 3, rank = "nurse", limit = 4 },  -- Perifériás vénabiztosítás
    ["HK-C02"] = { points = 6, rank = "resident", limit = 4 },  -- Intraosszeális kanül
    ["HK-C03"] = { points = 2, rank = "nurse", limit = 4 },  -- Infúzió bekötése
    ["HK-C04"] = { points = 3, rank = "nurse", limit = 4 },  -- Perfúzor indítása
    ["HK-C05"] = { points = 5, rank = "nurse", limit = 4 },  -- Transzfúzió (egységenként)
    ["HK-C06"] = { points = 12, rank = "physician", limit = 4 },  -- Masszív transzfúziós protokoll
    ["HK-C07"] = { points = 5, rank = "nurse", limit = 4 },  -- Medenceöv
    ["HK-C08"] = { points = 4, rank = "nurse", limit = 4 },  -- Vérzéscsillapítás (nyomókötés, érszorító)
    ["HK-C09"] = { points = 8, rank = "physician", limit = 4 },  -- Artériás kanül
    ["HK-C10"] = { points = 12, rank = "physician", limit = 4 },  -- Centrális véna
    ["HK-G01"] = { points = 2, rank = "nurse", limit = 4 },  -- Gyógyszer iv.
    ["HK-G02"] = { points = 2, rank = "nurse", limit = 4 },  -- Gyógyszer im. / sc.
    ["HK-G03"] = { points = 1, rank = "nurse", limit = 4 },  -- Gyógyszer po. / sl.
    ["HK-G04"] = { points = 3, rank = "resident", limit = 4 },  -- Fájdalomcsillapítás titrálva
    ["HK-G05"] = { points = 6, rank = "physician", limit = 4 },  -- Szedáció
    ["HK-G06"] = { points = 6, rank = "resident", limit = 4 },  -- Antidótum beadása
    ["HK-G07"] = { points = 4, rank = "nurse", limit = 4 },  -- Aktív szén
    ["HK-G08"] = { points = 20, rank = "physician", limit = 4 },  -- Trombolízis (stroke)
    ["HK-G09"] = { points = 18, rank = "physician", limit = 4 },  -- Trombolízis (STEMI)
    ["HK-G10"] = { points = 4, rank = "resident", limit = 4 },  -- Antibiotikum 1 órán belül (szepszis)
    ["HK-G11"] = { points = 6, rank = "resident", limit = 4 },  -- Inzulin-perfúzor (DKA)
    ["HK-G12"] = { points = 8, rank = "physician", limit = 4 },  -- Vazopresszor-perfúzor
    ["HK-G13"] = { points = 2, rank = "nurse", limit = 4 },  -- Tetanusz-profilaxis
    ["HK-G14"] = { points = 5, rank = "resident", limit = 4 },  -- Kalcium / bikarbonát (hyperkalaemia, TCA)
    ["HK-G15"] = { points = 2, rank = "nurse", limit = 4 },  -- Nitrát sublingualisan
    ["HK-S01"] = { points = 5, rank = "nurse", limit = 4 },  -- Sebtisztítás, irrigálás
    ["HK-S02"] = { points = 2, rank = "nurse", limit = 4 },  -- Fertőtlenítés
    ["HK-S03"] = { points = 3, rank = "resident", limit = 4 },  -- Helyi érzéstelenítés
    ["HK-S04"] = { points = 6, rank = "resident", limit = 4 },  -- Sebvarrás, egyszerű (5 cm alatt)
    ["HK-S05"] = { points = 10, rank = "resident", limit = 4 },  -- Sebvarrás, összetett
    ["HK-S06"] = { points = 2, rank = "nurse", limit = 4 },  -- Végleges kötés
    ["HK-S07"] = { points = 5, rank = "nurse", limit = 4 },  -- Égési kötés
    ["HK-S08"] = { points = 10, rank = "resident", limit = 4 },  -- Zárt repozíció
    ["HK-S09"] = { points = 6, rank = "nurse", limit = 4 },  -- Gipszsín
    ["HK-S10"] = { points = 8, rank = "nurse", limit = 4 },  -- Körkörös gipsz
    ["HK-S11"] = { points = 10, rank = "resident", limit = 4 },  -- Luxáció repozíciója
    ["HK-S12"] = { points = 6, rank = "resident", limit = 4 },  -- Idegentest eltávolítása
    ["HK-S13"] = { points = 3, rank = "nurse", limit = 4 },  -- Rögzítés (sín, nyakrögzítő)
    ["HK-S14"] = { points = 2, rank = "nurse", limit = 4 },  -- Kötéscsere
    ["HK-O01"] = { points = 6, rank = "physician", limit = 1 },  -- Átadás a műtőnek
    ["HK-O10"] = { points = 30, rank = "physician", limit = 1 },  -- Splenectomia
    ["HK-O11"] = { points = 32, rank = "physician", limit = 1 },  -- Laparotomia, bélvarrat
    ["HK-O12"] = { points = 36, rank = "physician", limit = 1 },  -- Máj sebellátás, packing
    ["HK-O13"] = { points = 24, rank = "physician", limit = 1 },  -- Appendectomia
    ["HK-O14"] = { points = 40, rank = "physician", limit = 1 },  -- Craniotomia, haematoma kiürítés
    ["HK-O15"] = { points = 40, rank = "physician", limit = 1 },  -- Thoracotomia
    ["HK-O16"] = { points = 30, rank = "physician", limit = 1 },  -- Belső rögzítés (ORIF)
    ["HK-O17"] = { points = 26, rank = "physician", limit = 1 },  -- Medence külső rögzítés
    ["HK-O18"] = { points = 32, rank = "physician", limit = 1 },  -- Ér-rekonstrukció
    ["HK-O19"] = { points = 30, rank = "physician", limit = 1 },  -- Primer PCI
    ["HK-O20"] = { points = 32, rank = "physician", limit = 1 },  -- Mechanikus trombectomia
    ["HK-O21"] = { points = 18, rank = "physician", limit = 1 },  -- Sebfeltárás, debridement
    ["HK-O22"] = { points = 20, rank = "physician", limit = 1 },  -- Pericardiotomia
    ["HK-I01"] = { points = 5, rank = "physician", limit = 6 },  -- Intenzív vizit
    ["HK-I02"] = { points = 4, rank = "physician", limit = 6 },  -- Lélegeztetés beállítása
    ["HK-I03"] = { points = 4, rank = "physician", limit = 6 },  -- Vazopresszor-titrálás
    ["HK-I04"] = { points = 3, rank = "physician", limit = 6 },  -- Szedáció beállítása
    ["HK-I05"] = { points = 3, rank = "resident", limit = 6 },  -- Vérgáz-ellenőrzés
    ["HK-T01"] = { points = 1, rank = "nurse", limit = 6 },  -- Hordágyra fektetés
    ["HK-T02"] = { points = 1, rank = "nurse", limit = 6 },  -- Belső betegszállítás (helyiségváltás)
    ["HK-T03"] = { points = 3, rank = "nurse", limit = 6 },  -- Elfekvő vizit
    ["HK-T04"] = { points = 4, rank = "nurse", limit = 6 },  -- Hólyagkatéter
    ["HK-T05"] = { points = 4, rank = "nurse", limit = 6 },  -- Gyomorszonda
    ["HK-T06"] = { points = 2, rank = "nurse", limit = 6 },  -- Ágyba helyezés (elfekvő, intenzív)
    ["HK-T07"] = { points = 1, rank = "nurse", limit = 6 },  -- Halott letakarása
    ["HK-DX"] = { points = 2, rank = "resident", limit = 5 },  -- helyes diagnózis (lelet szerint)
    ["HK-CASE"] = { points = 0, rank = "resident", limit = 1 },  -- kezelői esetbónusz (15%, er/server/outcome.lua)
}

ERC.CODE_GROUPS = { A = "admin", V = "exam", L = "lab", K = "imaging", E = "ecg", R = "airway", C = "circulation",
    G = "drug", S = "wound", O = "surgery", I = "icu", T = "care" }

-- points of a code (0 if unknown)
function ERC.codePoints(code) local d = ERC.CODES[code] return d and d.points or 0 end
