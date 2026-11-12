-- Hostages of the live scenes (role "hostage", 2026-11-12). The hostage kneels / holds its hands up among the
-- hostiles (ai_peds behaviour "hostage", never flees). The police (police_system interact menu) grabs it and leads
-- it out (escort without cuffs); let go within 5 m of a police car it is safe and waits there standing.
-- It leaves the scene with the ambulance whenever EMS is involved (a unit took the EMS task, or the police asked for
-- an ambulance: police_system sets "pol.ambulance" on the ped): "Hand over to EMS" makes it the medic's patient.
-- With no EMS at all and no hostile still fighting nearby the police may release it: an ordinary civilian walker,
-- removed as soon as nobody sees it and no player is close.
--
-- Element data (server only, police_system reads them when it builds its menus):
--   vsm.hostage          "held" | "safe" | "ems" | "released"
--   vsm.hostage.release  true while "Release" is allowed
-- police_system -> here: event onPoliceHostageAction (source = the ped; action "safe" | "ems" | "release", officer)

Hostage = { list = {} }   -- [ped] = { scene, entry, state }

local function ai() return vsmResourceRunning(VSM.AIPEDS) and exports[VSM.AIPEDS] or nil end

-- a system line in every open task of the scene (inter-agency channel)
local function sys(scene, key, params)
    for id, t in pairs(scene.tasks or {}) do
        if not t.closed then
            local a = Agencies.get(id)
            if a and a.system then pcall(a.system, t.id, key, params or {}) end
        end
    end
end

local function setState(ped, h, state)
    h.state = state
    setElementData(ped, "vsm.hostage", state, false)
end

function Hostage.add(scene, ped, entry)
    Hostage.list[ped] = { scene = scene, entry = entry, state = "held" }
    setElementData(ped, "vsm.hostage", "held", false)
    setElementData(ped, "vsm.hostage.release", false, false)
end

-- a hostile of the scene that still fights (alive, not down, not cuffed, not surrendered) within r of the ped
local function threatNear(h, ped, r)
    local x, y, z = getElementPosition(ped)
    for other, entry in pairs(h.scene.pedEntries or {}) do
        if entry.role == "hostile" and isElement(other) and not Npc.isDown(other) and not Npc.isCuffed(other)
            and not Npc.isSurrendered(other) then
            local ox, oy, oz = getElementPosition(other)
            if getDistanceBetweenPoints3D(x, y, z, ox, oy, oz) <= r then return true end
        end
    end
    return false
end

local function emsInvolved(h, ped)
    return h.scene.emsAssignedAt ~= nil or getElementData(ped, "pol.ambulance") == true
end

local function canRelease(h, ped)
    return (h.state == "held" or h.state == "safe") and not emsInvolved(h, ped)
        and not threatNear(h, ped, VSM.NPC.HOSTAGE_THREAT_RADIUS)
end

local function seen(ped)
    if not vsmResourceRunning("ai_land_traffic") then return false end
    local ok, res = pcall(function() return exports.ai_land_traffic:isElementSeenByPlayers(ped) end)
    return ok and res == true
end

local function tick()
    for ped, h in pairs(Hostage.list) do
        if not isElement(ped) then
            Hostage.list[ped] = nil
        elseif h.state == "released" then
            -- gone once nobody sees it and no player is close
            local x, y, z = getElementPosition(ped)
            local near = #getElementsWithinRange(x, y, z, VSM.NPC.HOSTAGE_GONE_DIST, "player") > 0
            if not near and not seen(ped) then
                Hostage.list[ped] = nil
                Npc.destroy(ped)
            end
        elseif isPedDead(ped) then
            Hostage.list[ped] = nil
            sys(h.scene, "v_scenemanager.hostage.dead")
            vsmLog("scene '%s' #%d: hostage %s died", h.scene.name, h.scene.id, tostring(h.entry.id))
        else
            local r = canRelease(h, ped)
            if getElementData(ped, "vsm.hostage.release") ~= r then setElementData(ped, "vsm.hostage.release", r, false) end
        end
    end
end

addEvent("onPoliceHostageAction")
addEventHandler("onPoliceHostageAction", root, function(action, officer)
    local ped = source
    local h = Hostage.list[ped]
    local A = ai()
    if not h or not A or not isElement(ped) or isPedDead(ped) then return end
    local scene = h.scene
    if action == "safe" and h.state == "held" then
        setState(ped, h, "safe")
        pcall(function() A:setAIPedBehaviour(ped, "hostage", { pose = "stand" }) end)
        sys(scene, "v_scenemanager.hostage.safe")
    elseif action == "ems" and (h.state == "held" or h.state == "safe") then
        setState(ped, h, "ems")
        pcall(function() A:setAIPedBehaviour(ped, "patient", {}) end)
        sys(scene, "v_scenemanager.hostage.ems")
    elseif action == "release" and canRelease(h, ped) then
        setState(ped, h, "released")
        setElementData(ped, "vsm.hostage.release", false, false)
        pcall(function()
            A:setAIPedProtected(ped, false)
            A:setAIPedKeep(ped, false)
            A:setAIPedGroup(ped, "civilian")
            A:setAIPedBehaviour(ped, "civilian", { task = "wander" })
        end)
        sys(scene, "v_scenemanager.hostage.released")
    else
        return
    end
    vsmLog("scene '%s' #%d: hostage %s -> %s (%s)", scene.name, scene.id, tostring(h.entry.id), action,
        isElement(officer) and getPlayerName(officer) or "?")
end)

addEventHandler("onElementDestroy", root, function()
    if Hostage.list[source] then Hostage.list[source] = nil end
end)

setTimer(function()
    local ok, err = pcall(tick)
    if not ok then vsmLog("hostage tick: %s", tostring(err)) end
end, 1000, 0)
