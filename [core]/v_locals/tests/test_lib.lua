-- v_locals lib unit tests (run by tests/run.py through lupa, Lua 5.1).
-- MTA functions are stubbed; the lib runs with LOCALS_INTERNAL as backend.

local failed, passed = 0, 0
local function eq(name, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL %s: got %q, want %q"):format(name, tostring(got), tostring(want)))
    end
end
local function ok(name, cond) eq(name, cond and true or false, true) end

--------------------------------------------------------------------------------
-- MTA stubs
--------------------------------------------------------------------------------
local LOGS = {}
function outputDebugString(msg) LOGS[#LOGS + 1] = msg end
local function logged(part)
    for _, m in ipairs(LOGS) do if m:find(part, 1, true) then return true end end
    return false
end

local handlers = {}
function addEvent() return true end
function addEventHandler(name, _, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn); return true end
local function fire(name, src, ...)
    for _, fn in ipairs(handlers[name] or {}) do source = src; fn(...) end
end

root = {}
function getThisResource() return "res" end
function getResourceName(r) if r == "res" then return "testres" elseif r == "vres" then return "v_locals" end return tostring(r) end
function getResourceRootElement() return {} end
function getResourceFromName() return nil end
function getResourceState() return "running" end
function isElement(e) return type(e) == "table" and e.isPlayer == true end

local function ulen(s) local _, n = s:gsub("[%z\1-\127\194-\244][\128-\191]*", ""); return n end
local MEASURED = 0
function dxGetTextWidth(text, scale, font, cc)
    MEASURED = MEASURED + 1
    if cc then text = text:gsub("#%x%x%x%x%x%x", "") end
    return ulen(text) * 8 * (scale or 1)
end
local DRAWN = 0
function dxDrawText() DRAWN = DRAWN + 1 end

CUR_LANG = "en"
DEBUG_MODE = nil
local CATS = {
    en = {
        t = {
            ["t.hello"]       = "Hello",
            ["t.paid"]        = "{name} paid you {amount|money}.",
            ["t.items.one"]   = "{count} patient",
            ["t.items.other"] = "{count} patients",
            ["t.status"]      = "Unit status: {status}",
            ["t.enroute"]     = "En Route",
            ["t.colour"]      = "#ff0000Error: #ffffff{what}",
            ["t.braces"]      = "{{literal}} and {name}",
            ["t.only_en"]     = "Only in English",
        },
        common = { ["common.cancel"] = "Cancel" },
    },
    hu = {
        t = {
            ["t.hello"] = "Szia",
            ["t.items"] = "{count} beteg",
        },
    },
}
local CATALOG_CALLS = 0
local MISSING = {}
LOCALS_INTERNAL = {
    getLanguage       = function() return CUR_LANG end,
    getLanguageInfo   = function() return { en = { plural = "one_other" }, hu = { plural = "other", fallback = "en" } } end,
    getCatalog        = function(lang, ns) CATALOG_CALLS = CATALOG_CALLS + 1; return CATS[lang] and CATS[lang][ns] or false end,
    getFile           = function(lang, path) if lang == "en" and path == "x/rules.txt" then return "RULES" end end,
    getDebugMode      = function() return DEBUG_MODE end,
    reportMissing     = function(key, res) MISSING[key] = res end,
    getPlayerLanguage = function(p) return p.lang end,
}

--------------------------------------------------------------------------------
-- client lib
--------------------------------------------------------------------------------
assert(loadstring(LIB_SOURCE_CLIENT, "@lib-client"))()
local L = _G.L
ok("client lib loaded", type(L) == "table" and L.__v_locals)

-- loading twice is a no-op
local before = L
assert(loadstring(LIB_SOURCE_CLIENT, "@lib-client"))()
ok("double import keeps the instance", _G.L == before)

-- UTF-8
eq("upper hu", L.upper("árvíztűrő tükörfúrógép"), "ÁRVÍZTŰRŐ TÜKÖRFÚRÓGÉP")
eq("lower hu", L.lower("ÁRVÍZTŰRŐ TÜKÖRFÚRÓGÉP"), "árvíztűrő tükörfúrógép")
eq("upper ascii", L.upper("Start Game"), "START GAME")
eq("upper latin-1", L.upper("àçñÿ"), "ÀÇÑŸ")
eq("upper cyrillic", L.upper("привет"), "ПРИВЕТ")
eq("upper keeps digits/symbols", L.upper("ő-1 €5"), "Ő-1 €5")
eq("len", L.len("őű ab"), 5)
eq("len ascii", L.len("abc"), 3)
eq("sub", L.sub("árvíz", 2, 3), "rv")
eq("sub negative", L.sub("tűrő", -2), "rő")
eq("sub ascii", L.sub("hello", 2, 3), "el")

-- lookup
eq("static", L("t.hello"), "Hello")
eq("params", L("t.paid", { name = "Andrew", amount = 1234.9 }), "Andrew paid you €1,234.")
eq("missing param kept", L("t.paid", { name = "Andrew" }), "Andrew paid you {amount|money}.")
eq("plural one", L("t.items", { count = 1 }), "1 patient")
eq("plural other", L("t.items", { count = 5 }), "5 patients")
eq("plural zero", L("t.items", { count = 0 }), "0 patients")
eq("nested message", L("t.status", { status = L.msg("t.enroute") }), "Unit status: En Route")
eq("colour codes", L("t.colour", { what = "x" }), "#ff0000Error: #ffffffx")
eq("escaped braces", L("t.braces", { name = "n" }), "{literal} and n")
eq("other namespace", L("common.cancel"), "Cancel")
eq("missing key -> key", L("t.nope"), "t.nope")
ok("missing key reported", MISSING["t.nope"] == "testres" and logged("missing key 't.nope'"))
local calls = CATALOG_CALLS
L("t.nope"); L("t.nope"); L("nons.key")
L("nons.key2")
eq("negative cache: unknown namespace fetched once", CATALOG_CALLS - calls, 1)
eq("resolve string", L.resolve("raw text"), "raw text")
eq("resolve message", L.resolve({ t = "t.hello" }), "Hello")
eq("resolve nil", L.resolve(nil), "")
ok("has", L.has("t.hello") and not L.has("t.nope"))
eq("file", L.file("x/rules.txt"), "RULES")
eq("template", L.template("{a}+{b|int}", { a = 1, b = 2.7 }), "1+2")

-- formats (English must match what the resources print today)
local function inacMoney(n)
    local s = tostring(math.floor(n))
    return "€" .. (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local same = true
for _, n in ipairs({ 0, 1, 12, 123, 999, 1000, 1234.9, 99999, 100000, 1234567, 999999999, 1000000000 }) do
    if L.money(n) ~= inacMoney(n) then same = false; print("money differs", n, L.money(n), inacMoney(n)) end
end
math.randomseed(112)
for _ = 1, 2000 do
    local n = math.random(0, 2000000000) + math.random()
    if L.money(n) ~= inacMoney(n) then same = false; print("money differs", n, L.money(n), inacMoney(n)); break end
end
ok("money == ui_inac money()", same)
eq("money negative", L.money(-1234), "-€1,234")
eq("money big", L.money(5000000000), "€5,000,000,000")
eq("num", L.num(1234567), "1,234,567")
eq("num negative", L.num(-1234), "-1,234")
eq("int like %d", L.int(2.7), ("%d"):format(2.7))
eq("int negative like %d", L.int(-2.7), ("%d"):format(-2.7))
eq("time mm:ss", L.time(75), "01:15")
eq("time hh:mm:ss", L.time(3725), "01:02:05")
eq("dist m", L.dist(850), "850 m")
eq("dist km", L.dist(1234), "1.2 km")
eq("fixed 1f", L.template("{v|1f}", { v = 2.25 }), ("%.1f"):format(2.25))
eq("pct", L.template("{v|pct}", { v = 42.9 }), "42%")
eq("upper fmt", L.template("{v|upper}", { v = "tűz" }), "TŰZ")

-- DX helpers (stub width = 8 px per character * scale)
eq("width", L.width("abcd", 1, "default"), 32)
MEASURED = 0
for _ = 1, 100 do L.width("abcd", 1, "default") end
eq("width cached", MEASURED, 0)
eq("width colour coded", L.width("#ff0000ab", 1, "default", true), 16)
eq("fit fits", L.fit("abcd", 40), "abcd")
eq("fit cut", L.fit("abcdefghij", 48), "abcde…")
eq("fit utf8", L.fit("őőőőőőőőőő", 48), "őőőőő…")
eq("fit trims space", L.fit("abc defgh", 40), "abc…")
local t1, s1 = L.fitScale("abcdefghij", 72, 1)          -- 80 px -> 0.9 scale fits
eq("fitScale shrinks", t1, "abcdefghij"); eq("fitScale scale", s1, 0.9)
local t2, s2 = L.fitScale("abcdefghij", 40, 1, nil, 0.8) -- too long even at 0.8
eq("fitScale min scale", s2, 0.8); eq("fitScale cut", t2, "abcde…")   -- 6 chars * 6.4 px = 38.4 px
local lines = L.wrap("aaa bbb ccc", 56)
eq("wrap lines", #lines, 2); eq("wrap 1", lines[1], "aaa bbb"); eq("wrap 2", lines[2], "ccc")
local long = L.wrap("őőőőőőőőőő", 32)
eq("wrap breaks long word", #long, 3); eq("wrap utf8 piece", long[1], "őőőő")
eq("wrap paragraphs", #L.wrap("a\n\nb", 100), 3)
MEASURED = 0
L.wrap("aaa bbb ccc", 56)
eq("wrap cached", MEASURED, 0)

-- bind + language change
local labels = L.bind({ hello = "t.hello", paid = { "t.paid", { name = "A", amount = 5 } }, msg = { t = "t.enroute" } })
eq("bind static", labels.hello, "Hello")
eq("bind params", labels.paid, "A paid you €5.")
local changed
L.onChange(function(lang, reason) changed = lang .. ":" .. reason end)
CUR_LANG = "hu"
fire("v_locals:onClientLanguageChange", root, "hu", "en")
eq("lang switched", L.lang(), "hu")
eq("bind refreshed", labels.hello, "Szia")
eq("onChange called", changed, "hu:language")
eq("fallback to en", L("t.only_en"), "Only in English")
eq("hu plural rule other", L("t.items", { count = 1 }), "1 beteg")
eq("bind fallback", labels.msg, "En Route")
CUR_LANG = "en"
fire("v_locals:onClientLanguageChange", root, "en", "hu")
eq("back to en", L("t.hello"), "Hello")

-- debug modes
fire("v_locals:onClientDebugModeChange", root, "keys")
eq("keys mode", L("t.hello"), "t.hello")
eq("keys mode bind", labels.hello, "t.hello")
fire("v_locals:onClientDebugModeChange", root, "pseudo")
local p = L("t.paid", { name = "Andrew", amount = 10 })
ok("pseudo keeps params", p:find("Andrew", 1, true) and p:find("€10", 1, true))
ok("pseudo accents + padding", p:sub(1, 1) == "[" and p:find("~", 1, true) and p:find("á", 1, true))
local pc = L("t.colour", { what = "x" })
ok("pseudo keeps colour codes", pc:find("#ff0000", 1, true) and pc:find("#ffffff", 1, true))
eq("pseudo missing key", L("t.nope2"), "[missing:t.nope2]")
fire("v_locals:onClientDebugModeChange", root, "overflow")
ok("overflow wrapper installed", dxDrawText ~= nil and L("t.hello") == "Hello")
LOGS = {}
dxDrawText("abcdefghij", 0, 0, 40, 10, 0, 1, "default")             -- 80 px in 40 px
dxDrawText("abc", 0, 0, 40, 10, 0, 1, "default")                    -- fits
dxDrawText("abcdefghij", 0, 0, 40, 10, 0, 1, "default", "left", "top", true)  -- clipped
dxDrawText("abcdefghijk", 0, 0, 40, 10, 0, 1, 1, "default")         -- scaleX, scaleY form
local over = 0
for _, m in ipairs(LOGS) do if m:find("overflow", 1, true) then over = over + 1 end end
eq("overflow reports", over, 2)
eq("overflow still draws", DRAWN, 4)
fire("v_locals:onClientDebugModeChange", root, nil)
eq("debug off", L("t.hello"), "Hello")

--------------------------------------------------------------------------------
-- server lib
--------------------------------------------------------------------------------
local clientL = L
_G.L = nil
handlers = {}
assert(loadstring(LIB_SOURCE_SERVER, "@lib-server"))()
local S = _G.L
ok("server lib loaded", type(S) == "table" and S ~= clientL and S.forPlayer)
local hu, en = { isPlayer = true, lang = "hu" }, { isPlayer = true, lang = "en" }
eq("forPlayer hu", S.forPlayer(hu, "t.hello"), "Szia")
eq("forPlayer en", S.forPlayer(en, "t.hello"), "Hello")
eq("forPlayer fallback", S.forPlayer(hu, "t.only_en"), "Only in English")
eq("forLang", S.forLang("hu", "t.hello"), "Szia")
eq("default L()", S("t.hello"), "Hello")
eq("resolveFor message", S.resolveFor(hu, S.msg("t.hello")), "Szia")
eq("server money", S.money(1234, en), "€1,234")
hu.lang = "en"                                   -- the player switched language
eq("forPlayer follows the player", S.forPlayer(hu, "t.hello"), "Hello")
local before = CATALOG_CALLS
S._reload()
eq("reload refetches", S.forPlayer(en, "t.paid", { name = "B", amount = 2 }), "B paid you €2.")
ok("reload dropped the cache", CATALOG_CALLS > before)

-- server lib imported by another resource: exports backend + language cache
local internalBackend = LOCALS_INTERNAL
LOCALS_INTERNAL = nil
local EXPORT_CALLS = 0
exports = { v_locals = setmetatable({}, { __index = function(_, fn)
    return function(_, ...) EXPORT_CALLS = EXPORT_CALLS + 1; return internalBackend[fn](...) end
end }) }
function getResourceFromName(name) return name == "v_locals" and "vres" or nil end
local SENT, CHAT, KICK = {}, {}, {}
function triggerClientEvent(...) SENT[#SENT + 1] = { ... }; return true end
function triggerLatentClientEvent(...) SENT[#SENT + 1] = { ... }; return true end
function outputChatBox(...) CHAT[#CHAT + 1] = { ... }; return true end
function kickPlayer(...) KICK[#KICK + 1] = { ... }; return true end
function getElementType(e) return e.isPlayer and "player" or "root" end
local SED
function setElementData(e, k, v) SED = v; return true end
function getElementData() return nil end
resourceRoot = {}
local PLAYERS = {}
function getElementsByType() return PLAYERS end
_G.L = nil
handlers = {}
assert(loadstring(LIB_SOURCE_SERVER, "@lib-server-consumer"))()
local X = _G.L
local p = { isPlayer = true, lang = "hu" }
eq("consumer forPlayer", X.forPlayer(p, "t.hello"), "Szia")
EXPORT_CALLS = 0
for _ = 1, 50 do X.forPlayer(p, "t.hello") end
eq("consumer: no export per lookup", EXPORT_CALLS, 0)
p.lang = "en"                                    -- v_locals changed it ...
eq("consumer language cached", X.forPlayer(p, "t.hello"), "Szia")
fire("onPlayerLanguageChange", p, "en", "hu")    -- ... and announced it
eq("onPlayerLanguageChange updates cache", X.forPlayer(p, "t.hello"), "Hello")
fire("onPlayerQuit", p)
p.lang = "hu"
eq("quit clears cache", X.forPlayer(p, "t.hello"), "Szia")
local beforeReload = EXPORT_CALLS
fire("v_locals:onCatalogReload", root)
eq("reload event resyncs", X.forPlayer(p, "t.hello"), "Szia")
ok("reload event refetched", EXPORT_CALLS > beforeReload)

-- message objects: safety net + send-time resolution per receiver (D4)
local m = X.msg("t.paid", { name = "A", amount = 5 })
ok("isMsg", X.isMsg(m) and not X.isMsg({ t = "x" }) and not X.isMsg("x"))
eq("msg tostring", tostring(m), "A paid you €5.")
eq("msg concat", "> " .. m, "> A paid you €5.")
eq("msg string method", m:upper(), "A PAID YOU €5.")
local sorted = { X.msg("t.paid", { name = "B", amount = 1 }), X.msg("t.hello") }
table.sort(sorted, function(a, b) return a < b end)
eq("msg sortable", tostring(sorted[1]), "B paid you €1.")
local plainCopy = { t = "t.hello", p = nil, __loc = true }     -- crossed a resource boundary (no metatable)
local pHu, pEn = { isPlayer = true, lang = "hu" }, { isPlayer = true, lang = "en" }
fire("onPlayerQuit", pHu); fire("onPlayerQuit", pEn)
triggerClientEvent(pHu, "ev", pHu, X.msg("t.hello"), { title = plainCopy, n = 3 }, 7)
local s1 = SENT[#SENT]
eq("trigger: receiver kept", s1[1], pHu)
eq("trigger: event name kept", s1[2], "ev")
eq("trigger: msg resolved in receiver language", s1[4], "Szia")
eq("trigger: nested plain-copy msg resolved", s1[5].title, "Szia")
eq("trigger: other values kept", s1[5].n == 3 and s1[6], 7)
PLAYERS = { pHu, pEn }
function isElement(e) return type(e) == "table" and (e.isPlayer == true or e == root) end
local before = #SENT
triggerClientEvent(root, "ev2", root, X.msg("t.hello"))
eq("trigger root: one send per player", #SENT - before, 2)
eq("trigger root: hu", SENT[before + 1][4], "Szia")
eq("trigger root: en", SENT[before + 2][4], "Hello")
before = #SENT
triggerClientEvent("ev3", root, X.msg("t.hello"))
eq("trigger without receiver: per player", #SENT - before, 2)
eq("trigger without receiver: receiver added", SENT[before + 1][1], pHu)
local data = { list = { 1, 2, 3 } }
triggerClientEvent(pEn, "ev4", pEn, data)
eq("trigger without msg: untouched table", SENT[#SENT][4], data)
outputChatBox(X.msg("t.hello"), pHu, 255, 0, 0)
eq("outputChatBox resolved", CHAT[#CHAT][1], "Szia")
eq("outputChatBox args kept", CHAT[#CHAT][3], 255)
before = #CHAT
outputChatBox(X.msg("t.hello"))
eq("outputChatBox to everyone: per player", #CHAT - before, 2)
kickPlayer(pHu, X.msg("t.hello"))
eq("kickPlayer reason resolved", KICK[#KICK][2], "Szia")
eq("resolveDeep", X.resolveDeep({ a = X.msg("t.hello") }, pEn).a, "Hello")
eq("string.format %s with message", ("[%s] %d"):format(X.msg("t.hello"), 5), "[Hello] 5")
eq("string.format plain", string.format("%d-%s", 1, "x"), "1-x")
eq("table.concat with message", table.concat({ "a", X.msg("t.hello"), "b" }, " "), "a Hello b")
eq("table.concat plain", table.concat({ 1, 2 }, ","), "1,2")
setElementData({}, "k", X.msg("t.hello"))
eq("setElementData stores default-language text", SED, "Hello")
setElementData({}, "k", { a = X.msg("t.hello"), n = 1 })
eq("setElementData nested text", SED.a, "Hello")
eq("format with a copied message", ("%s!"):format({ t = "t.hello", __loc = true }), "Hello!")
local copied = { name = { t = "t.hello", __loc = true }, list = { { t = "t.hello", __loc = true } } }
X.adopt(copied)
eq("adopt: concat works again", copied.name .. "!", "Hello!")
eq("adopt: nested", tostring(copied.list[1]), "Hello")

print(("tests: %d passed, %d failed"):format(passed, failed))
return failed > 0
