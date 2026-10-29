-- Admin test module (MEDFX_TEST.ENABLED, admin_level check through v_mysql).
--   /medfx          menu (client/test.lua): visual preview, real medsys changes on yourself, animation peds
--   /medfx heal     heals you completely (also works while you are knocked out)
--   /medfx clear    removes your test peds

if not MEDFX_TEST.ENABLED then return end

addEvent("medfx:testAction", true)

local testPeds = {} -- admin -> { ped, ... } oldest first

local function say(player, text)
    outputChatBox("#ff5a5a[MEDFX] #ffffff" .. text, player, 255, 255, 255, true)
end

-- admin_level is read from the account store, not from (client-spoofable) element data
local function isAllowed(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return false end
    local mysql = getResourceFromName("v_mysql")
    if not mysql or getResourceState(mysql) ~= "running" then return false end
    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= MEDFX_TEST.MIN_ADMIN_LEVEL
end

local function removePeds(admin)
    local list = testPeds[admin]
    testPeds[admin] = nil
    local count = 0
    for _, ped in ipairs(list or {}) do
        if isElement(ped) then
            destroyElement(ped)
            count = count + 1
        end
    end
    return count
end

local function createTestPed(admin)
    local x, y, z = getElementPosition(admin)
    local _, _, rz = getElementRotation(admin)
    local a = math.rad(rz)
    local d = MEDFX_TEST.SPAWN_DISTANCE
    local skins = MEDFX_TEST.SKINS
    local ped = createPed(skins[math.random(#skins)], x - math.sin(a) * d, y + math.cos(a) * d, z, rz + 180)
    if not ped then return nil end
    setElementInterior(ped, getElementInterior(admin))
    setElementDimension(ped, getElementDimension(admin))

    local list = testPeds[admin] or {}
    testPeds[admin] = list
    list[#list + 1] = ped
    while #list > MEDFX_TEST.MAX_PEDS do
        local oldest = table.remove(list, 1)
        if isElement(oldest) then destroyElement(oldest) end
    end
    return ped
end

-- Real changes on the admin through medsys
local SELF = {
    dazed = function(p, ms) return ms:setMedicalState(p, "consciousness", "dazed"), "Dazed (medsys knockout time)" end,
    unconscious = function(p, ms)
        return ms:setMedicalState(p, "consciousness", "unconscious"),
            "Unconscious - /" .. MEDFX_TEST.COMMAND .. " heal wakes you up"
    end,
    pain = function(p, ms) return ms:setMedicalState(p, "pain", 85), "Pain 85 (fades)" end,
    bleed1 = function(p, ms) return ms:setMedicalState(p, "bleeding", 1), "Mild bleeding" end,
    bleed3 = function(p, ms) return ms:setMedicalState(p, "bleeding", 3), "Critical bleeding" end,
    spo2 = function(p, ms) return ms:setMedicalState(p, "spo2", 80), "SpO2 80% (recovers)" end,
    blood = function(p, ms) return ms:setMedicalState(p, "bloodVolume", 3300), "Blood volume 66%" end,
    legFracture = function(p, ms)
        local id = ms:applyInjury(p, "fracture", 2)
        if id then
            TestParts[p] = TestParts[p] or {}
            TestParts[p][id] = "left_leg"
            refreshPlayer(p)
        end
        return id, "Left leg fracture (no sprint / jump, limping)"
    end,
    armFracture = function(p, ms)
        local id = ms:applyInjury(p, "fracture", 2)
        if id then
            TestParts[p] = TestParts[p] or {}
            TestParts[p][id] = "right_arm"
            refreshPlayer(p)
        end
        return id, "Right arm fracture (no aiming)"
    end,
    heal = function(p, ms) return ms:healCompletely(p), "Healed completely" end,
}

-- Test peds for the forced animations. pose = a med_scenemanager-like pose played first,
-- the medical state follows after `delay` ms (shows the override).
local PEDS = {
    unconscious = { label = "Unconscious ped", set = { { "consciousness", "unconscious" } } },
    dazed = { label = "Dazed ped", set = { { "consciousness", "dazed" } } },
    arrest = { label = "Ped in clinical death", set = { { "consciousness", "clinical_death" } } },
    override = { label = "Standing scene pose -> unconscious after 3 s", pose = { "GANGS", "leanIDLE", true },
        delay = 3000, set = { { "consciousness", "unconscious" } } },
    keep = { label = "Lying scene pose -> unconscious (pose kept)", pose = { "CRACK", "crckdeth2", false },
        delay = 3000, set = { { "consciousness", "unconscious" } } },
    wake = { label = "Unconscious ped, wakes up after 8 s", set = { { "consciousness", "unconscious" } },
        later = { 8000, "consciousness", "stable" } },
}
local PED_ORDER = { "unconscious", "dazed", "arrest", "override", "keep", "wake" }

local function spawnPed(admin, id)
    local def = PEDS[id]
    local ms = medsys()
    if not def or not ms then return false end
    local ped = createTestPed(admin)
    if not ped then
        say(admin, "Could not create the ped here.")
        return true
    end
    setTimer(function()
        if not isElement(ped) then return end
        if def.pose then
            setPedAnimation(ped, def.pose[1], def.pose[2], -1, def.pose[3], false, false, true)
        end
        setTimer(function()
            if not isElement(ped) then return end
            ms:applyInjury(ped, "fracture", 1) -- keeps it a patient
            for _, entry in ipairs(def.set) do ms:setMedicalState(ped, entry[1], entry[2]) end
            if def.later then
                setTimer(function()
                    if isElement(ped) then ms:setMedicalState(ped, def.later[2], def.later[3]) end
                end, def.later[1], 1)
            end
        end, def.delay or 50, 1)
    end, 150, 1)
    say(admin, ("Spawned: #ffd24a%s"):format(def.label))
    return true
end

local function selfAction(admin, id)
    local action = SELF[id]
    local ms = medsys()
    if not action then return false end
    if not ms then
        say(admin, "medsys is not running.")
        return true
    end
    local ok, label = action(admin, ms)
    say(admin, ok and ("Applied: #ffd24a%s"):format(label) or "medsys refused it (are you dead?).")
    return true
end

addCommandHandler(MEDFX_TEST.COMMAND, function(player, _, arg)
    if not isAllowed(player) then return end
    if not arg then
        local peds = {}
        for i, id in ipairs(PED_ORDER) do peds[i] = { id = id, label = PEDS[id].label } end
        triggerClientEvent(player, "medfx:testMenu", resourceRoot, peds)
    elseif arg == "clear" then
        say(player, ("Removed %d test ped(s)."):format(removePeds(player)))
    elseif not selfAction(player, arg) and not spawnPed(player, arg) then
        say(player, ("Usage: /%s [heal|clear|dazed|unconscious|pain|bleed1|bleed3|spo2|blood|legFracture|armFracture]")
            :format(MEDFX_TEST.COMMAND))
    end
end)

-- value from the menu: { self = id } | { ped = id } | { clear = true }
addEventHandler("medfx:testAction", resourceRoot, function(value)
    local admin = client
    if not isAllowed(admin) or type(value) ~= "table" then return end
    if value.self then
        selfAction(admin, value.self)
    elseif value.ped then
        spawnPed(admin, value.ped)
    elseif value.clear then
        say(admin, ("Removed %d test ped(s)."):format(removePeds(admin)))
    end
end)

addEventHandler("onPlayerQuit", root, function()
    removePeds(source)
end)
