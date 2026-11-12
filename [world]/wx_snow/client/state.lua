-- wx_snow :: client state
--
-- Server state ({ level, from, at } + server clock) or a local preview (/snow <0-5>, v_admin
-- Preview), the player's quality setting, and where the camera is:
--   indoor  = interior ~= 0 or inside a maps_loader "indoor" box -> no snow at all
--   covered = under a roof (roof map / line of sight up)         -> no snowfall, ground stays
-- Modules subscribe with snowOnChange(fn(reason)).

CS = {
    server = { level = 0, from = 0, at = 0 },
    offset = 0,              -- server clock - client clock (s)
    preview = nil,           -- local state (same shape, server clock)
    coverFixed = nil,        -- /snow cover
    quality = SNOW.DEFAULT_QUALITY,
    debug = false,
    indoor = false,          -- interior or indoor zone: no snowfall / fog / colours
    interior = false,        -- interior ~= 0: the ground layers draw nothing (same textures inside)
    indoorWhy = nil,         -- "interior" | "zone"
    covered = false,
    zones = {},              -- maps_loader indoor boxes (all active maps)
    nearBoxes = {},          -- nearest SNOW.INDOOR_BOXES of them
    received = false,
}

local listeners = {}

function snowOnChange(fn) listeners[#listeners + 1] = fn end

function snowChanged(reason)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, reason)
        if not ok then outputDebugString("[wx_snow] listener: " .. tostring(err), 1) end
    end
end

function snowNow() return getRealTime().timestamp + CS.offset end

function snowActiveState() return CS.preview or CS.server end

-- -> level, coverage 0..1, level params
function snowCurrent()
    local st = snowActiveState()
    local p, lvl = snowLevelParams(st.level)
    local cov = CS.coverFixed or snowCoverageAt(st, snowNow())
    return lvl, cov, p
end

-- the effect may run at all (quality on, outdoors)
function snowEnabled()
    return CS.quality ~= "off" and not CS.indoor
end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end
snowResourceRunning = running

-------------------------------------------------------------------------------- notifications

function snowMessage(key, params)
    local text = L(key, params)
    if running("ui_core") then
        pcall(function() exports.ui_core:addNotification(L("wx_snow.title"), text) end)
    else
        outputConsole("[Snow] " .. text)
    end
end

addEvent("wx_snow:notify", true)
addEventHandler("wx_snow:notify", resourceRoot, function(key, params)
    snowMessage(key, params)
end)

-------------------------------------------------------------------------------- server state

addEvent("wx_snow:state", true)
addEventHandler("wx_snow:state", resourceRoot, function(st, serverNow)
    if type(st) ~= "table" then return end
    CS.offset = (tonumber(serverNow) or getRealTime().timestamp) - getRealTime().timestamp
    local first = not CS.received
    CS.received = true
    local oldLevel = CS.server.level
    CS.server = { level = tonumber(st.level) or 0, from = tonumber(st.from) or 0, at = tonumber(st.at) or 0 }
    if first or oldLevel ~= CS.server.level then snowChanged("level") end
end)

-------------------------------------------------------------------------------- preview / local commands

-- level 0..5, or false = back to the server state
function setSnowPreview(level, instant)
    if level == false or level == nil then
        CS.preview, CS.coverFixed = nil, nil
    else
        CS.preview = snowStateChange(snowActiveState(), level, snowNow(), instant == true)
        if CS.coverFixed then CS.coverFixed = nil end
    end
    snowChanged("level")
    return true
end

function getSnowQuality() return CS.quality end

-- ui_pause keeps it on the account; the private file covers a wx_snow restart / before login
local QUALITY_FILE = "@quality.txt"

local function loadQuality()
    if not fileExists(QUALITY_FILE) then return end
    local f = fileOpen(QUALITY_FILE, true)
    if not f then return end
    local q = fileRead(f, math.min(16, fileGetSize(f)))
    fileClose(f)
    if q == "off" or q == "low" or q == "high" then CS.quality = q end
end

