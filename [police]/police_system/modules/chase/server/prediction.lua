-- police_system / modules/chase/server/prediction.lua
-- Route prediction from level 2 (not while evading): with a v_radar GPS destination (gpsDestination on the
-- suspect's vehicle) the navmesh route to it, otherwise the road ahead on the lane graph (ai_land_traffic
-- predictRoadPath: straight on where possible, 300-500 m). Refreshed every PREDICT_EVERY, and only when the suspect
-- left the predicted path by more than PREDICT_DEVIATION. The AI module picks interception points from it.

local PR = POL.module("prediction", { pending = {} })
local C = POLICE.CHASE

local function offPath(c, x, y)
    local pts = c.predicted
    if not pts or #pts == 0 then return true end
    local best = math.huge
    for _, p in ipairs(pts) do
        local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
        if d < best then best = d end
    end
    return math.sqrt(best) > C.PREDICT_DEVIATION
end

local function truncate(points, x, y)
    local out, len = {}, 0
    local px, py = x, y
    for _, p in ipairs(points) do
        local px2, py2, pz2 = tonumber(p[1] or p.x), tonumber(p[2] or p.y), tonumber(p[3] or p.z)
        if px2 then
            len = len + math.sqrt((px2 - px) ^ 2 + (py2 - py) ^ 2)
            px, py = px2, py2
            out[#out + 1] = { px2, py2, pz2 or 0 }
            if len >= C.PREDICT_LENGTH then break end
        end
    end
    return out
end

function PR.update(c)
    local veh = isElement(c.suspect) and getElementType(c.suspect) ~= "vehicle" and getPedOccupiedVehicle(c.suspect)
    if not veh then c.predicted = nil return end
    local x, y, z = getElementPosition(veh)
    if c.predicted and not offPath(c, x, y) then return end
    local _, _, rz = getElementRotation(veh)
    local gps = getElementData(veh, "gpsDestination")
    if type(gps) == "table" and tonumber(gps[1]) and POL.running("navmesh") and not PR.pending[c] then
        local ok, id = pcall(function()
            return exports.navmesh:requestRoute("vehicle", x, y, z, tonumber(gps[1]), tonumber(gps[2]), tonumber(gps[3]) or z,
                { profile = "car" })
        end)
        if ok and id then
            PR.pending[id] = c
            PR.pending[c] = true
            return
        end
    end
    if POL.running("ai_land_traffic") then
        local ok, pts = pcall(function() return exports.ai_land_traffic:predictRoadPath(x, y, z, rz, C.PREDICT_LENGTH) end)
        c.predicted = ok and type(pts) == "table" and pts or nil
    end
end

addEvent("onNavmeshRouteReady")
addEventHandler("onNavmeshRouteReady", resourceRoot, function(id, result)
    local c = PR.pending[id]
    if not c then return end
    PR.pending[id] = nil
    PR.pending[c] = nil
    if type(result) == "table" and type(result.points) == "table" and isElement(c.suspect) then
        local x, y = getElementPosition(c.suspect)
        c.predicted = truncate(result.points, x, y)
    end
end)
