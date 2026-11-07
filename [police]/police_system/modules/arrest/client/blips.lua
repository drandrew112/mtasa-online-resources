-- Handover point of every station as a v_radar interior blip (jail icon) on the station's minimap plan.
-- Only police on duty see it: created when the unit state appears, removed when it goes.
-- The interior map id = POLICE.STATIONS[].radarMap (lspd -> ls_pd).

local blipIds = {}

local function radarRunning()
    local r = getResourceFromName("v_radar")
    return r and getResourceState(r) == "running"
end

local function clear()
    if radarRunning() then exports.v_radar:clearInteriorBlips() end
    blipIds = {}
end

local function sync()
    clear()
    if not POL.onDuty() or not radarRunning() then return end
    for _, st in ipairs(POLICE.STATIONS) do
        local h = st.handover
        if h and st.radarMap then
            blipIds[#blipIds + 1] = exports.v_radar:addInteriorBlip(st.radarMap, h[1], h[2], h[3], "jail", "Handover")
        end
    end
end

POL.on("unit", function(u, old)
    if (u and true or false) ~= (old and true or false) then sync() end
end)
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "v_radar" then sync() end
end)
addEventHandler("onClientResourceStart", resourceRoot, function() setTimer(sync, 1000, 1) end)
addEventHandler("onClientResourceStop", resourceRoot, clear)
