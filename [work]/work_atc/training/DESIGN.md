# work_atc képzési modulok – terv

Kérés (2026-10-16): három külön képzési modul a work_atc-hez, amelyek **teljesen kiváltják** a
toronyirányító tutorialt. Az első szolgálat a tutorial helyett az ADC modult ajánlja fel. A modulokat
az ATC jog (avi_core `atcright`) oldja fel: approach jog nélkül nem indítható az APC. Indítás egy
markerből: int 3, dim 0, `{ x = 214.42, y = 193.64, z = 1057.16 }`.

| modul | pozíció | jog | tartalom |
|---|---|---|---|
| ADC – Aerodrome Controller | SASF_TWR | TWR | a régi tutorial 9 lépése |
| APC – Approach Controller | SASF_APP | APP | induló gép a TMA-n át, érkező STAR-on, érkező radarvektorokkal |
| ACC – Area Control Centre | SACC_CTR | RADAR | átrepülő, szembe repülő konfliktuspár, érkező átadása az approachnak |

## Döntések

1. A régi `tutorial/` motorja lett általános (`training/`): egy szerveroldali munkamenet-motor
   (`server/session.lua`) és modulonként egy leírás (`server/modules.lua`: lépések, gépszerepek,
   belépési kampók, szerveroldali ellenőrzések), a kliensen egy közös gép (`client/core.lua`) és
   modulonként a részlépések (`client/adc.lua`, `apc.lua`, `acc.lua`).
2. A marker csak szolgálatban látszik és használható; `E` a modullistát nyitja (zárva / elérhető /
   teljesítve, „Újra”). A markerből indított modul a játékost a helyén hagyja (csak a dimenzió vált).
3. Teljesítés: `atc.training.<modul> = true`. Az első szolgálati ajánlatra adott válasz
   `atc.training.offered`. A modul megszakítása nem teljesítés.
4. Minden más pozíció zárva van: a gyakornok szektorán kívül a pilóták maguktól repülnek. A CTA-ban a
   képzési pozíció az egyetlen nyitott a centre láncokban (`sectorPosition(ac, open)`), így a
   SACC_CTR az egész CTA-t viszi akkor is, ha élesben valaki egy osztott szektort tart.
5. Gyorsítás csak a „csak nézd” részlépéseken (`fast`), és csak ha a gyakornok egyik gépe sem kér.
6. A lépések nem akadnak el: ha a gép közben elhagyta a szektort, a parancsot kérő részlépés is
   továbblép.

## Megvalósítás közben derült ki (offline lupa futás)

- Az APC érkező a TMA belépő fixet pont a TMA határán éri el, ezért STAR-t sosem kér, azonnal
  megközelítési engedélyt kér. Ezért az első APC érkező a pilóták által választott STAR-ral jön (a radar
  zárva van, élesben is így jönne), a gyakornok süllyeszti és Cleared approach-ot ad; a második STAR
  nélkül jön, azt vektorozni kell.
- A TMA-ban kb. 75–90 s jut egy érkezőre (1x sebességgel): a süllyesztés és a megközelítési
  engedély ennyi idő alatt kényelmesen kiadható.
- A konfliktuspár 2 × 3500 m-ről indul, kb. 105 s múlva találkoznának; 2000 láb emelés a 20. s-ban
  szétválasztja őket.

## SCOPE modul (2026-10-16)

Kérés: a radarkép bemutatása külön modulban; ez az első szolgálatkor felajánlott modul. A többi modul
ismertnek veszi a radarképet, belőlük kikerült minden ilyen rész (ADC: a radarkép-túra és a
címkék általános leírása; APC / ACC: a „scope” lépés neve „airspace” lett, a lista-magyarázat
kikerült, a légtér tartalma maradt).

- Pozíció SASF_TWR, jog TWR, kb. 5 perc. Lépések: console, tour (felső sáv, eszközök, nézet, listák,
  gombok), menu (egy induló gép az állóhelyen: címke, a menü megnyitása és röviden a tartalma –
  parancsot nem kell adni), logout, done.
- A modul vége a `logout` lépés: a session motor a modul `logoutStep` mezőjét figyeli az „alerts”
  helyett.
