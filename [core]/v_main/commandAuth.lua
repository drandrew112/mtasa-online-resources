--[[
    commandAuth.lua
    ---------------------------------------------------------------------------
    Shared access gate for v_main's privileged console commands:
        /restartallresource   (restartAllResources.lua)
        /updateresources      (updateResources.lua)

    Allowed for:
      - the server console
      - an in-game player who is logged in AND has admin_level >= 5 (Dev+)

    admin_level is read from the authoritative store (v_mysql), the same way
    v_admin's getAdminLevel does it - not from (client-spoofable) element data.
]]

PRIV_ADMIN_LEVEL = 5

--- True when `player` may run a privileged v_main command.
--- addCommandHandler passes a falsy `player` when the command comes from the
--- server console.
function canRunAdminCommand(player)
    if not player or not isElement(player) then return true end
    if getElementType(player) ~= "player" then return true end

    if getElementData(player, "isLogged") ~= true then return false end

    local level = tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= PRIV_ADMIN_LEVEL
end

--- Uniform "no permission" reply + false (so callers can `return denyAdminCommand(...)`).
function denyAdminCommand(player, cmdName)
    local msg = ("Access denied - '%s' requires admin level %d or the server console.")
        :format(tostring(cmdName), PRIV_ADMIN_LEVEL)

    if isElement(player) then
        outputConsole(msg, player)
    else
        outputServerLog("[v_main] " .. msg)
    end
    return false
end

--- Feedback line that reaches the caller whether it is the console or a player
--- (chat is disabled mod-wide, so players get it in their F8 console).
function commandFeedback(player, tag, msg)
    outputServerLog(("[v_main:%s] %s"):format(tag, msg))
    if isElement(player) then
        outputConsole(("[%s] %s"):format(tag, msg), player)
    end
end
