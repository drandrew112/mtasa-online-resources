-- police_system / modules/rights/server/rights.lua
-- The police right: element data pol.right on the player, subscribe sync (only the player itself gets it). The
-- server is the truth (Rights.has). work_police gives it at duty start and takes it at duty end; after a
-- police_system restart work_police gives it back (onPoliceSystemStart). With REQUIRE_POLICE_RIGHT = false
-- (testing) everybody has it, like bt_core's REQUIRE_RIGHT.
-- Without the right nothing police related shows (no MDC, keys, plates) and no warning either.

local R = POL.module("rights", {})
local KEY = POLICE.RIGHT_KEY

function R.has(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if not POLICE.REQUIRE_POLICE_RIGHT then return true end
    return getElementData(player, KEY) == true
end

local function apply(player, on)
    if on then
        setElementData(player, KEY, true, "subscribe")
        addElementDataSubscriber(player, KEY, player)
    else
        removeElementData(player, KEY)
    end
end

function R.set(player, on)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if not on and not POLICE.REQUIRE_POLICE_RIGHT then return true end   -- test mode: everybody keeps it
    local had = getElementData(player, KEY) == true
    apply(player, on and true or false)
    if had ~= (on and true or false) then POL.emit("rights.changed", player, on and true or false) end
    return true
end

function R.start()
    if POLICE.REQUIRE_POLICE_RIGHT then return end
    for _, p in ipairs(getElementsByType("player")) do apply(p, true) end
end

addEventHandler("onPlayerJoin", root, function()
    if not POLICE.REQUIRE_POLICE_RIGHT then apply(source, true) end
end)

-- exports
function hasPoliceRight(player) return R.has(player) end
function setPoliceRight(player, on) return R.set(player, on) end
