# web_api

Shared web UI toolkit of the server - *Provided by OpenSanAndreas* (the credit is added to every
page automatically, in the bottom-left corner of the `.osa-map-wrap` map; a page without a map
gets a strip at the bottom-left of the page).

A resource builds its web interface once; it then runs in two places:

| where | how it is reached | transport |
| --- | --- | --- |
| normal browser | `http://<server>:<httpport>/<resource>/` | `POST /<resource>/call/<function>` (MTA HTTP) |
| in game | a `ui_browser` site (CEF) | `mta.triggerEvent` -> web_api client -> server |

The page code is identical: `OSA.api().call('fn', ...)` works in both. Only server exports marked
`http="true"` in the app's `meta.xml` can be called, in both modes (the in-game bridge reads the
list from `meta.xml`, so it is exactly the HTTP surface).

Used by `med_erm` (EMS dispatch console, `ems-dispatch.eu`) and `rw_core` (Sunline Rail network
map, `sunline-rail.sa`). A live demo of the components: `http://<server>:<httpport>/web_api/`.

## Using it in a resource

`meta.xml`:

```xml
<include resource="web_api" />
<html src="web/http.html" default="true" />      <!-- also lists the app on web_manager -->
<file src="web/index.html"    type="client" />    <!-- every file the page links ... -->
<file src="web/css/style.css" type="client" />    <!-- ... must be a client file (in-game) -->
<file src="web/js/app.js"     type="client" />
<export function="myCall" type="server" http="true" />
```

`web/index.html` - link the shared files by absolute path, your own ones relative:

```html
<link rel="stylesheet" href="/web_api/osa.css">
<link rel="stylesheet" href="css/style.css">
...
<script src="/web_api/osa.js"></script>
<script src="js/app.js"></script>
```

Use double quotes and `<script src="..."></script>` as written - the HTTP builder looks for exactly
that pattern.

`web/http.html` - the standard entry (copy it). A resource may not read another resource's files,
so the app reads its files and web_api inlines them (MTA serves client files as
`application/octet-stream`, which browsers refuse as a stylesheet):

```lua
<*
local PAGE = "web/index.html"
local function read(path)
    local f = fileExists(path) and fileOpen(path, true)
    if not f then return nil end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    return content
end
local html = read(PAGE)
local files = {}
for _, path in ipairs(exports.web_api:getAssetRefs(html, PAGE)) do files[path] = read(path) end
httpWrite(exports.web_api:renderPage(html, files, PAGE))
*>
```

Server script - only for an in-game site (omit for an HTTP-only app):

```lua
local function registerSite()
    exports.web_api:registerApp({
        title = "My app", site = "my-app.eu", category = "services",
        description = "Shown in the ui_browser search.",
        -- page = "web/index.html"
    })
end
addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)   -- web_api restarted
```

The in-game page is opened through `loader.html`, which fetches your page with `?v=<version>` (changes
whenever your resource or web_api restarts), so CEF never shows a stale cached copy.

## Server exports

| export | |
| --- | --- |
| `registerApp(def)` | register the calling resource: `title`, `site` (ui_browser address), `category`, `description`, `page` |
| `unregisterApp()` | |
| `getApps()` | public info of the registered apps |
| `getAssetRefs(html, page)` | files (relative to the resource root) the page links - for `renderPage` |
| `renderPage(html, files, page)` | the complete HTTP document |
| `getCallerId(fallback)` | inside an `http="true"` export: `"player:<serial>"` for the in-game page, else `fallback` (pass the HTTP global `hostname`) or `"web"`. For rate limits / logs |
| `getCallerPlayer()` | the player behind an in-game call, `false` over HTTP |

Event `onWebApiStart` (server): web_api (re)started - register again.

## Page API (`osa.js`)

```js
const api = OSA.api();                       // the page's own resource
const r = await api.call('myCall', a, b);    // first return value; throws on network error / timeout
OSA.inGame                                   // true inside ui_browser
```

