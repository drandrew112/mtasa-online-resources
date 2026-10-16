-- Scope alerts (ac.alert, shown in red above the label) and separation losses.
--   EMRG  squawk 7700
--   COMS  squawk 7600
--   DUPE  another active aircraft squawks the same code
--   STCA  separation lost (rules below)
--   RAM   route deviation: off the cleared route (heading to the next point more than
--         TR.RAM_ANGLE off for TR.RAM_TIME s) while flying its own navigation. Should never happen.
-- Separation rules (each loss is fined once per pair, on the controllers of both aircraft, but only when it
-- happened in that controller's own sector: an aircraft handed over early, e.g. CNU controlling one still
-- in the CSU sector, does not cost CNU anything):
--   GND  two ground aircraft head-on (facing each other, close, on the same line)
--   TMA  closer than TR.SEP_AIR_DIST (horizontal) and TR.SEP_AIR_VERT (vertical) in a TMA
--   CTA  the same in the CTA
-- A pair counts as separated again TR.SEP_RESET s after the conflict ended (no flicker re-fines).

addEvent("onAviSeparationLoss")   -- source: resourceRoot, args: kind, { posId, ... }, callsign1, callsign2
addEvent("onAviTutorialSeparationLoss")   -- source: resourceRoot, args: owner player, kind, callsign1, callsign2

local conflicts = {}    -- ["id1:id2"] = { kind = , last = tick }

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
local function bearing(ax, ay, bx, by) return math.deg(math.atan2(bx - ax, by - ay)) % 360 end
local function angleTo(from, to) return (to - from + 540) % 360 - 180 end

-- ground phases that count for the head-on rule (not standing at the stand)
local GND_ACTIVE = { pushback = true, pushed = true, taxi_out = true, hold = true, lined = true, takeoff = true,
    landing = true, vacate = true, vacated = true, taxi_in = true }

local function headOn(a, b)
    if (a.gndApt or a.arr) ~= (b.gndApt or b.arr) then return false end
    if a.spd < 1 and b.spd < 1 then return false end
    if dist(a.x, a.y, b.x, b.y) > TR.SEP_GND_DIST then return false end
    if math.abs(angleTo(a.hdg, b.hdg)) < 180 - TR.SEP_GND_ANGLE then return false end
    -- each one ahead of the other, roughly on the same line
    return math.abs(angleTo(a.hdg, bearing(a.x, a.y, b.x, b.y))) < TR.SEP_GND_ANGLE
        and math.abs(angleTo(b.hdg, bearing(b.x, b.y, a.x, a.y))) < TR.SEP_GND_ANGLE
end

local function airClass(ac)
    local a = airspaceAt(ac.x, ac.y, ac.alt)
    return a and a.type
end

-- "TMA" / "CTA" when the pair is too close in one of those, nil otherwise
local function airConflict(a, b)
    if math.abs(a.alt - b.alt) >= TR.SEP_AIR_VERT then return nil end
    if dist(a.x, a.y, b.x, b.y) >= TR.SEP_AIR_DIST then return nil end
    local ca, cb = airClass(a), airClass(b)
    if ca == "TMA" or cb == "TMA" then return "TMA" end
    if ca == "CTA" or cb == "CTA" then return "CTA" end
    return nil
end

local function routeDeviation(ac, dt)
    local t = ac.phase == "air" and not ac.ahdg and ac.navTgt
    if t and math.abs(angleTo(ac.hdg, bearing(ac.x, ac.y, t.x, t.y))) > TR.RAM_ANGLE then
        ac.ramTime = (ac.ramTime or 0) + dt
    else
        ac.ramTime = 0
    end
    return ac.ramTime >= TR.RAM_TIME
end

function updateAlerts(dt)
    local now = getTickCount()
    local list, stca = {}, {}
    for _, ac in pairs(AIRCRAFT) do list[#list + 1] = ac end
    table.sort(list, function(a, b) return a.id < b.id end)

    for i = 1, #list - 1 do
        local a = list[i]
        local ga = isAircraftOnGround(a)
        for j = i + 1, #list do
            local b = list[j]
            local gb = isAircraftOnGround(b)
            local kind
            if a.tut ~= b.tut then
                -- the live traffic and the tutorial worlds never conflict
            elseif ga and gb then
                if GND_ACTIVE[a.phase] and GND_ACTIVE[b.phase] and headOn(a, b) then kind = "GND" end
            elseif not ga and not gb then
                kind = airConflict(a, b)
            end
            if kind then
                stca[a.id], stca[b.id] = true, true
                local key = a.id .. ":" .. b.id
                local c = conflicts[key]
                if not c and a.tut then
                    -- tutorial: no fine, the tutorial explains it
                    triggerEvent("onAviTutorialSeparationLoss", resourceRoot, a.tut, kind, a.cs, b.cs)
                    c = { kind = kind }
                    conflicts[key] = c
                elseif not c then
                    local pos, seen = {}, {}
                    for _, ac in ipairs({ a, b }) do
                        if ac.ctl and not seen[ac.ctl] and sectorPosition(ac) == ac.ctl then
                            seen[ac.ctl] = true; pos[#pos + 1] = ac.ctl
                        end
                    end
                    triggerEvent("onAviSeparationLoss", resourceRoot, kind, pos, a.cs, b.cs)
                    if #pos > 0 then
                        outputDebugString(("[avi_traffic] separation loss %s: %s / %s (%s)"):format(kind, a.cs, b.cs,
                            table.concat(pos, ", ")))
                    end
                    c = { kind = kind }
                    conflicts[key] = c
                end
                c.last = now
            end
        end
    end
    for key, c in pairs(conflicts) do
        local id1, id2 = key:match("^(%d+):(%d+)$")
        if not (AIRCRAFT[tonumber(id1)] and AIRCRAFT[tonumber(id2)]) or now - c.last > TR.SEP_RESET * 1000 then
            conflicts[key] = nil
        end
    end

    -- duplicate squawks within one world (live / each tutorial)
    local function sqkKey(ac) return (ac.tut and tostring(ac.tut) or "") .. ":" .. ac.sqk end
    local sqkCount = {}
    for _, ac in ipairs(list) do
        if ac.sqk then sqkCount[sqkKey(ac)] = (sqkCount[sqkKey(ac)] or 0) + 1 end
    end

    for _, ac in ipairs(list) do
        local al = {}
        if ac.sqk == "7700" then al[#al + 1] = "EMRG" end
        if ac.sqk == "7600" then al[#al + 1] = "COMS" end
        if ac.sqk and sqkCount[sqkKey(ac)] > 1 then al[#al + 1] = "DUPE" end
        if stca[ac.id] then al[#al + 1] = "STCA" end
        if routeDeviation(ac, dt) then al[#al + 1] = "RAM" end
        ac.alert = #al > 0 and table.concat(al, " ") or nil
    end
end

-- tests / emergencies: set the squawk of an active flight (7700 = EMRG, 7600 = COMS)
function setSquawk(cs, code)
    code = tostring(code or "")
    if not code:match("^[0-7][0-7][0-7][0-7]$") then return false, "bad squawk" end
    for _, ac in pairs(AIRCRAFT) do
        if ac.cs == tostring(cs or ""):upper() and not ac.tut then
            ac.sqk = code
            return true
        end
    end
    return false, "not active"
end
