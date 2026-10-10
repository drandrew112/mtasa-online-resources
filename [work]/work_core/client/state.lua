-- Client state: the registered works (synced from the server), the marker the local player
-- stands in, client-side queries/exports and the onClientPlayerWorkChange event.

Works = {}                         -- id -> { id, name, description, color, skins }
CurrentMarker = nil                -- work marker the local player can use right now

addEvent("work:sync", true)
addEventHandler("work:sync", resourceRoot, function(t)
    Works = type(t) == "table" and t or {}
end)

addEvent("work:notify", true)
addEventHandler("work:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(tostring(title or "Work"), tostring(text or ""))
end)

addEvent("work:clipboard", true)
addEventHandler("work:clipboard", resourceRoot, function(text)
    if type(text) == "string" then setClipboard(text) end
end)

---------------------------------------------------------------- exports / queries

function getPlayerWork(player)
    return isElement(player) and getElementData(player, WORK_DATA.PLAYER_WORK) or false
end

function isPlayerOnDuty(player, workId)
    local w = getPlayerWork(player)
    if not w then return false end
    return workId == nil or w == workId
end

function getWorkPlayers(workId)
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, WORK_DATA.PLAYER_WORK) == workId then list[#list + 1] = p end
    end
    return list
end

function getWork(id)
    return Works[id] or false
end

function getWorks()
    return Works
end

-- Work levels (synced by the server in work.levels; see server/levels.lua)
local function levelData(player, workId)
    local t = isElement(player) and getElementData(player, WORK_DATA.PLAYER_LEVELS)
    return type(t) == "table" and t[workId] or nil
end

function getPlayerWorkLevel(player, workId)
    local d = levelData(player, workId)
    return d and d.level or 1
end

function getPlayerWorkXp(player, workId)
    local d = levelData(player, workId)
    return d and d.xp or 0
end

function getPlayerWorkLevelName(player, workId)
    local w, lv, best = Works[workId], getPlayerWorkLevel(player, workId), nil
    if not (w and w.levels) then return false end
    for k in pairs(w.levels.names) do
        if k <= lv and (not best or k > best) then best = k end
    end
    return best and w.levels.names[best] or false
end

function hasWorkLevel(player, workId, level)
    return getPlayerWorkLevel(player, workId) >= (tonumber(level) or 1)
end

function getVehicleWork(vehicle)
    return isElement(vehicle) and getElementData(vehicle, WORK_DATA.VEHICLE_WORK) or false
end

-- onClientPlayerWorkChange (newWorkId | false, oldWorkId | false), source = the player
addEvent("onClientPlayerWorkChange")
addEventHandler("onClientElementDataChange", root, function(key, old, new)
    if key ~= WORK_DATA.PLAYER_WORK or getElementType(source) ~= "player" then return end
    triggerEvent("onClientPlayerWorkChange", source, new or false, old or false)
end)

---------------------------------------------------------------- marker detection

-- Can the local player use this marker in the current state?
function canUseMarker(marker, kind)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if kind == "duty" then
        return not vehicle
    end
    -- vehicle marker: only for the players on duty in its work
    if getPlayerWork(localPlayer) ~= getElementData(marker, WORK_DATA.MARKER_WORK) then return false end
    if not vehicle then return true end
    -- in a vehicle: only the driver of their own work vehicle (to return it)
    return getVehicleController(vehicle) == localPlayer
        and getElementData(vehicle, WORK_DATA.VEHICLE_OWNER) == localPlayer
end

local function isInside(marker, px, py, pz)
    local x, y, z = getElementPosition(marker)
    if pz < z - 1 or pz > z + WORK.MARKER_HEIGHT then return false end
    return getDistanceBetweenPoints2D(px, py, x, y) <= getMarkerSize(marker) / 2 + WORK.MARKER_EXTRA_RADIUS
end

local function poll()
    local found = nil
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local e = getPedOccupiedVehicle(localPlayer) or localPlayer
    local px, py, pz = getElementPosition(e)
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        local kind = getElementData(m, WORK_DATA.MARKER_KIND)
        if kind and getElementDimension(m) == dim and getElementInterior(m) == int
            and isInside(m, px, py, pz) and canUseMarker(m, kind) then
            found = m
            break
        end
    end
    if found ~= CurrentMarker then
        CurrentMarker = found
        onCurrentMarkerChange(found)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(poll, WORK.POLL, 0)
end)
