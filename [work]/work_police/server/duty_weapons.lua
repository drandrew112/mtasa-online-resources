-- duty_weapons module: the service weapons of an officer. On duty start the player gets POLICE_WORK.DUTY_WEAPONS
-- (stun gun 23 + Desert Eagle 24) as LENT weapons of wp_manager (lendPlayerWeapon): they are not the player's
-- own, never saved with the account, and an own weapon of the same id is parked meanwhile. Duty end (any reason)
-- takes them back (returnLentWeapons); wp_manager also takes them back by itself when work_police stops.

local W = POLICE_WORK

local function wm()
    local res = getResourceFromName("wp_manager")
    return res and getResourceState(res) == "running" and exports.wp_manager or nil
end

local function give(player)
    local m = wm()
    if not m or not isElement(player) then return end
    for _, w in ipairs(W.DUTY_WEAPONS) do m:lendPlayerWeapon(player, w.id, w.ammo, false) end
end

local function takeBack(player)
    local m = wm()
    if m and isElement(player) then m:returnLentWeapons(player) end
end

PoliceWorkModules.register("duty_weapons", {
    onDutyStart = function(player) give(player) end,
    onDutyEnd   = function(player) takeBack(player) end,
})

local function onDutyPlayers()
    local res = getResourceFromName("work_core")
    if not res or getResourceState(res) ~= "running" then return {} end
    return exports.work_core:getWorkPlayers(W.WORK_ID) or {}
end

-- officers already on duty when work_police (re)starts, or when wp_manager starts after it
local function giveMissing()
    local m = wm()
    if not m then return end
    for _, player in ipairs(onDutyPlayers()) do
        for _, w in ipairs(W.DUTY_WEAPONS) do
            if not m:isPlayerWeaponLent(player, w.id) then m:lendPlayerWeapon(player, w.id, w.ammo, false) end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, giveMissing)
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "wp_manager" then setTimer(giveMissing, 500, 1) end
end)