local function saveQuality()
    if fileExists(QUALITY_FILE) then fileDelete(QUALITY_FILE) end
    local f = fileCreate(QUALITY_FILE)
    if f then
        fileWrite(f, CS.quality)
        fileClose(f)
    end
end

function setSnowQuality(q)
    if q ~= "off" and q ~= "low" and q ~= "high" then return false end
    if q == CS.quality then return true end
    CS.quality = q
    saveQuality()
    snowChanged("quality")
    return true
end

function getSnowLevel() return (snowCurrent()) end

function getSnowCoverage()
    local _, cov = snowCurrent()
    return cov
end

function isSnowing() return (snowCurrent()) > 0 end

-- snow is drawn where the camera is now
function isSnowVisibleHere() return snowEnabled() and (snowCurrent()) > 0 end

-------------------------------------------------------------------------------- where is the camera

local function inBox(b, x, y, z, m)
    return x >= b[1] - m and x <= b[4] + m and y >= b[2] - m and y <= b[5] + m and z >= b[3] - m and z <= b[6] + m
end

-- SNOW.CLEAR_AREAS: always snow free (ground + flakes), not "indoor" for the camera
local CLEAR = {}
for _, a in ipairs(SNOW.CLEAR_AREAS or {}) do
    CLEAR[#CLEAR + 1] = { a.min[1], a.min[2], a.min[3], a.max[1], a.max[2], a.max[3], name = a.name }
end

-- maps_loader indoor boxes; a map in SNOW.ZONE_MASKS uses those boxes instead (its loader box is
-- bigger than the building and would leave a snow free strip outside)
local zonesKey = ""
local function refreshZones()
    local list = {}
    if running("maps_loader") then
        local ok, res = pcall(function() return exports.maps_loader:getIndoorZones() end)
        list = ok and type(res) == "table" and res or {}
    end
    local out, replaced = {}, {}
    for _, b in ipairs(list) do
        local over = SNOW.ZONE_MASKS and SNOW.ZONE_MASKS[b.map]
        if over then
            if not replaced[b.map] then
                replaced[b.map] = true
                for _, o in ipairs(over) do out[#out + 1] = { o[1], o[2], o[3], o[4], o[5], o[6], map = b.map } end
            end
        else
            out[#out + 1] = b
        end
    end
    local key = toJSON(out)
    if key ~= zonesKey then
        zonesKey = key
        CS.zones = out
    end
end

local function nearestBoxes(cx, cy, cz)
    local scored = {}
    local list = {}
    for _, b in ipairs(CLEAR) do list[#list + 1] = b end
    -- with a baked roof map the floors under a roof are known exactly: the loader boxes (often
    -- reaching past the walls onto open ground) are only used for the camera, not as masks
    if not (ROOF and ROOF.isLoaded and ROOF.isLoaded()) then
        for _, b in ipairs(CS.zones) do list[#list + 1] = b end
    end
    for _, b in ipairs(list) do
        local dx = math.max(b[1] - cx, 0, cx - b[4])
        local dy = math.max(b[2] - cy, 0, cy - b[5])
        local dz = math.max(b[3] - cz, 0, cz - b[6])
        scored[#scored + 1] = { b = b, d = dx * dx + dy * dy + dz * dz }
    end
    table.sort(scored, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(SNOW.INDOOR_BOXES, #scored) do out[i] = scored[i].b end
    return out
end

local function sameBoxes(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function checkPlace()
    local cx, cy, cz = getCameraMatrix()
    local why = nil
    if getElementInterior(localPlayer) ~= 0 or getCameraInterior() ~= 0 then
        why = "interior"
    else
        for _, b in ipairs(CS.zones) do
            if inBox(b, cx, cy, cz, 0.3) then why = "zone" break end
        end
    end
    local indoor = why ~= nil
    local interior = why == "interior"
    local covered = false
    if not indoor then
        local roofZ = ROOF and ROOF.heightAt and ROOF.heightAt(cx, cy)
        if roofZ then
            covered = roofZ > cz + 0.4
        else
            covered = not isLineOfSightClear(cx, cy, cz + 0.3, cx, cy, cz + 40, true, false, false, true, false, true)
        end
    end
    local boxes = nearestBoxes(cx, cy, cz)
    local boxesChanged = not sameBoxes(boxes, CS.nearBoxes)
    CS.nearBoxes = boxes
    if indoor ~= CS.indoor or interior ~= CS.interior then
        CS.indoor, CS.interior, CS.indoorWhy = indoor, interior, why
        snowChanged("indoor")
    end
    CS.indoorWhy = why
    if covered ~= CS.covered then
        CS.covered = covered
        snowChanged("covered")
    end
    if boxesChanged then snowChanged("boxes") end
end

-------------------------------------------------------------------------------- lifecycle

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadQuality()
    refreshZones()
    checkPlace()
    setTimer(checkPlace, SNOW.CHECK_MS, 0)
    -- going out / in: switch in the same frame, not on the next timer tick
    addEventHandler("onClientElementInteriorChange", localPlayer, function() checkPlace() end, false)
    addEventHandler("onClientElementDimensionChange", localPlayer, function() checkPlace() end, false)
    setTimer(refreshZones, 2000, 0)
    triggerServerEvent("wx_snow:hello", resourceRoot)
end)

-------------------------------------------------------------------------------- /snow on this client

local function info(server)
    local lvl, cov = snowCurrent()
    local st = snowActiveState()
    local eta = CS.coverFixed and 0 or snowCoverageEta(st, snowNow())
    snowMessage("wx_snow.cmd.info_server", {
        level = server.level, target = server.target, source = L("wx_snow.source." .. tostring(server.source)),
        coverage = math.floor((server.coverage or 0) * 100 + 0.5), weekly = server.weekly,
        dynamic = server.dynamic and L("wx_snow.yes") or L("wx_snow.no"),
        minutes = math.ceil((server.eta or 0) / 60),
    })
    local d = getSnowDebugState()
    snowMessage("wx_snow.cmd.info_client", {
        level = lvl, coverage = math.floor(cov * 100 + 0.5), minutes = math.ceil(eta / 60),
        preview = CS.preview and L("wx_snow.yes") or L("wx_snow.no"), quality = L("wx_snow.quality." .. CS.quality),
        place = CS.indoor and L("wx_snow.place." .. tostring(CS.indoorWhy)) or (CS.covered and L("wx_snow.place.covered") or L("wx_snow.place.outside")),
        shaders = d.groundShaders, attached = d.groundAttached and L("wx_snow.yes") or L("wx_snow.no"),
        roof = d.roofMap and L("wx_snow.yes") or L("wx_snow.no"), flakes = d.flakesDrawn,
    })
end

SNOW_COMMANDS = {
    info = function(a) info(a) end,
    preview = function(a)
        setSnowPreview(a.level, a.instant)
        snowMessage("wx_snow.cmd.preview_set", { level = a.level, name = L("wx_snow.level." .. a.level) })
    end,
    cover = function(a)
        CS.coverFixed = tonumber(a.value)
        snowChanged("cover")
        snowMessage("wx_snow.cmd.cover_set", { coverage = math.floor(CS.coverFixed * 100 + 0.5) })
    end,
    reset = function()
        setSnowPreview(false)
        snowMessage("wx_snow.cmd.preview_reset")
    end,
    debug = function()
        CS.debug = not CS.debug
        snowChanged("debug")
        snowMessage(CS.debug and "wx_snow.cmd.debug_on" or "wx_snow.cmd.debug_off")
    end,
    quality = function(a)
        setSnowQuality(a.value)
        snowMessage("wx_snow.cmd.quality_set", { quality = L("wx_snow.quality." .. a.value) })
    end,
}

addEvent("wx_snow:cmd", true)
addEventHandler("wx_snow:cmd", resourceRoot, function(action, args)
    local fn = SNOW_COMMANDS[action]
    if fn then fn(type(args) == "table" and args or {}) end
end)
