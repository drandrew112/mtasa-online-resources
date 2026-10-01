-- Környezeti megvilágítás a dynamic_lighting resource pontfényeivel: a villogó
-- fények színe rávetül az útra, a falakra és a közeli járművekre.
--
-- Fix méretű fénykészletet (pool) használunk: a fények egyszer jönnek létre,
-- utána csak mozgatjuk / színezzük őket. A nem használt fény a pálya alá kerül,
-- ott a dynamic_lighting távolság alapján kiszűri. Egyszerre csak a legközelebbi
-- ELS_ENV.maxVehicles jármű kap környezeti fényt.

EnvLight = {}

local DL = "dynamic_lighting"
local PARK_Z = -5000
local MOVE_EPSILON = 0.02

local maxVehicles = ELS_ENV.maxVehicles
local pool = {}        -- { light, parked, x, y, z, on, r, g, b }
local best = {}        -- a legközelebbi járművek: { dist, m, layout, pattern, t }
local bestCount = 0

for i = 1, maxVehicles do best[i] = {} end

local function dl()
    return exports[DL]
end

local function isAvailable()
    if not ELS_ENV.enabled then return false end
    local res = getResourceFromName(DL)
    return res and getResourceState(res) == "running"
end

local function createPool()
    for i = 1, maxVehicles * ELS_ENV.perVehicle do
        local light = dl():createPointLight(0, 0, PARK_Z, 0, 0, 0, 0, ELS_ENV.radius, true)
        if not light then break end
        pool[i] = { light = light, parked = true, on = false }
    end
end

local function park(slot)
    if slot.parked then return end
    dl():setLightPosition(slot.light, 0, 0, PARK_Z)
    slot.parked = true
end

local function setSlot(slot, x, y, z, on, r, g, b)
    if slot.parked or math.abs(x - slot.x) + math.abs(y - slot.y) + math.abs(z - slot.z) > MOVE_EPSILON then
        dl():setLightPosition(slot.light, x, y, z)
        slot.x, slot.y, slot.z, slot.parked = x, y, z, false
    end
    -- csak változáskor hívjuk, mert minden hívás újrarendezi a dynamic_lighting fényeit
    if on ~= slot.on or r ~= slot.r or g ~= slot.g or b ~= slot.b then
        dl():setLightColor(slot.light, r, g, b, on and ELS_ENV.intensity or 0)
        slot.on, slot.r, slot.g, slot.b = on, r, g, b
    end
end

------------------------------------------------------------
-- KÉPKOCKÁNKÉNTI FRISSÍTÉS (beacons.lua hívja)
------------------------------------------------------------

function EnvLight.begin()
    bestCount = 0
end

-- jelölt jármű; rendezetten megtartjuk a legközelebbi maxVehicles darabot
function EnvLight.consider(dist, m, layout, pattern, t)
    if dist > ELS_ENV.range or not layout.env or #layout.env == 0 then return end

    local pos = bestCount + 1
    while pos > 1 and best[pos - 1].dist > dist do
        pos = pos - 1
    end
    if pos > maxVehicles then return end

    local last = math.min(bestCount + 1, maxVehicles)
    local entry = best[last] -- a kieső (vagy még üres) bejegyzést használjuk újra
    for i = last, pos + 1, -1 do
        best[i] = best[i - 1]
    end
    best[pos] = entry
    entry.dist, entry.m, entry.layout, entry.pattern, entry.t = dist, m, layout, pattern, t
    bestCount = last
end

function EnvLight.finish()
    if bestCount == 0 and #pool == 0 then return end
    if not isAvailable() then return end
    if #pool == 0 then createPool() end

    local used = 0
    for i = 1, bestCount do
        local c = best[i]
        for _, e in ipairs(c.layout.env) do
            local slot = pool[used + 1]
            if not slot then break end
            used = used + 1
            local x, y, z = Beacons.toWorld(c.m, e.x, e.y, e.z)
            setSlot(slot, x, y, z, Beacons.isGroupOn(c.pattern, e.group, c.t), e.r, e.g, e.b)
        end
        c.m, c.layout = nil, nil
    end

    for i = used + 1, #pool do
        park(pool[i])
    end
end

-- minden fény kikapcsolása (nincs több világító jármű)
function EnvLight.release()
    bestCount = 0
    if #pool == 0 or not isAvailable() then return end
    for _, slot in ipairs(pool) do
        park(slot)
    end
end

------------------------------------------------------------
-- DYNAMIC_LIGHTING ÉLETCIKLUS
------------------------------------------------------------

-- a fények a dynamic_lighting elemei: ha az leáll, velük együtt eltűnnek
addEventHandler("onClientResourceStop", root, function(res)
    if getResourceName(res) == DL then
        pool = {}
    end
end)

-- a mi leállásunkkor viszont nekünk kell törölni őket
addEventHandler("onClientResourceStop", resourceRoot, function()
    if #pool > 0 and isAvailable() then
        for _, slot in ipairs(pool) do
            dl():destroyLight(slot.light)
        end
    end
    pool = {}
end)
