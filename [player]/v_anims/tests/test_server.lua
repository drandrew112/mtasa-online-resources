-- Offline tests (python tests/run.py): shared tables + server play / stop / commands / favourites
-- with the MTA functions stubbed.
local fails, passes = 0, 0
local function ok(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1 print("FAIL: " .. msg) end
end

-- ---------------------------------------------------------------- stubs
local now = 0
local timers = {}
function getTickCount() return now end
function setTimer(fn, ms, n) local t = { fn = fn, at = now + ms } timers[#timers + 1] = t return t end
function isTimer(t) for _, x in ipairs(timers) do if x == t then return true end end return false end
function killTimer(t) for i, x in ipairs(timers) do if x == t then table.remove(timers, i) return end end end
local function advance(ms)
    now = now + ms
    local again = true
    while again do
        again = false
        for i, t in ipairs(timers) do
            if t.at <= now then table.remove(timers, i) t.fn() again = true break end
        end
    end
end

L = setmetatable({ msg = function(k, p) return { k = k, p = p } end }, { __call = function(_, k) return k end })
local handlers, commands, events = {}, {}, {}
function addEvent() end
function addEventHandler(name, _, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) end
function triggerEvent(name, src, ...) events[#events + 1] = { name, src, ... } end
local sent = {}
function triggerClientEvent(p, name, _, a) sent[#sent + 1] = { p, name, a } end
function addCommandHandler(name, fn) commands[name] = fn end
resourceRoot, root = {}, {}

local P = { type = "player", data = { accName = "tester" }, anim = nil, dead = false }
function isElement(e) return type(e) == "table" and e.type ~= nil end
function getElementType(e) return e.type end
function isPedDead(e) return e.dead end
function getPedOccupiedVehicle(e) return e.veh end
function isElementAttached() return false end
function isElementInWater() return false end
function isPedOnGround() return true end
function getElementData(e, k) return e.data[k] end
function setElementData(e, k, v) e.data[k] = v end
function setPedAnimation(e, b, n, t, loop, upd, int, hold) e.anim = b and { b, n, loop, upd, hold } or nil end
local acc = {}
exports = { v_mysql = {
    getAccData = function(_, p, k) return acc[k] end,
    setAccData = function(_, p, k, v) acc[k] = v end,
} }
function toJSON(t) local s = {} for i, v in ipairs(t) do s[i] = '"' .. v .. '"' end return "[" .. table.concat(s, ",") .. "]" end
function fromJSON(s) local t = {} for v in s:gmatch('"([^"]+)"') do t[#t + 1] = v end return t end

dofile(ROOT .. "/shared/database.lua")
dofile(ROOT .. "/shared/anims.lua")
dofile(ROOT .. "/server/main.lua")

-- ---------------------------------------------------------------- database
local ids, n = {}, 0
for _, a in ipairs(ANIMS.order) do
    ok(not ids[a.id], "unique id " .. a.id)
    ids[a.id] = true
    n = n + 1
    ok(a.ms and a.ms > 0, "length " .. a.id)
    ok(not (a.loop and a.hold), "loop xor hold " .. a.id)
    if a.move then ok(a.cat == "dive", "only dives move: " .. a.id) end
end
ok(n > 400, "anim count " .. n)
for cmd in pairs(ANIMS.groups) do ok(commands[cmd] ~= nil, "command /" .. cmd) end
ok(commands.anim and commands.stopanim, "/anim + /stopanim")
ok(ANIMS.resolve("sit").id == "sit_1", "resolve default")
ok(ANIMS.resolve("sit", 2).id == "sit_2", "resolve n")
ok(ANIMS.resolve("crack_3").id == "crack_3", "resolve id")
ok(ANIMS.resolve("sit", 99) == nil, "resolve range")
ok(#ANIMS.cleanFavs({ "sit_1", "sit_1", "bogus", "dance_1", "dance_2", "dance_3", "dance_4", "dance_5", "dance_6", "dance_7", "dance_8" }) == 8, "clean favs")

-- ---------------------------------------------------------------- play / stop
commands.sit(P, "sit", "2")
ok(P.data["v_anims.cur"] == "sit_2", "sit 2 state")
ok(P.anim and P.anim[2] == "ParkSit_W_in", "intro first")
advance(5000)
ok(P.anim and P.anim[2] == "ParkSit_W_loop" and P.anim[3] == true, "loop after intro")
advance(400)
commands.stopanim(P)
ok(not P.data["v_anims.cur"], "stopped")
ok(P.anim and P.anim[2] == "ParkSit_W_out", "outro on stop")

advance(400)
commands.sit(P, "sit", "50")
ok(sent[#sent][2] == "v_anims:notify" and sent[#sent][3].k == "v_anims.msg.range", "range message")

commands.dive(P, "dive")
ok(P.anim and P.anim[4] == true, "dive updates position")
advance(10000)
ok(not P.data["v_anims.cur"], "once anim clears itself")

advance(400)
P.veh = {}
ok(playAnim(P, "dance_1") == false, "blocked in vehicle")
P.veh = nil
advance(400)
ok(playAnim(P, "dance_1") == true, "plays")
setAnimsBlocked(P, "minigame", true)
ok(not P.data["v_anims.cur"], "block stops")
advance(400)
ok(playAnim(P, "dance_1", true) == false, "blocked by export")
setAnimsBlocked(P, "minigame", false)
ok(playAnim(P, "dance_1", true) == true, "unblocked")
commands.anim(P, "anim", "stop")
ok(not P.data["v_anims.cur"], "/anim stop")

-- ---------------------------------------------------------------- favourites
setPlayerFavouriteAnims(P, { "sit_1", "crack_2", "nope" })
ok(acc[ANIMS.ACC_KEY] == '["sit_1","crack_2"]', "favs saved " .. tostring(acc[ANIMS.ACC_KEY]))
ok(sent[#sent][2] == "v_anims:favs" and #sent[#sent][3] == 2, "favs echoed")

print(("%d passed, %d failed"):format(passes, fails))
if fails > 0 then error("tests failed") end
