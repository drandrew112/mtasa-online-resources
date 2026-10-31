-- police_system / core/server/main.lua
-- The last server script: shared helpers that need several modules, the external API (exports, events) and the
-- start / stop of every module. External API (docs/plan "Külső API"):
--   addWanted(player, reasonId, level?), getWanted(player), clearWanted(player, why)  (wanted.lua)
--   hasPoliceRight(player), setPoliceRight(player, bool)                               (rights.lua)
--   isPoliceVehicle(veh), isElementCuffed(el), radioCommand(player, id, args), getPublicStats()
--   createPoliceCall(player, title, description) (ui_phone), getPublicPolice() (gov_web)
-- Events (source = this resourceRoot): onPlayerWantedChange, onPlayerWantedEvaded, onPoliceArrest, onPoliceFineIssued,
-- onPoliceSystemStart (work_police gives the rights back).

addEvent("onPoliceArrest")        -- (suspect, officer | false, kind "player" | "ai")
addEvent("onPoliceFineIssued")    -- (subjectInfo, btkId, amount, officer)
addEvent("onPoliceSystemStart")   -- (), source = resourceRoot

-- model + 598 only with the hu_pd paintjob (the EMS doctor car is a 598 too); the 432 tank is AI only
function isPoliceVehicle(veh)
    local ok, def = isPoliceModelVehicle(veh)
    return ok and not def.aiOnly or false
end

function isElementCuffed(el) return POL.arrest.isCuffed(el) end

-- a police vehicle of a player unit or an AI unit
function POL.isPoliceVehicleOrAI(veh)
    return POL.ai.vehicles[veh] ~= nil or isPoliceVehicle(veh)
end

-- any police (AI officer / vehicle, officer on duty, police vehicle) within r of a point
function POL.policeNear(x, y, z, r, except)
    local r2 = r * r
    local function near(el)
        local ex, ey, ez = getElementPosition(el)
        return (ex - x) ^ 2 + (ey - y) ^ 2 + (ez - z) ^ 2 <= r2
    end
    for veh in pairs(POL.ai.vehicles) do if isElement(veh) and near(veh) then return true end end
    for ped in pairs(POL.ai.peds) do if isElement(ped) and not isPedDead(ped) and near(ped) then return true end end
    for _, p in ipairs(POL.units.onDuty()) do if p ~= except and near(p) then return true end end
    for _, v in ipairs(getElementsWithinRange(x, y, z, r, "vehicle")) do
        if isPoliceVehicle(v) and getVehicleController(v) and getVehicleController(v) ~= except then return true end
    end
    return false
end

addEventHandler("onResourceStart", resourceRoot, function()
    POL.startAll()
    triggerEvent("onPoliceSystemStart", resourceRoot)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    POL.stopAll()
end)

-- /poldebug: module state for admins (server console + F8)
addCommandHandler("poldebug", function(p)
    if (tonumber(getElementData(p, "admin_level")) or 0) < POLICE.ADMIN_LEVEL then return end
    local n = function(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
    local s = ("[police] db=%s units=%d onDuty=%d wanted=%d chases=%d ai=%d aiPeds=%d stops=%d cuffed=%d jailed=%d calls=%d"):format(
        tostring(POL.db.ready), n(POL.units.list), #POL.units.onDuty(), n(POL.wanted.list), n(POL.chase.list),
        n(POL.ai.units), n(POL.ai.peds), n(POL.stop.list), n(POL.arrest.cuffed), n(POL.jail.list), n(POL.dispatch.calls))
    outputConsole(s, p)
    outputServerLog(s)
end)
