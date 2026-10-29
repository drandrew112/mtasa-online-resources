if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The 3D cards above the work markers, drawn by ui_core (createMarkerUI). The card texts and the
-- level box depend on the player, so they are sent as per-player meta, and only to the players
-- within the card's radius (onMarkerUIStreamIn). Vehicle markers are labelled only for the
-- players on duty in their work.

local RED = { 218, 54, 51 }

local function uiRunning()
    local res = getResourceFromName("ui_core")
    return res and getResourceState(res) == "running"
end

local function uiCall(fn, ...)
    if not uiRunning() then return false end
    return exports.ui_core[fn](exports.ui_core, ...)
end

local uiIds = {}        -- ui id -> marker
local nextId = 0

local function define(marker, m)
    local work = Works[m.work]
    if not work then return end
    local duty = m.kind == "duty"
    uiCall("createMarkerUI", m.uiId, {
        element = marker,
        type = duty and "work_duty" or "work_veh",
        color = work.color,
        name = work.name,
        title = duty and L.msg("work_core.labels.go_on_duty") or L.msg("work_core.labels.work_vehicles"),
        hidden = not duty,  -- vehicle cards: revealed by the meta of the players on duty
        radius = WORK.LABEL_DISTANCE, fullRadius = WORK.LABEL_FULL_DISTANCE,
        minScale = WORK.LABEL_MIN_SCALE, height = WORK.LABEL_HEIGHT,
    })
end

-- called by baseMarker (server/markers.lua)
function registerMarkerUI(marker, m)
    nextId = nextId + 1
    m.uiId = "m" .. nextId
    uiIds[m.uiId] = marker
    define(marker, m)
    addEventHandler("onElementDestroy", marker, function()
        uiIds[m.uiId] = nil
        if uiRunning() then uiCall("removeMarkerUI", m.uiId) end
    end, false)
end

-- the per-player fields of a card (labelFor of the old client labels)
local function metaFor(player, m)
    local work = Works[m.work]
    if not work then return nil end
    local mine = getPlayerWork(player)
    local key = WORK.KEY:upper()

    if m.kind == "duty" then
        local meta
        if mine and mine ~= m.work then
            local other = Works[mine]
            meta = { color = RED, icon = "!", title = work.name, name = work.name,
                     hint = L.msg("work_core.labels.you_are_working_as_go_off", { mine = other and other.name or mine }) }
        elseif mine == m.work then
            meta = { title = L.msg("work_core.labels.on_duty"),
                     hint = L.msg("work_core.labels.press_outfit_go_off_duty", { key = key }) }
        else
            meta = { hint = L.msg("work_core.labels.press_choose_your_outfit", { key = key }) }
        end
        local info = getWorkLevelInfo(player, m.work)
        if info then
            meta.level, meta.levelName = info.level, info.name or nil
            meta.xp, meta.xpFrom, meta.xpTo = info.xp, info.from, info.to or nil
        end
        return meta
    end

    if mine ~= m.work then return { hidden = true } end
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle and getElementData(vehicle, WORK_DATA.VEHICLE_OWNER) == player then
        return { hidden = false, hint = L.msg("work_core.labels.press_return_vehicle", { key = key }) }
    end
    return { hidden = false, hint = L.msg("work_core.labels.press_request_vehicle", { key = key }) }
end

local function push(player, id)
    local marker = uiIds[id]
    local m = marker and Markers[marker]
    if m then uiCall("setMarkerUIMeta", id, metaFor(player, m), player) end
end

local nearby = {}       -- player -> { [ui id] = true } cards within range of the player

addEvent("onMarkerUIStreamIn")
addEventHandler("onMarkerUIStreamIn", resourceRoot, function(id, player)
    nearby[player] = nearby[player] or {}
    nearby[player][id] = true
    push(player, id)
end)

addEvent("onMarkerUIStreamOut")
addEventHandler("onMarkerUIStreamOut", resourceRoot, function(id, player)
    if nearby[player] then nearby[player][id] = nil end
end)

addEventHandler("onPlayerQuit", root, function() nearby[source] = nil end)

-- the player's state changed: refresh the cards he is near right now
local function refreshPlayer(player)
    for id in pairs(nearby[player] or {}) do push(player, id) end
end

local function refreshSource() refreshPlayer(source) end
addEventHandler("onPlayerWorkDutyStart", root, refreshSource)
addEventHandler("onPlayerWorkDutyEnd", root, refreshSource)
addEventHandler("onPlayerWorkXpGain", root, refreshSource)
addEventHandler("onPlayerWorkLevelChange", root, refreshSource)
addEventHandler("onVehicleEnter", root, function(player) refreshPlayer(player) end)
addEventHandler("onVehicleExit", root, function(player) refreshPlayer(player) end)

-- ui_core restarted: define every card again
addEvent("onMarkerUISystemStart")
addEventHandler("onMarkerUISystemStart", root, function()
    for _, marker in pairs(uiIds) do
        local m = Markers[marker]
        if m then define(marker, m) end
    end
end)