| | |
| --- | --- |
| `OSA.esc(s)` `OSA.arr(x)` `OSA.clean(name)` | escape html, `{}` -> array (MTA encodes empty Lua tables as `{}`), strip `#RRGGBB` |
| `OSA.hhmm(secOfDay)` `OSA.clock(epoch)` `OSA.age(epoch)` `OSA.delay(sec)` | time formatting |
| `OSA.time.sync(serverEpoch)` `OSA.time.now()` | server clock |
| `OSA.poll(fn, ms, {onOk, onFail})` | non-overlapping poll loop -> `{stop(), now()}` |
| `OSA.toast(text, ok)` | |
| `OSA.ui.openMenu(x, y, items)` | context menu: `{label, action, disabled, danger, dot}`, `{header}`, `'sep'` |
| `OSA.ui.showTip / moveTip / hideTip / updateTip` | tooltip |
| `OSA.ui.form(title, fields, submitLabel, hint)` / `OSA.ui.confirm(...)` | promise-based dialogs |
| `new OSA.Map(el, opts)` | pan / zoom map (below) |

### Map

```js
const map = new OSA.Map(document.getElementById('map'), { maxZoom: 4 });
map.marker('st:1', x, y, 'my-class', '<b>label</b>', onClick);   // world coordinates
map.removeMissing('st:', new Set(['st:1']));
map.addLayer((ctx, map) => { const [sx, sy] = map.toScreen(x, y); ... });   // canvas under the markers
map.fit(); map.fitBox(minX, minY, maxX, maxY, pad); map.focus(x, y, minZoom);
map.on('mapclick', e => e.detail.wx);  map.on('mapcontext', e => ...);  map.on('mapmove', ...);
```

The image is v_radar's bigmap (`/v_radar/radar/files/radar.png`, the same URL works over HTTP and in
game) and is laid out at a fixed logical size, so it does not matter whether `radar.png` is 3072 or
4096 px. Put the map in `<section class="osa-map-wrap"><div id="map"></div></section>`.

## Styles (`osa.css`)

Every class is `osa-` prefixed; theme by overriding the variables in your own css
(`--osa-bg`, `--osa-panel`, `--osa-panel-2/3`, `--osa-line`, `--osa-text`, `--osa-dim`,
`--osa-faint`, `--osa-accent`, `--osa-ok/bad/warn/info`, `--osa-topbar-bg`, `--osa-map-bg`).

`osa-topbar` `osa-brand` `osa-stats/osa-stat` `osa-kpis/osa-kpi` `osa-clock` `osa-conn(.ok/.bad)` ·
`osa-panel` `osa-panel-head` `osa-tabs/osa-tab` `osa-list` `osa-scroll` `osa-empty` `osa-muted` ·
`osa-btn(.primary/.danger/.small/.icon)` `osa-input` `osa-select` `osa-textarea` ·
`osa-badge` `osa-pill` (`.ok/.bad/.warn/.info`) `osa-chip` `osa-dot` `osa-tag` · `osa-kv` `osa-table` ·
`osa-login` `osa-login-box` · `osa-map-wrap` `osa-offline` `osa-legend` · the overlays (menu,
tooltip, modal, toasts) are created by `osa.js` itself.

The credit takes `--osa-footer-h` at the bottom of the map; `osa-legend` sits above it. Keep the
bottom-left corner of the map free.

## Files

```
web_api/
  osa.css  osa.js  loader.html      shared page files (client files, in-game: http://mta/web_api/...)
  server/main.lua                   app registry, ui_browser site list
  server/bridge.lua                 in-game call bridge (meta.xml http exports, caller id, flood guard)
  server/page.lua                   HTTP page builder
  server/demo.lua  demo/            demo page + its API (/web_api/)
  client/sites.lua                  registers the ui_browser sites
  client/bridge.lua                 page <-> server relay
```
