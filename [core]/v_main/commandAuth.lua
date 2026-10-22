if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
    local msg = L.msg("v_main.commandauth.access_denied_requires_admin_level_or", { cmd_name = tostring(cmdName), priv_admin_level = PRIV_ADMIN_LEVEL })

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
    if tag == "update" then reportLine("update", "status", msg) end
    outputServerLog(("[v_main:%s] %s"):format(tag, msg))
    if isElement(player) then
        outputConsole(("[%s] %s"):format(tag, msg), player)
    end
end

-- ---------------------------------------------------------------------------
-- Report of the last update check / update (v_admin Resources page):
--   UPDATE_REPORT[kind] = { at, by, lines = { { time, event, text } } }, kind = "check" | "update"
-- ---------------------------------------------------------------------------
UPDATE_REPORT = { check = false, update = false }

local REPORT_MAX = 400

function reportStart(kind, by)
    UPDATE_REPORT[kind] = { at = getRealTime().timestamp, by = tostring(by), lines = {} }
end

function reportLine(kind, event, text)
    local r = UPDATE_REPORT[kind]
    if not r or #r.lines >= REPORT_MAX then return end
    r.lines[#r.lines + 1] = { time = getRealTime().timestamp, event = event, text = text }
end
