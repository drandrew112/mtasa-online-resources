-- ATC markers (config AVI.MARKERS). Standing in one and pressing the key opens the position login
-- of avi_controller (or the scope toggle when already logged in). The markers are visible only to
-- the players on duty in the work AVI.MARKER_WORK (work_core), and the server checks that too.

local markers = {}               -- marker -> config entry

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
    if not markers[marker] or not isElement(marker) then return end
    if getElementDimension(player) ~= getElementDimension(marker)
        or getElementInterior(player) ~= getElementInterior(marker) then return end
    local px, py, pz = getElementPosition(getPedOccupiedVehicle(player) or player)
    local x, y, z = getElementPosition(marker)
    if getDistanceBetweenPoints2D(px, py, x, y) > AVI.MARKER_SIZE / 2 + 3 or math.abs(pz - z) > 5 then return end
    if not atWork(player) then
        aviNotify(player, "Only air traffic controllers can use this.")
        return
    end
    if not hasATCAccess(player) then
        aviNotify(player, "You do not have any ATC rights.")
        return
    end
    if not isRunning("avi_controller") then
        aviNotify(player, "The controller software is not running.")
        return
    end
    local ok, err = pcall(function() return exports.avi_controller:useATCConsole(player) end)
    if not ok then
        aviNotify(player, "The controller software needs a restart (restart avi_controller).")
        outputDebugString("[avi_core] useATCConsole failed: " .. tostring(err), 2)
    end
end)

addEventHandler("onPlayerQuit", root, function() last[source] = nil end)
