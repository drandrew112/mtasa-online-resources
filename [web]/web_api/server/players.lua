-- web_api :: server/players.lua
-- Player state for external software (voice client, overlays, tools).
-- HTTP (http="true", POST /web_api/call/<fn>, body = JSON array); token = v_accounts webLogin:
--   playerState(token)  -> own state (see below) | { ok = false, error }
--   playerOnline(name)  -> { ok, online, displayName } of any account (public: no position / work)
-- Server export: getPlayerState(playerOrAccount) -> the same table (no token, for other resources).
--
-- State: { ok, account, online, displayName, name, work = { id, onDuty, name } | false,
--          position = { x, y, z }, rotation = { x, y, z }, interior, dimension, zone, city,
--          health, armor, money, wanted, ping,
--          vehicle = { model, name, seat, driver, plate, speed (km/h), health, rotation, engine, sirens } | false }

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function round(n, d)
    local m = 10 ^ (d or 2)
    return math.floor((tonumber(n) or 0) * m + 0.5) / m
end

local function stripColors(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""))
end

local flood = {}   -- [address] = { windowStart, count }
local function flooded()
    local key, t = type(hostname) == "string" and hostname or "web", getTickCount()
    local f = flood[key]
    if not f or t - f[1] > 10000 then
        flood[key] = { t, 1 }
        return false
    end
    f[2] = f[2] + 1
    return f[2] > 60
end

local function workOf(player)
    if not running("work_core") then return false end
    local id = exports.work_core:getPlayerWork(player)
    if not id then return false end
    local w = exports.work_core:getWork(id)
    return {
        id = id,
        onDuty = exports.work_core:isPlayerOnDuty(player, id) and true or false,
        name = type(w) == "table" and type(w.name) == "string" and stripColors(w.name) or id,
    }
end

local function vehicleOf(player)
    local veh = getPedOccupiedVehicle(player)
    if not veh then return false end
    local vx, vy, vz = getElementVelocity(veh)
    local rx, ry, rz = getElementRotation(veh)
    local name = getVehicleName(veh)
    if running("veh_manager") then
        local ok, n = pcall(function() return exports.veh_manager:getModelName(getElementModel(veh)) end)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    return {
        model = getElementModel(veh),
        name = name,
        seat = getPedOccupiedVehicleSeat(player),
        driver = getVehicleController(veh) == player,
        plate = getVehiclePlateText(veh),
        speed = round(math.sqrt(vx * vx + vy * vy + vz * vz) * 180, 1),
        health = round(getElementHealth(veh), 0),
        rotation = { x = round(rx), y = round(ry), z = round(rz) },
        engine = getVehicleEngineState(veh),
        sirens = getVehicleSirensOn(veh),
    }
end

-- playerOrAccount: player element or account name
function getPlayerState(playerOrAccount)
    local player = playerOrAccount
    local account
    if not isElement(player) then
        account = tostring(playerOrAccount or "")
        player = running("v_accounts") and exports.v_accounts:playerOnAccount(account) or nil
    end
    if not isElement(player) then return { ok = true, account = account, online = false } end
    if running("v_accounts") then account = exports.v_accounts:getName(player) or account end

    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)
    return {
        ok = true,
        account = account or false,
        online = true,
        displayName = stripColors(getElementData(player, "displayName") or getPlayerName(player)),
        name = stripColors(getPlayerName(player)),
        work = workOf(player),
        position = { x = round(x), y = round(y), z = round(z) },
        rotation = { x = round(rx), y = round(ry), z = round(rz) },
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
        zone = getZoneName(x, y, z),
        city = getZoneName(x, y, z, true),
        health = round(getElementHealth(player), 0),
        armor = round(getPedArmor(player), 0),
        money = getPlayerMoney(player),
        wanted = getPlayerWantedLevel(player),
        ping = getPlayerPing(player),
        vehicle = vehicleOf(player),
    }
end

function playerState(token)
    if flooded() then return { ok = false, error = "flood" } end
    if not running("v_accounts") then return { ok = false, error = "accounts_offline" } end
    local account = type(token) == "string" and exports.v_accounts:getWebSession(token)
    if not account then return { ok = false, error = "unauthorized" } end
    return getPlayerState(account)
end

function playerOnline(name)
    if flooded() then return { ok = false, error = "flood" } end
    if type(name) ~= "string" or name == "" or #name > 64 then return { ok = false, error = "bad_name" } end
    if not running("v_accounts") then return { ok = false, error = "accounts_offline" } end
    local player = exports.v_accounts:playerOnAccount(name)
    if not isElement(player) then return { ok = true, online = false } end
    return { ok = true, online = true, displayName = stripColors(getElementData(player, "displayName") or getPlayerName(player)) }
end

setTimer(function()
    local t = getTickCount()
    for k, f in pairs(flood) do if t - f[1] > 60000 then flood[k] = nil end end
end, 60000, 0)
