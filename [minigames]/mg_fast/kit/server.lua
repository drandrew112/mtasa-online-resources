-- Hospital minigame kit, server side: sessions, the synced animation next to the patient, the
-- sanity check of the client result and the finish event (MGDEF.serverEvent, source = player):
--   success, percent, reason, sessionId, details
--   reason: "completed" | "expired" | "cancelled" | "died" | "quit" | "timeout" | "invalid"
--
-- IDENTICAL COPY in mg_suture (master), mg_irrigation, mg_cast, mg_reduction, mg_blooddraw, mg_fast,
-- mg_chestdrain and mg_ecg. Change it in mg_suture/kit/ and copy it to the others (README.md).

MGS = {}

local ANIM_KNEEL = { "BOMBER", "BOM_Plant_Loop" }
local ANIM_STAND = { "INT_SHOP", "shop_loop" }
local COUNTDOWN, RESULT_TIME = 3, 2.2

addEvent(MGDEF.serverEvent, false)
addEvent(MGDEF.res .. ":onResult", true)
addEvent(MGDEF.res .. ":ready", true)

local sessions = {} -- [player] = { id, options, ped, animated, startTick, timer }
local lastId = 0

-- only the keys MGDEF.details lists, with their type; strings are cut to 32 characters
local function sanitize(details)
    local out = {}
    if type(details) ~= "table" then return out end
    for key, kind in pairs(MGDEF.details or {}) do
        local v = details[key]
        if kind == "number" and tonumber(v) then out[key] = tonumber(v)
        elseif kind == "boolean" and type(v) == "boolean" then out[key] = v
        elseif kind == "string" and type(v) == "string" then out[key] = v:sub(1, 32)
        elseif kind == "table" and type(v) == "table" then
            local t = {}
            for k, x in pairs(v) do
                if type(k) == "string" and #k <= 16 and (type(x) == "string" or type(x) == "number" or type(x) == "boolean") then
                    t[k] = type(x) == "string" and x:sub(1, 16) or x
                end
            end
            out[key] = t
        end
    end
    return out
end

local function finishSession(player, reason, percent, details)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    if isTimer(s.timer) then killTimer(s.timer) end
    percent = math.max(0, math.min(100, math.floor(tonumber(percent) or 0)))
    details = sanitize(details)
    local success = reason == "completed" and MGDEF.pass(percent, details, s.options) or false
    if isElement(player) then
        if s.animated then setPedAnimation(player) end
        triggerEvent(MGDEF.serverEvent, player, success, percent, reason, s.id, details)
    end
end

-- -> session id, or false (invalid player / ped, or already playing)
function MGS.start(player, ped, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if ped ~= nil then
        if not isElement(ped) or ped == player then return false end
        local t = getElementType(ped)
        if t ~= "ped" and t ~= "player" then return false end
    end
    options = MGDEF.normalize(options)
    if ped and isPedInVehicle(player) then removePedFromVehicle(player) end
    lastId = lastId + 1
    local s = { id = lastId, options = options, ped = ped, startTick = getTickCount() }
    s.timer = setTimer(finishSession, (COUNTDOWN + options.time + RESULT_TIME + 15) * 1000, 1, player, "timeout")
    sessions[player] = s
    triggerClientEvent(player, MGDEF.res .. ":start", resourceRoot, s.id, options, ped)
    return s.id
end

function MGS.stop(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, MGDEF.res .. ":stop", resourceRoot)
    finishSession(player, "cancelled")
    return true
end

function MGS.active(player) return sessions[player] ~= nil end

-- the client stands / kneels next to the patient: the synced animation
addEventHandler(MGDEF.res .. ":ready", resourceRoot, function(sessionId, stand)
    local player = client
    local s = sessions[player]
    if not s or s.id ~= sessionId or not s.ped or s.animated then return end
    s.animated = true
    local anim = stand == true and ANIM_STAND or ANIM_KNEEL
    setPedAnimation(player, anim[1], anim[2], -1, true, false, false, false)
end)

addEventHandler(MGDEF.res .. ":onResult", resourceRoot, function(sessionId, percent, details, reason)
    local player = client
    local s = sessions[player]
    if not s or s.id ~= sessionId then return end
    percent = tonumber(percent)
    local elapsed = (getTickCount() - s.startTick) / 1000
    if (reason ~= "completed" and reason ~= "expired") or not percent or percent < 0 or percent > 100
        or elapsed < COUNTDOWN + MGDEF.minDuration(s.options) then
        outputDebugString(("%s: rejected result from %s (reason=%s, percent=%s, %.1fs)")
            :format(MGDEF.res, getPlayerName(player), tostring(reason), tostring(percent), elapsed), 2)
        return finishSession(player, "invalid")
    end
    finishSession(player, reason, percent, details)
end)

addEventHandler("onPlayerWasted", root, function()
    if not sessions[source] then return end
    triggerClientEvent(source, MGDEF.res .. ":stop", resourceRoot)
    finishSession(source, "died")
end)

addEventHandler("onPlayerQuit", root, function() finishSession(source, "quit") end)

-- /<testCommand> [0]: a lying test ped in front of the player (0 = without a ped)
if MGDEF.testCommand then
    local testPeds = {}
    addCommandHandler(MGDEF.testCommand, function(player, _, withPed)
        local ped
        if withPed ~= "0" then
            local x, y, z = getElementPosition(player)
            local _, _, rz = getElementRotation(player)
            local a = math.rad(rz)
            ped = createPed(math.random(7, 30), x - math.sin(a) * 2, y + math.cos(a) * 2, z, rz + 90)
            setElementInterior(ped, getElementInterior(player))
            setElementDimension(ped, getElementDimension(player))
            setTimer(function() if isElement(ped) then setPedAnimation(ped, "PED", "KO_shot_front", -1, false, false, false, true) end end, 100, 1)
        end
        if MGS.start(player, ped) then testPeds[player] = ped elseif ped then destroyElement(ped) end
    end)
    addEventHandler(MGDEF.serverEvent, root, function(success, percent, reason)
        outputDebugString(("[%s] %s: %s %d%% (%s)"):format(MGDEF.res, getPlayerName(source), success and "SUCCESS" or "FAILED", percent, reason))
        local ped = testPeds[source]
        testPeds[source] = nil
        if isElement(ped) then setTimer(destroyElement, 3000, 1, ped) end
    end)
end
