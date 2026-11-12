-- police_system / modules/radio_voice/client/builder.lua
-- phrase id + args -> the ordered list of sound items the player plays (the Lua twin of docs/design.html's builder).
-- An item: { tok, file, len (ms, trimmed), text, gap (ms before it, negative = overlap), char, fx } or { pause = ms }.
-- Variables (db.varsHelp): callsign, plate, color, vehicle, direction, bound, crime, code, area. A variable without
-- audio (a zone or plane model without a clip) is dropped; "in <area>" drops its conjunctive with it.
-- Pure Lua apart from VOICE.db, so tools/test_builder.lua runs it outside MTA.

VOICE = VOICE or {}
local B = {}
VOICE.Builder = B

local DB
B.random = math.random

local function clipOf(name)
    local c = DB.clips[name]
    if c and c.same then return DB.clips[c.same] end
    return c
end

local function pick(tok)
    local t = DB.tokens[tok]
    if not t or not t.clips or #t.clips == 0 then return nil end
    local avoid = {}
    for _, a in ipairs(t.avoid or {}) do avoid[a] = true end
    local list = {}
    for _, c in ipairs(t.clips) do if not avoid[c] then list[#list + 1] = c end end
    if #list == 0 then list = t.clips end
    return list[B.random(#list)]
end

local function push(out, tok, extra)
    local name = pick(tok)
    local c = name and clipOf(name)
    if not c or not c.file then return false end
    local it = { tok = tok, file = c.file, len = tonumber(c.len) or 300, text = DB.tokens[tok].text or "" }
    if extra then for k, v in pairs(extra) do it[k] = v end end
    out[#out + 1] = it
    return true
end

-- "r,g,b" | { r, g, b } -> nearest maps.colors token (redmean distance)
function B.nearestColor(color)
    local r, g, b
    if type(color) == "table" then
        r, g, b = tonumber(color[1]), tonumber(color[2]), tonumber(color[3])
    else
        r, g, b = tostring(color or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
    end
    if not (r and g and b) then return nil end
    local best, bd
    for _, c in ipairs(DB.maps.colors) do
        local R, G, Bc = c.rgb[1], c.rgb[2], c.rgb[3]
        local rm = (r + R) / 2
        local d = (2 + rm / 256) * (r - R) ^ 2 + 4 * (g - G) ^ 2 + (2 + (255 - rm) / 256) * (b - Bc) ^ 2
        if not bd or d < bd then best, bd = c.token, d end
    end
    return best
end

function B.crimeToken(crime)
    if type(crime) ~= "string" or crime == "" then return nil end
    if crime:find("^CRIME%.") or crime:find("^ASSIST%.") then return DB.tokens[crime] and crime or nil end
    return DB.maps.reasonCrime[crime] or DB.maps.sceneCrime[crime]
end

local function expandVar(v, a, out)
    if v == "callsign" then
        local kind, num = tostring(a.callsign or ""):match("^([ALal])%-?(%d+)$")
        if not kind then return end
        push(out, kind:upper() == "A" and "UNIT.ADAM" or "UNIT.LINCOLN")
        for d in num:gmatch("%d") do push(out, "CHAR." .. d, { char = true }) end
    elseif v == "plate" then
        local p = tostring(a.plate or ""):upper():gsub("[^0-9A-Z]", ""):sub(1, 8)
        for ch in p:gmatch(".") do push(out, "CHAR." .. ch, { char = true }) end
    elseif v == "color" then
        local t = B.nearestColor(a.color)
        if t then push(out, t) end
    elseif v == "vehicle" then
        local t = DB.maps.vehicles[tostring(a.model)]
        if t then push(out, t) end
    elseif v == "direction" then
        push(out, DB.maps.directions.heading[VOICE.dirIndex(a.heading)])
    elseif v == "bound" then
        push(out, DB.maps.directions.bound[VOICE.dirIndex(a.heading)])
    elseif v == "crime" then
        local t = B.crimeToken(a.crime)
        if t then push(out, t) end
    elseif v == "code" then
        push(out, DB.maps.priorityCode[tostring(a.priority)] or "RESPOND.CODE_2")
    elseif v == "name" then
        -- "First Last" (a.gender "m" | "f" picks the first-name list; none = either): first name, short pause, last name
        local words = {}
        for w in tostring(a.name or ""):lower():gsub("'", ""):gmatch("[%a]+") do words[#words + 1] = w end
        if #words == 0 then return end
        local names = DB.maps.names
        local g = a.gender == "f" and "f" or (a.gender == "m" and "m" or nil)
        local first = (g and names[g][words[1]]) or (not g and (names.m[words[1]] or names.f[words[1]]))
        local last = #words > 1 and names.l[words[#words]] or nil
        if first then push(out, first) end
        if first and last then out[#out + 1] = { pause = 120 } end
        if last then push(out, last) end
    elseif v == "area" then
        local t = a.area and DB.maps.areas[a.area]
        if t and push(out, t) then return end
        local prev = out[#out]
        if prev and prev.tok and prev.tok:find("^CONJ%.") then out[#out] = nil end
    end
end

local function expand(seq, a, out)
    for _, it in ipairs(seq or {}) do
        if type(it) == "string" then
            push(out, it)
        elseif type(it) == "table" then
            if it.var then
                expandVar(it.var, a, out)
            elseif it.opt then
                if B.random() < (tonumber(it.p) or 0.5) then expand(it.opt, a, out) end
            elseif it.any then
                if #it.any > 0 then expand(it.any[B.random(#it.any)], a, out) end
            elseif it["if"] then
                local key, neg = it["if"], false
                if key:sub(1, 1) == "!" then key, neg = key:sub(2), true end
                local truthy = a[key] ~= nil and a[key] ~= false and a[key] ~= ""
                if truthy ~= neg then expand(it["then"], a, out) elseif it["else"] then expand(it["else"], a, out) end
            elseif it.pause then
                out[#out + 1] = { pause = tonumber(it.pause) or 120 }
            end
        end
    end
end

-- -> items, total ms | nil when the phrase is unknown or nothing of it has audio
function B.build(pid, args)
    DB = VOICE.load()
    if not DB then return nil end
    local trig, seq = DB.triggers[pid], DB.phrases[pid]
    if not trig or not seq then return nil end
    args = type(args) == "table" and args or {}
    local frame = DB.frames[trig.frame] or DB.frames.short
    local body = {}
    expand(seq, args, body)
    local spoken = 0
    for _, it in ipairs(body) do if not it.pause then spoken = spoken + 1 end end
    if spoken == 0 then return nil end
    local out = {}
    for _, t in ipairs(frame.before or {}) do push(out, t, { fx = true }) end
    for _, it in ipairs(body) do out[#out + 1] = it end
    for _, t in ipairs(frame.after or {}) do push(out, t, { fx = true }) end
    local S = DB.settings
    local total = 0
    for i, it in ipairs(out) do
        local prev = out[i - 1]
        if prev and not it.pause and not prev.pause then
            it.gap = (it.char and prev.char) and (tonumber(S.charGapMs) or -20) or (tonumber(S.gapMs) or 40)
        else
            it.gap = 0
        end
        total = total + it.gap + (it.pause or it.len)
    end
    return out, total
end

-- the English sentence of the items (subtitle / log)
function B.text(items)
    local words = {}
    for _, it in ipairs(items or {}) do
        if not it.pause and not it.fx and it.text ~= "" then words[#words + 1] = it.text end
    end
    return table.concat(words, " ")
end
