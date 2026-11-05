-- Környezeti megvilágítás: a villogó fények színe rávetül a környezetre.
-- Két háttér közül a játékos választ (ui_pause > Grafika > "gfx_elslights"):
--
--   "dynamic" – a dynamic_lighting resource shader-pontfényei: út, falak, járművek
--   "native"  – a GTA saját createLight pontfényei: járművek/pedek + földi fényfolt
--               (createsShadow); shader nélkül, gyengébb gépen olcsóbb
--
-- Ha a "dynamic" van kiválasztva, de a dynamic_lighting nem fut, a natív fények
-- lépnek a helyére.
--
-- Mindkét háttér fix méretű fénykészletet (pool) használ: a fények egyszer jönnek
-- létre, utána csak mozgatjuk / színezzük őket. A nem használt fény a pálya alá
-- kerül. Egyszerre csak a legközelebbi N jármű kap környezeti fényt.

EnvLight = {}

local DL = "dynamic_lighting"
local PARK_Z = -5000
local MOVE_EPSILON = 0.02

local mode = nil       -- a játékos választása (nil = ELS_ENV.defaultMode)
local active = nil     -- a ténylegesen használt háttér neve
local pool = {}        -- { light, parked, x, y, z, on, r, g, b, dim, int }
local best = {}        -- a legközelebbi járművek: { dist, m, layout, pattern, t }
local bestCount = 0
local bestMax = math.max(ELS_ENV.maxVehicles, ELS_ENV.native.maxVehicles)

for i = 1, bestMax do best[i] = {} end

local function dlRunning()
    local res = getResourceFromName(DL)
    return res and getResourceState(res) == "running"
end

local function dl()
    return exports[DL]
end

local function moved(slot, x, y, z)
    return slot.parked or math.abs(x - slot.x) + math.abs(y - slot.y) + math.abs(z - slot.z) > MOVE_EPSILON
end

------------------------------------------------------------
-- HÁTTEREK
------------------------------------------------------------

local backends = {}

-- dynamic_lighting: a kikapcsolt fény a helyén marad 0 erősséggel
backends.dynamic = {
    maxVehicles = function() return ELS_ENV.maxVehicles end,

    create = function()
        local light = dl():createPointLight(0, 0, PARK_Z, 0, 0, 0, 0, ELS_ENV.radius, true)
        return light and { light = light, parked = true, on = false } or nil
    end,

    park = function(slot)
        if slot.parked then return end
        dl():setLightPosition(slot.light, 0, 0, PARK_Z)
        slot.parked = true
    end,

    set = function(slot, x, y, z, on, r, g, b)
        if moved(slot, x, y, z) then
            dl():setLightPosition(slot.light, x, y, z)
            slot.x, slot.y, slot.z, slot.parked = x, y, z, false
        end
        -- csak változáskor hívjuk, mert minden hívás újrarendezi a dynamic_lighting fényeit
        if on ~= slot.on or r ~= slot.r or g ~= slot.g or b ~= slot.b then
            dl():setLightColor(slot.light, r, g, b, on and ELS_ENV.intensity or 0)
            slot.on, slot.r, slot.g, slot.b = on, r, g, b
        end
    end,

    destroy = function(slot)
        if dlRunning() then dl():destroyLight(slot.light) end
    end,
}

-- createLight: a kikapcsolt fény a pálya alá kerül (a fekete szín a földi
-- fényfoltot is sötétítené)
backends.native = {
    maxVehicles = function() return ELS_ENV.native.maxVehicles end,

    create = function()
        local light = createLight(0, 0, 0, PARK_Z, ELS_ENV.native.radius, 0, 0, 0, 0, 0, 0, ELS_ENV.native.shadow)
        return light and { light = light, parked = true } or nil
    end,

    park = function(slot)
        if slot.parked then return end
        setElementPosition(slot.light, 0, 0, PARK_Z)
        slot.parked = true
    end,

    set = function(slot, x, y, z, on, r, g, b)
        if not on then
            backends.native.park(slot)
            return
        end
        -- a fény ott látszik, ahol a játékos (a kamera) van
        local dim, int = getElementDimension(localPlayer), getCameraInterior()
        if dim ~= slot.dim then setElementDimension(slot.light, dim) slot.dim = dim end
        if int ~= slot.int then setElementInterior(slot.light, int) slot.int = int end
        if moved(slot, x, y, z) then
            setElementPosition(slot.light, x, y, z)
            slot.x, slot.y, slot.z, slot.parked = x, y, z, false
        end
        if r ~= slot.r or g ~= slot.g or b ~= slot.b then
            setLightColor(slot.light, r, g, b)
            slot.r, slot.g, slot.b = r, g, b
        end
    end,

    destroy = function(slot)
        if isElement(slot.light) then destroyElement(slot.light) end
    end,
}

