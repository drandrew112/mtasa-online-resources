-- ATC rights ("légiforgalmi irányító jogok"): tower, approach and radar are separate. The server
-- table is the authority; the element data copy (AVI.DATA_RIGHTS) only tells clients, and
-- client-side changes to it are reverted. Not persisted: work_atc / admins hand them out.
-- Everybody starts with AVI.DEFAULT_RIGHTS (tower).

local RIGHTS = {}                    -- [player] = { TWR = true, ... } (only players with changes)

addEvent("onPlayerATCChange") -- source: player, args: right, enabled

local function validRight(right)
    for _, r in ipairs(AVI.RIGHTS) do
        if r == right then return true end
    end
    return false
end

local function current(player)
    return RIGHTS[player] or AVI.DEFAULT_RIGHTS
end

local function copy(t)
    local out = {}
    for _, r in ipairs(AVI.RIGHTS) do out[r] = t[r] == true end
    return out
end

local function syncData(player)
    if isElement(player) then setElementData(player, AVI.DATA_RIGHTS, copy(current(player))) end
end

-- hasATCRight(player, "TWR" | "APP" | "RADAR")
function hasATCRight(player, right)
    return current(player)[right] == true
end

-- may the player staff a position of this type (TWR / APP / CTR)
function canStaffPosition(player, posType)
    local right = AVI.POSITION_RIGHT[posType]
    return right ~= nil and hasATCRight(player, right)
end

-- any right at all: may open the controller software
function hasATCAccess(player)
    for _, r in ipairs(AVI.RIGHTS) do
        if current(player)[r] then return true end
    end
    return false
end

function getPlayerATCRights(player)
    return copy(current(player))
end

function setPlayerATCRight(player, right, enabled)
    if not isElement(player) or getElementType(player) ~= "player" or not validRight(right) then return false end
    enabled = enabled and true or false
    if hasATCRight(player, right) == enabled then return true end
    RIGHTS[player] = copy(current(player))
    RIGHTS[player][right] = enabled
    syncData(player)
    triggerEvent("onPlayerATCChange", player, right, enabled)
    return true
end

-- setPlayerATCRights(player, { TWR = true, APP = true }) | setPlayerATCRights(player, false) = defaults
function setPlayerATCRights(player, rights)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local old = copy(current(player))
    if type(rights) == "table" then
        RIGHTS[player] = copy(rights)
    else
        RIGHTS[player] = nil
    end
    syncData(player)
    local new = current(player)
    for _, r in ipairs(AVI.RIGHTS) do
        if (new[r] == true) ~= old[r] then triggerEvent("onPlayerATCChange", player, r, new[r] == true) end
    end
    return true
end

addEventHandler("onElementDataChange", root, function(key)
    if key == AVI.DATA_RIGHTS and client then syncData(source) end
end)

addEventHandler("onPlayerJoin", root, function() syncData(source) end)
addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do syncData(p) end
end)
addEventHandler("onPlayerQuit", root, function() RIGHTS[source] = nil end)

-- /atcright [player] <twr|app|radar|all|reset> [on|off]  (admins) - no player = yourself, no state = toggle
addCommandHandler("atcright", function(player, _, a, b, c)
    if not isAviationAdmin(player) then
        aviNotify(player, "You are not allowed to do this.")
        return
    end
    -- the player name is optional: the first argument that is not a keyword
    local keywords = { twr = true, app = true, radar = true, all = true, reset = true }
    local target, right, state = player, a, b
    if a and not keywords[a:lower()] then
        target = findPlayer(a)
        if not target then
            aviNotify(player, "No such player.")
            return
        end
        right, state = b, c
    end
    right = right and right:lower()
    if not right or not keywords[right] then
        aviNotify(player, "Usage: /atcright [player] <twr|app|radar|all|reset> [on|off]")
        return
    end
    local who = getPlayerName(target):gsub("#%x%x%x%x%x%x", "")
    if right == "reset" then
        setPlayerATCRights(target, false)
        aviNotify(player, "ATC rights reset: " .. who)
    else
        local list = right == "all" and AVI.RIGHTS or { right:upper() }
        local enable
        if state == "on" then enable = true elseif state == "off" then enable = false
        else enable = not hasATCRight(target, list[1]) end
        for _, r in ipairs(list) do setPlayerATCRight(target, r, enable) end
        aviNotify(player, ("ATC right %s %s: %s"):format(right:upper(), enable and "given" or "removed", who))
    end
    if target ~= player then aviNotify(target, "Your ATC rights were changed.") end
end)
