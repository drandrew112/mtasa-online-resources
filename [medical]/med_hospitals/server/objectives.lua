-- v_radar objective (yellow blip + auto route) to a hospital, one per player.
-- Removed automatically within HOSP.ARRIVE_RADIUS of the hospital, on quit and on reload.

local objectives = {}  -- [player] = { id, hospital }

local function radarRunning() return isResourceRunning("v_radar") end

function removePlayerObjective(player)
    local o = objectives[player]
    if not o then return false end
    objectives[player] = nil
    if isElement(player) and radarRunning() then exports.v_radar:removeObjective(player, o.id) end
    return true
end

-- -> objectiveId | false, error
function setPlayerObjective(player, h, label)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "Invalid player" end
    if not radarRunning() then return false, "v_radar is not running" end
    removePlayerObjective(player)
    local id = exports.v_radar:addObjective(player, h.x, h.y, h.z, label or h.name)
    if not id then return false, "v_radar refused the objective" end
    objectives[player] = { id = id, hospital = h }
    return id
end

-- Nearest hospital to a point (same interior / dimension when given) -> hospital, distance
function findNearestHospital(x, y, z, interior, dimension)
    local best, bestDist
    for _, h in ipairs(Hospitals.list) do
        if (not interior or h.interior == interior) and (not dimension or h.dimension == dimension) then
            local d = getDistanceBetweenPoints3D(x, y, z, h.x, h.y, h.z)
            if not bestDist or d < bestDist then best, bestDist = h, d end
        end
    end
    return best, bestDist
end

local function checkArrivals()
    for player, o in pairs(objectives) do
        if not isElement(player) then
            objectives[player] = nil
        else
            local x, y = getElementPosition(player)
            if getDistanceBetweenPoints2D(x, y, o.hospital.x, o.hospital.y) <= HOSP.ARRIVE_RADIUS then
                removePlayerObjective(player)
            end
        end
    end
end

UnloadHandlers[#UnloadHandlers + 1] = function()
    for player in pairs(objectives) do removePlayerObjective(player) end
end

addEventHandler("onPlayerQuit", root, function()
    objectives[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(checkArrivals, 1000, 0)
end)