------------------------------------------------------------
-- MÓD
------------------------------------------------------------

local function wantedBackend()
    if not ELS_ENV.enabled then return nil end
    local m = mode or ELS_ENV.defaultMode
    if m == "dynamic" and dlRunning() then return "dynamic" end
    return "native"
end

local function destroyPool()
    local b = active and backends[active]
    if b then
        for _, slot in ipairs(pool) do b.destroy(slot) end
    end
    pool = {}
end

-- a kívánt hátteret állítja be; nil, ha a környezeti fény ki van kapcsolva
local function ensureBackend()
    local want = wantedBackend()
    if want ~= active then
        destroyPool()
        active = want
    end
    return active and backends[active]
end

local function createPool(b)
    for i = 1, b.maxVehicles() * ELS_ENV.perVehicle do
        local slot = b.create()
        if not slot then break end
        pool[i] = slot
    end
end

function getEnvLightMode()
    return mode or ELS_ENV.defaultMode
end

function setEnvLightMode(m)
    if m ~= "dynamic" and m ~= "native" then return false end
    mode = m
    ensureBackend() -- a régi háttér fényei azonnal eltűnnek
    return true
end

------------------------------------------------------------
-- KÉPKOCKÁNKÉNTI FRISSÍTÉS (beacons.lua hívja)
------------------------------------------------------------

local frameMax = ELS_ENV.maxVehicles -- az aktuális képkocka járműkorlátja

function EnvLight.begin()
    bestCount = 0
    local b = backends[wantedBackend() or "dynamic"]
    frameMax = math.min(b.maxVehicles(), bestMax)
end

-- jelölt jármű; rendezetten megtartjuk a legközelebbi frameMax darabot
function EnvLight.consider(dist, m, layout, pattern, t)
    if dist > ELS_ENV.range or not layout.env or #layout.env == 0 then return end

    local pos = bestCount + 1
    while pos > 1 and best[pos - 1].dist > dist do
        pos = pos - 1
    end
    if pos > frameMax then return end

    local last = math.min(bestCount + 1, frameMax)
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
    local b = ensureBackend()
    if not b then return end
    if #pool == 0 then createPool(b) end

    local used = 0
    for i = 1, bestCount do
        local c = best[i]
        for _, e in ipairs(c.layout.env) do
            local slot = pool[used + 1]
            if not slot then break end
            used = used + 1
            local x, y, z = Beacons.toWorld(c.m, e.x, e.y, e.z)
            b.set(slot, x, y, z, Beacons.isGroupOn(c.pattern, e.group, c.t), e.r, e.g, e.b)
        end
        c.m, c.layout = nil, nil
    end

    for i = used + 1, #pool do
        b.park(pool[i])
    end
end

-- minden fény kikapcsolása (nincs több világító jármű)
function EnvLight.release()
    bestCount = 0
    if #pool == 0 then return end
    local b = ensureBackend()
    if not b then return end
    for _, slot in ipairs(pool) do
        b.park(slot)
    end
end

------------------------------------------------------------
-- ÉLETCIKLUS
------------------------------------------------------------

-- a dynamic_lighting fényei az ő elemei: ha az leáll, velük együtt eltűnnek
-- (a következő képkockában a natív háttér veszi át)
addEventHandler("onClientResourceStop", root, function(res)
    if active == "dynamic" and getResourceName(res) == DL then
        pool = {}
        active = nil
    end
end)

-- a dynamic_lighting (újra)indulásakor a "dynamic" mód visszaáll rá
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == DL and #pool > 0 then
        ensureBackend()
    end
end)

-- a mi leállásunkkor viszont nekünk kell törölni őket
addEventHandler("onClientResourceStop", resourceRoot, function()
    destroyPool()
    active = nil
end)
