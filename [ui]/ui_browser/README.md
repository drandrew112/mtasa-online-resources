# ui_browser

A simplified **virtual browser** for MTA:SA. "Websites" are HTML-like markup files
(`sites/<name>/page.vhtml`) rendered by a small custom parser + layout engine
(drawn into a render target, with clean scrolling). Everything is in English.

## Exports

### Client

| export | description |
| --- | --- |
| `openBrowser()` | Open the browser on the home page (Open SE). |
| `openBrowserSite(url)` | Open the browser and navigate to an address (e.g. `"lvcars.vm"`). If already open, just navigates. |
| `registerBrowserSite(url, def)` | Register a new website (see below). |
| `isBrowserOpen()` | `true` while the browser is open. |
| `closeBrowser()` | Close the browser. |

### Server

| export | description |
| --- | --- |
| `openBrowser(player)` | Open the browser for that player. |
| `openBrowserSite(player, url)` | Open an address for that player. |

## Controls

- **URL bar (top)** – read-only, shows the current address. You cannot type here.
- **Left button** – back. **Right button (X)** – close.
- **Right mouse click** – go back; at the start of history it closes the browser.
- **Mouse wheel** – scroll.
- **Home page search box** – click it, type an address / a category / any words,
  press Enter. Escape or a click elsewhere unfocuses it.
- A **cash / bank HUD** shows top-right of the screen while the browser is open
  (bank balance = account data `bank_money`).
- `/browser [address]` – for testing.

Website addresses end in `.eu` by convention (e.g. `lvcars.eu`); it is not
enforced, any address works. The search engine itself lives at
`opensearchengine.com` — `opensearchengine.com/<category>` for a category,
`opensearchengine.com/results?q=<query>` for a search. (`home` / `search` /
`start` still resolve there too.)

## Panel integration

While the browser is open it sets `setElementData(localPlayer, "browserOpen", true)`.
The pause menu, `ui_phone` and the `ui_inac` interaction menu all check that flag
and will not open on top of the browser. The social panel is deliberately still
allowed. The `ui_phone` **Browser** app opens this browser (and closes the phone);
the `/browser` command still works too.

## Categories

Ids (shown in this order): `entertainment`, `finance`, `business`, `vehicles`,
`realestate` (labelled "Property"). Each has an accent colour (`BR.accentOf(id)`).

## Registering a website

```lua
exports.ui_browser:registerBrowserSite("mycars.vm", {
    title    = "My Cars",
    category = "vehicles",
    desc     = "Short blurb for the search list.",
    dir      = "sites/mycars",              -- folder with page.vhtml, logo.png, images
    markup   = "sites/mycars/page.vhtml",   -- OR:
    -- builder = function(query) return "<page>...</page>" end,
    logo     = "sites/mycars/logo.png",     -- optional; auto-used if the file exists
})
```

Site folder layout:

```
sites/mycars/
    page.vhtml      the markup
    logo.png        shown in the header and the search cards (optional)
    infernus.png    referenced from markup as <img src="infernus.png" />
```

All site files must also be listed in `meta.xml` (`<file src="..." />`).

## Markup language (`.vhtml`)

Not real HTML – only the tags below are understood. Root tag is `<page>`.

### Page theme

`<page>` carries the whole page's colours; every value is optional and defaults
to the light theme:

```
<page bg="#0b0b10" text="#efecf5" heading="#ffffff" muted="#9a94a8"
      link="#c084fc" accent="#e11d48" card="#161320" cardline="#33263f">
```

A dark `bg` automatically switches shadows / hover highlights to a light wash.

### Text / layout

| tag | attributes | notes |
| --- | --- | --- |
| `<page>` | `bg` | page, background colour `#rrggbb` |
| `<h1> <h2> <h3>` | `align`, `color` | headings |
| `<p> <small>` | `align`, `color`, `class` | paragraph / small text |
| `<price>` | – | styled price text |
| `<hr />` `<br />` `<space h="20" />` | | rule / line break / vertical gap |
| `<img />` | `src`, `w`, `h`, `alt` | bare `src` names resolve to the site folder |
| `<logo h="44" />` | `h` | the current site's `logo.png` |
| `<row>` | `gap` | children in equal-width columns |
| `<buttons>` | `gap` | buttons packed left-to-right, wrapping |
| `<card>` | `accent` | white panel; `accent` adds a top colour bar |
| `<list><item>…</item></list>` | | bulleted list |

