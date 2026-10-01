-- Test module: spawns injured peds in front of an admin (MEDIC_TEST.ENABLED, admin_level check).
--   /medtest              opens the menu (client/test.lua)
--   /medtest <scenario>   spawns a scenario directly (/medtest list for the ids)
--   /medtest clear        removes your test peds

if not MEDIC_TEST.ENABLED then return end

addEvent("medic:testSpawn", true)
addEvent("medic:testClear", true)

local testPeds = {} -- [admin] = { ped, ped, ... } oldest first

local scenarioById = {}
for _, scenario in ipairs(MEDIC_TEST.SCENARIOS) do
    scenarioById[scenario.id] = scenario
end

local function say(player, text)
    outputChatBox("#ff5a5a[MEDTEST] #ffffff" .. text, player, 255, 255, 255, true)
end

-- admin_level is read from the account store, not from (client-spoofable) element data
local function isAllowed(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return false end
    local mysql = getResourceFromName("v_mysql")
    if not mysql or getResourceState(mysql) ~= "running" then return false end
    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= MEDIC_TEST.MIN_ADMIN_LEVEL
end

local function removePeds(admin)
    local list = testPeds[admin]
    testPeds[admin] = nil
    if not list then return 0 end
    local count = 0
    for _, ped in ipairs(list) do
        if isElement(ped) then
            destroyElement(ped)
            count = count + 1
        end
    end
    return count
end

-- Ped in front of the admin, facing them
local function createTestPed(admin)
    local x, y, z = getElementPosition(admin)
    local _, _, rz = getElementRotation(admin)
    local a = math.rad(rz)
    local d = MEDIC_TEST.SPAWN_DISTANCE
    local skins = MEDIC_TEST.SKINS
    local ped = createPed(skins[math.random(#skins)], x - math.sin(a) * d, y + math.cos(a) * d, z, rz + 180)
    if not ped then return nil end
    setElementInterior(ped, getElementInterior(admin))
    setElementDimension(ped, getElementDimension(admin))

    local list = testPeds[admin] or {}
    testPeds[admin] = list
    list[#list + 1] = ped
    while #list > MEDIC_TEST.MAX_PEDS do
        local oldest = table.remove(list, 1)
        if isElement(oldest) then destroyElement(oldest) end
    end
    return ped
end

-- injuries = { { type, severity } }, set = { { key, value } }
local function spawnPatient(admin, injuries, set, label)
    local ped = createTestPed(admin)
    if not ped then
        say(admin, "Could not create the ped here.")
        return
    end
    -- give the ped a moment to exist on the clients, so the animations sync
    setTimer(function()
        if not isElement(ped) then return end
        for _, injury in ipairs(injuries) do
            applyInjury(ped, injury[1], injury[2])
        end
        for _, entry in ipairs(set or {}) do
            setMedicalState(ped, entry[1], entry[2])
        end
    end, 150, 1)
    say(admin, ("Spawned: #ffd24a%s"):format(label))
end

local function spawnScenario(admin, id)
    local scenario = scenarioById[id]
    if not scenario then return false end
    spawnPatient(admin, scenario.injuries, scenario.set, scenario.label)
    return true
end

local function spawnInjury(admin, injuryType, severity)
    local def = MEDIC_INJURIES[injuryType]
    severity = medicNormalizeSeverity(severity)
    if not def or not severity then return false end
    spawnPatient(admin, { { injuryType, severity } }, nil, ("%s (%s)"):format(def.label, MEDIC_SEVERITY[severity]))
    return true
end

addCommandHandler(MEDIC_TEST.COMMAND, function(player, _, arg, severity)
    if not isAllowed(player) then return end

    if not arg then
        triggerClientEvent(player, "medic:testMenu", resourceRoot)
    elseif arg == "clear" then
        say(player, ("Removed %d test ped(s)."):format(removePeds(player)))
    elseif arg == "list" then
        local ids = {}
        for _, scenario in ipairs(MEDIC_TEST.SCENARIOS) do ids[#ids + 1] = scenario.id end
        say(player, "Scenarios: #ffd24a" .. table.concat(ids, ", "))
        say(player, "Single injury: /" .. MEDIC_TEST.COMMAND .. " <gunshot|fracture|burn|suffocation> <1-3>")
    elseif not spawnScenario(player, arg) and not spawnInjury(player, arg, severity) then
        say(player, ("Unknown scenario / injury. Use /%s list"):format(MEDIC_TEST.COMMAND))
    end
end)

-- value from the menu: { scenario = id } or { injury = type, severity = n }
addEventHandler("medic:testSpawn", resourceRoot, function(value)
    local admin = client
    if not isAllowed(admin) or type(value) ~= "table" then return end
    if value.scenario then
        spawnScenario(admin, value.scenario)
    elseif value.injury then
        spawnInjury(admin, value.injury, value.severity)
    end
end)

addEventHandler("medic:testClear", resourceRoot, function()
    local admin = client
    if not isAllowed(admin) then return end
    say(admin, ("Removed %d test ped(s)."):format(removePeds(admin)))
end)

addEventHandler("onPlayerQuit", root, function()
    removePeds(source)
end)
