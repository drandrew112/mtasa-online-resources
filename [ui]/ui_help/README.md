# ui_help – súgó panel

F1 (vagy `/help`) nyitja és zárja. Bal oldalt a kereső és a témalista (kategóriák, kattintásra
összecsukhatók), jobb oldalt a kiválasztott oldal görgethetően.

## Fájlok

| Fájl | Mit csinál |
|---|---|
| `content/index.lua` | a kategóriák és témák listája (`HELP_INDEX`) |
| `content/<nyelv>/...` | az oldalak szövege nyelvenként (`en`, `hu`); ha a `hu` fájl hiányzik, az `en` jelenik meg |
| `content/images/...` | képek az oldalakhoz |
| `client/content.lua` | téma-nyilvántartás, fájlbetöltés, nyelvenkénti cache |
| `client/markup.lua` | a szövegformátum feldolgozása és tördelése |
| `client/search.lua` | kereső (kis/nagybetű és ékezet független) |
| `client/panel.lua` | a DX panel, billentyűk, görgetés |
| `client/exports.lua`, `server/exports.lua` | exportok más resource-oknak |

A panel feliratai a v_locals `ui_help` névterében vannak (`[core]/v_locals/locales/<nyelv>/ui_help.json`).

## Új téma felvétele

1. Kategória a `content/index.lua`-ba (ha még nincs):
   ```lua
   { id = "basics", order = 10, title = { en = "Getting started", hu = "Kezdő lépések" } },
   ```
2. Téma ugyanide:
   ```lua
   { id = "first_steps", category = "basics", order = 10, file = "basics/first_steps.txt" },
   ```
3. A szöveg: `content/en/basics/first_steps.txt` és `content/hu/basics/first_steps.txt`.
4. Minden fájl kerüljön be a `meta.xml`-be:
   ```xml
   <file src="content/en/basics/first_steps.txt" type="client" />
   <file src="content/hu/basics/first_steps.txt" type="client" />
   ```

Opcionális mezők: `title` (különben a fájl első `# ` sora), `keywords` (extra keresőszavak),
`related` (kapcsolódó témák id-jei, az oldal alján jelennek meg), `hidden = true` (nincs a listában,
csak keresésből és linkről érhető el). A `HELP_INDEX.home` egy kezdőoldal fájlja lehet
(pl. `"home.txt"`); nélküle a kezdőoldal egy tartalomjegyzék.

## Szövegformátum

Soronként értelmezett, egyszerű jelölés (UTF-8 fájl):

```text
# Az oldal címe
@keywords: pénz, bank, átutalás
@related: bank_accounts, loans

Sima bekezdés. Az egymást követő sorok egy bekezdéssé fűződnek,
az üres sor új bekezdést kezd. Sor végi \ = sortörés.\
Ez már új sorban van. **Kiemelés** és `/parancs` vagy `F1` is használható,
valamint MTA színkód: #FF5050piros#DEE2E9 szöveg.

## Fejezetcím (vonallal alatta)
### Alcím

- felsorolás
- második elem
  - beljebb (2 szóköz)
1. számozott lista
2. második lépés

> Tipp doboz. Több egymást követő > sor egy dobozba kerül.
>! Figyelmeztetés doboz.

---
![160](content/images/bank.png)
[[bank_accounts]]
[[loans|Hitelek – saját felirattal]]
```

- `# ` az első sorban: az oldal címe (a későbbi `# ` sorok nagy fejezetcímek).
- `@keywords:` keresőszavak, `@related:` kapcsolódó témák, `@title:` cím felülírása.
- `![magasság](útvonal)`: kép, a magasság 1080p-s pixelben (üresen: eredeti méret, a szélességhez igazítva).
- `[[téma_id]]` vagy `[[téma_id|felirat]]`: kattintható link egy másik témára (külön sorban).

## Exportok

Kliens (`exports.ui_help:...`):

- `openHelp([topicId])`, `closeHelp()`, `toggleHelp()`, `isHelpOpen()`
- `addHelpCategory(id, { title, order })`
- `addHelpTopic(id, { category, order, title, text, keywords, related, hidden })` – más resource
  saját súgóoldala; a `text` ugyanebben a formátumban, string / `{ en = ..., hu = ... }` / v_locals üzenet.
  A resource leállásakor a témái automatikusan törlődnek.
- `removeHelpTopic(id)`, `removeHelpCategory(id)`, `getHelpTopics()`
- esemény: `ui_help:onClientHelpToggle` (open), source = localPlayer; nyitva a helyi
  `helpOpen` element data `true`.

Szerver: `openHelp(player [, topicId])`.

Például egy munka bemutatójából a megfelelő oldal megnyitása: `exports.ui_help:openHelp("work_ems")`.

## Ötletek a bővítéshez

- billentyű-jelvények (`[F1]` keretben) és táblázatok a markupban
- „legutóbb megnyitott” és „népszerű” témák a kezdőoldalon
- első belépéskor felugró ajánlott témák
- admin szerkesztő (mint a v_news) MySQL-ben tárolt oldalakkal
