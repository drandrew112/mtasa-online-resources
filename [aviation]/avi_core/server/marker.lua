if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ATC markers (config AVI.MARKERS). Standing in one and pressing the key opens the position login
-- of avi_controller (or the scope toggle when already logged in). The markers are visible only to
-- the players on duty in the work AVI.MARKER_WORK (work_core), and the server checks that too.

local markers = {}               -- marker -> config entry
local tutorialMarkers = {}       -- marker -> { player, position } (work_atc tutorial, createTutorialMarker)

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function applyVisibility()
    for marker in pairs(markers) do
        if isElement(marker) then
            if AVI.MARKER_WORK then
                -- hidden until work_core says who is on duty
                setElementVisibleTo(marker, root, false)
                if isRunning("work_core") then
                    exports.work_core:setElementVisibleToWork(marker, AVI.MARKER_WORK)
                end
            else
                setElementVisibleTo(marker, root, true)
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, def in ipairs(AVI.MARKERS) do
        local c = AVI.MARKER_COLOR
        local m = createMarker(def.x, def.y, def.z, "cylinder", AVI.MARKER_SIZE, c[1], c[2], c[3], c[4])
        if m then
            setElementInterior(m, def.interior or 0)
            setElementDimension(m, def.dimension or 0)
            setElementData(m, "avi.marker", def.name or "ATC")
            markers[m] = def
        end
    end
    applyVisibility()
end)

-- work_core (re)started: its visibility sets are gone
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, applyVisibility)

local function atWork(player)
    if not AVI.MARKER_WORK then return true end
    if not isRunning("work_core") then return false end
    return exports.work_core:isPlayerOnDuty(player, AVI.MARKER_WORK) == true
end

local last = {}
addEvent("avi:markerUse", true)
addEventHandler("avi:markerUse", resourceRoot, function(marker)
    local player = client
    local now = getTickCount()
    if last[player] and now - last[player] < 750 then return end
    last[player] = now
    if not (markers[marker] or tutorialMarkers[marker]) or not isElement(marker) then return end
    if getElementDimension(player) ~= getElementDimension(marker)
        or getElementInterior(player) ~= getElementInterior(marker) then return end
    local px, py, pz = getElementPosition(getPedOccupiedVehicle(player) or player)
    local x, y, z = getElementPosition(marker)
    if getDistanceBetweenPoints2D(px, py, x, y) > AVI.MARKER_SIZE / 2 + 3 or math.abs(pz - z) > 5 then return end
    local tut = tutorialMarkers[marker]
    if tut then
        -- tutorial console: only its player, no duty / rights needed
        if tut.player ~= player then return end
        if not isRunning("avi_controller") then
            aviNotify(player, L.msg("avi_core.marker.controller_software_is_not_running"))
            return
        end
        pcall(function() return exports.avi_controller:useTutorialConsole(player, tut.position) end)
        return
    end
    if not atWork(player) then
        aviNotify(player, L.msg("avi_core.marker.only_air_traffic_controllers_can_use"))
        return
    end
    if not hasATCAccess(player) then
        aviNotify(player, L.msg("avi_core.marker.you_do_not_have_any_atc"))
        return
    end
    if not isRunning("avi_controller") then
        aviNotify(player, L.msg("avi_core.marker.controller_software_is_not_running"))
        return
    end
    local ok, err = pcall(function() return exports.avi_controller:useATCConsole(player, markers[marker].available_positions) end)
    if not ok then
        aviNotify(player, L.msg("avi_core.marker.controller_software_needs_restart_restart_avi"))
        outputDebugString("[avi_core] useATCConsole failed: " .. tostring(err), 2)
    end
end)

addEventHandler("onPlayerQuit", root, function() last[source] = nil end)

-- ---------------------------------------------------------------- tutorial consoles (work_atc tutorial)
-- A copy of the ATC marker that offers `position` in the tutorial dimension, visible only to the
-- player. It opens the tutorial login of avi_controller (useTutorialConsole) instead of the live one.
-- The copy stands where the live marker offering that position stands (or at x, y, z when given).
-- -> marker | false
function createTutorialMarker(player, dimension, position, x, y, z, interior)
    if not isElement(player) then return false end
    local def
    for _, d in ipairs(AVI.MARKERS) do
        for _, p in ipairs(d.available_positions or {}) do
            if p == position then def = d end
        end
    end
    def = def or AVI.MARKERS[1]
    local c = AVI.MARKER_COLOR
    local m = createMarker(tonumber(x) or def.x, tonumber(y) or def.y, tonumber(z) or def.z, "cylinder", AVI.MARKER_SIZE,
        c[1], c[2], c[3], c[4])
    if not m then return false end
    setElementInterior(m, tonumber(interior) or def.interior or 0)
    setElementDimension(m, tonumber(dimension) or 0)
    setElementData(m, "avi.marker", def.name or "ATC")
    setElementVisibleTo(m, root, false)
    setElementVisibleTo(m, player, true)
    tutorialMarkers[m] = { player = player, position = position }
    return m
end

function destroyTutorialMarker(marker)
    if not tutorialMarkers[marker] then return false end
    tutorialMarkers[marker] = nil
    if isElement(marker) then destroyElement(marker) end
    return true
end

addEventHandler("onPlayerQuit", root, function()
    for m, t in pairs(tutorialMarkers) do
        if t.player == source then
            tutorialMarkers[m] = nil
            if isElement(m) then destroyElement(m) end
        end
    end
end)
