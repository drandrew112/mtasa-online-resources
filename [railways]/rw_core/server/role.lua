-- Railway role ("vasutas jog"), the same model as the medsys medic role. The server table is
-- the authority; the element data copy (RW.DATA_ROLE) only tells clients, and client-side
-- changes to it are reverted. Not persisted: work_traindriver / admins hand it out.

local Railway = {}

addEvent("onPlayerRailwayChange") -- source: player, arg: enabled

-- Is the role checked at all (fixed while the resource runs, query it once)
function isRailwayRoleRequired()
    return RW.REQUIRE_RAILWAY_ROLE == true
end

-- Does the player hold the role (the bare flag)
function isPlayerRailway(player)
    return Railway[player] == true
end

-- May the player assemble trains / throw switches: always when the role is not required
function hasRailwayAccess(player)
    return not RW.REQUIRE_RAILWAY_ROLE or Railway[player] == true
end

local function syncData(player)
    if Railway[player] then setElementData(player, RW.DATA_ROLE, true)
    else removeElementData(player, RW.DATA_ROLE) end
end

function setPlayerRailway(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    enabled = enabled and true or false
    if (Railway[player] == true) == enabled then return true end
    Railway[player] = enabled or nil
    syncData(player)
    triggerEvent("onPlayerRailwayChange", player, enabled)
    return true
end

function getRailwayPlayers()
    local list = {}
    for p in pairs(Railway) do list[#list + 1] = p end
    return list
end

addEventHandler("onElementDataChange", root, function(key)
    if key == RW.DATA_ROLE and client then syncData(source) end
end)

addEventHandler("onPlayerQuit", root, function() Railway[source] = nil end)

-- admin level through v_mysql (like med_erm), element data as a fallback
function getAdminLevel(player)
    local res = getResourceFromName("v_mysql")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

function isRailwayAdmin(player)
    return getAdminLevel(player) >= RW.ADMIN_LEVEL
end

-- /rwrole [player] [on|off]  (admins) - no player = yourself, no state = toggle
addCommandHandler("rwrole", function(player, _, name, state)
    if not isRailwayAdmin(player) then
        outputChatBox("[" .. RW.COMPANY_SHORT .. "] Nincs jogod ehhez.", player, 255, 80, 80)
        return
    end
    local target = player
    if name and name ~= "" then
        target = getPlayerFromName(name)
        if not target then
            local q = name:lower()
            for _, p in ipairs(getElementsByType("player")) do
                if getPlayerName(p):gsub("#%x%x%x%x%x%x", ""):lower():find(q, 1, true) then target = p break end
            end
        end
    end
    if not target then
        outputChatBox("[" .. RW.COMPANY_SHORT .. "] Nincs ilyen játékos.", player, 255, 80, 80)
        return
    end
    local enable
    if state == "on" then enable = true elseif state == "off" then enable = false
    else enable = not isPlayerRailway(target) end
    setPlayerRailway(target, enable)
    local who = getPlayerName(target):gsub("#%x%x%x%x%x%x", "")
    outputChatBox(("[%s] Vasutas jog %s: %s"):format(RW.COMPANY_SHORT, enable and "megadva" or "elvéve", who), player, 120, 200, 255)
    if target ~= player then
        outputChatBox(("[%s] Vasutas jogod %s."):format(RW.COMPANY_SHORT, enable and "lett" or "megszűnt"), target, 120, 200, 255)
    end
end)
