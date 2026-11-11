-- police_system / modules/radio_voice/tools/test_builder.lua
-- Run by tools/test_builder.py (lupa, Lua 5.1): VOICE.db is set from data/voice.json, then every phrase is built
-- with sample arguments and checked. Prints the sentences; error() on a failed check.

local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end end
local B = VOICE.Builder
local DB = VOICE.db

local S = { callsign = "A-12", plate = "4gt-r218", color = "28,47,110", model = 560, heading = 0, area = "Idlewood",
            crime = "robbery", priority = 1, stolen = true, warrant = true, caution = true, vehicle = true,
            direction = true, shots = true }

local seed = 1
B.random = function(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = seed / 2147483648
    if not a then return r end
    if not b then a, b = 1, a end
    return a + math.floor(r * (b - a + 1))
end

local n = 0
local ids = {}
for id in pairs(DB.phrases) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do
    for round = 1, 20 do
        local items, total = B.build(id, S)
        check(items and #items > 0, id .. " built nothing")
        for _, it in ipairs(items) do
            if not it.pause then
                check(type(it.file) == "string" and it.file:find("^modules/radio_voice/sounds/.+%.ogg$"), id .. " bad file " .. tostring(it.file))
                check(EXISTS(it.file), id .. " missing file " .. it.file)
                check(it.len > 0, id .. " len")
            end
        end
        check(total > 500 and total < 30000, id .. " total " .. total)
        if round == 1 then print(("%-18s %5d ms  %s"):format(id, total, B.text(items))) end
        n = n + 1
    end
end

-- specific checks
local items = B.build("QUERY_VEHICLE", S)
local toks = {}
for _, it in ipairs(items) do if it.tok then toks[#toks + 1] = it.tok end end
local str = table.concat(toks, " ")
check(str:find("UNIT.ADAM CHAR.1 CHAR.2", 1, true), "callsign: " .. str)
check(str:find("CHAR.4 CHAR.G CHAR.T CHAR.R CHAR.2 CHAR.1 CHAR.8", 1, true), "plate: " .. str)
check(str:find("COLOR.DARK_BLUE VEH.SEDAN", 1, true), "color/vehicle: " .. str)
check(str:find("PLATE.STOLEN PLATE.WARRANT PLATE.CAUTION", 1, true) and not str:find("PLATE.FELONY", 1, true), "flags: " .. str)
-- clean vehicle: no flag tokens
items = B.build("QUERY_VEHICLE", { callsign = "L-7", plate = "ABC", color = "250,250,250", model = 513, vehicle = false })
str = B.text(items)
check(not str:find("stolen") and not str:find("warrant"), "clean: " .. str)
check(str:find("Lincoln seven", 1, true), "lincoln: " .. str)
-- area without audio drops "in"
items = B.build("CALL_OFFER", { callsign = "A-1", crime = "robbery", area = "Idlewood", priority = 2 })
for _, it in ipairs(items) do check(it.tok ~= "CONJ.IN", "CONJ.IN left before a missing area") end
-- directions: 0 north, 90 west, 180 south, 270 east
check(VOICE.dirIndex(0) == 1 and VOICE.dirIndex(90) == 2 and VOICE.dirIndex(180) == 3 and VOICE.dirIndex(270) == 4
    and VOICE.dirIndex(350) == 1 and VOICE.dirIndex(-90) == 4, "dirIndex")
-- colours
check(B.nearestColor("10,10,10") == "COLOR.BLACK" and B.nearestColor("250,250,250") == "COLOR.WHITE"
    and B.nearestColor("200,20,20") == "COLOR.RED", "nearestColor")
-- crime mapping
check(B.crimeToken("shots_at_police") == "CRIME.SHOTS_FIRED_AT_AN_OFFICER" and B.crimeToken("robbery") == "CRIME.ROBBERY"
    and B.crimeToken("ASSIST.REQUIRED") == "ASSIST.REQUIRED" and B.crimeToken("deadbody") == nil, "crimeToken")
-- unknown phrase
check(B.build("NOPE", S) == nil, "unknown phrase")
-- overlap between plate characters
items = B.build("QUERY_VEHICLE", S)
local overl = false
for i, it in ipairs(items) do if it.char and items[i - 1] and items[i - 1].char then overl = overl or it.gap < 0 end end
check(overl, "char overlap")
print(("OK: %d builds"):format(n))