### Interactive

| tag | attributes | notes |
| --- | --- | --- |
| `<button>` | `href`, `action`, `class`, `align`, `block` | `href` navigates, `action` fires an event |
| `<link>` | `href` | text hyperlink |

### Grids, tabs, sorting

| tag | attributes | notes |
| --- | --- | --- |
| `<grid cols="3" gap="16">` | `cols`, `gap` | equal-height cells, wraps to new rows |
| `<catalog cols="3" sort="price">` | `cols`, `gap`, `sort` | grid of `<card>` / `<product>`; `sort="price"` adds a Default / low→high / high→low control |
| `<tabs accent="#7c3aed">` | `accent` | contains `<tab title="4-Wheel">…</tab>`; only the active tab renders |

### Products (shops)

A shop lists `<product>` elements instead of `<card>`s. Clicking a product card
(no buy button on the card) opens a detail page: big image on the left half,
name / description / price / colour swatches / a brown **"BUY for $…"** button
on the right.

```
<catalog cols="3" sort="price">
    <product id="sultan_rs" name="Sultan RS" price="$48,000"
             img="sultan.png" colors="black,silver,blue,red">
        All-wheel drive, sport suspension, turbo engine.
    </product>
</catalog>
```

| attribute | notes |
| --- | --- |
| `id` | unique within the site; used in the URL (`lvcars.eu?product=sultan_rs`) and the buy action |
| `name`, `price` | shown on the card and the detail page (`price` is sorted by its digits) |
| `img` | image in the site folder; omit for text-only listings (property, business) |
| `colors` | comma list of `black white silver grey red blue green yellow orange purple`; adds swatches and appends `:<colour>` to the buy action |

The detail page and its swatches / big image (`<productimage>`, `<swatches>`) are
generated by the browser – you only write `<product>`.

### Home / site components

| tag | notes |
| --- | --- |
| `<brand href="home">Open SE</brand>` | home logo (`assets/opense_logo.png`), clickable, goes home |
| `<searchbox placeholder="…" />` | the search input |
| `<catbtn cat="vehicles" sel="1">Vehicles</catbtn>` | category button |
| `<sitecard href="…" title="…" url="…" logo="…">desc</sitecard>` | clickable site card |
| `<siteheader title="…" tagline="…" accent="#2563eb" />` | site header with logo |

### Classes (`class`)

`btn-primary`, `btn-buy`, `btn-danger`, `btn-dark`, `btn-ghost`, `muted`,
`onblue`, `price`, `big`.

## Button actions (`action`)

`<button action="buy:sultan_rs">` fires an event on click, client and server side:

```lua
-- client
addEventHandler("ui_browser:action", localPlayer, function(url, verb, arg, category)
    -- url="lvcars.vm", verb="buy", arg="sultan_rs", category="vehicles"
end)

-- server
addEventHandler("ui_browser:action", root, function(url, verb, arg, category)
    local player = client
end)
```

### Built-in handlers (`server.lua`)

- `bank_deposit:<amount|all>` / `bank_withdraw:<amount|all>` – calls the
  `v_bank` exports (`depositMoney` / `withdrawMoney`). A "Deposited / Withdrew"
  notification is sent **only when the export returns `true`**; the page is
  refreshed then too. Failures (not enough cash / balance, v_bank not running)
  are silent apart from a server log line.
- `buy:<id>` or `buy:<id>:<colour>` – notifies the player. **TODO:** for the
  `vehicles` category, call the `[vehicles]/v_ownveh` export once it exists
  (`exports.v_ownveh:giveVehicle(player, model, colour)` or similar).

Everything else is only logged; hook it from your own resource.

## Default sites

| address | category | notes |
| --- | --- | --- |
| `lvcars.eu` | vehicles | Las Venturas Cars (used cars, colours) |
| `legendary.eu` | vehicles | Legendary Wheels (4-Wheel / 2-Wheel tabs) |
| `vizair.eu` | vehicles | VizAir (Airplane / Helicopter tabs) |
| `cityhomes.eu` | realestate | CityHomes (text listings) |
| `bizmarket.eu` | business | BizMarket (text listings) |
| `fiero.eu` | business | Fiero Markets – "investments unavailable" placeholder |
| `diamond.eu` | entertainment | Diamond Casino – about page, "not opened yet" |
| `libertybank.eu` | finance | Liberty Bank – dynamic deposit/withdraw page |
