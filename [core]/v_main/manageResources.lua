if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    manageResources.lua
    ---------------------------------------------------------------------------
    Per-resource control from in-game or the server console:

        /startresource   <name>   (alias: /startres)
        /stopresource    <name>   (alias: /stopres)
        /restartresource <name>   (alias: /restartres)

    Companion to restartAllResources.lua (/restartallresource). Same access
    rule: the server console, or a logged-in player with admin_level >= 5
    (see commandAuth.lua) - user ACL groups are no longer used.

    These live in v_main, not v_admin, because v_main is the resource that
    holds the ACL rights for startResource / stopResource / restartResource
    (it is the only script resource in <group name="Admin"> in acl.xml).
]]

-- Resources that must never be stopped / restarted from here: taking any of
-- them down would break the auth check itself or the admin tooling this
-- command depends on. A full, ordered reload is /restartallresource.
local PROTECT = {
    [getResourceName(resource)] = true,   -- ourselves (v_main)
    ["v_mysql"]    = true,                -- shared DB layer - backs the level check
    ["v_accounts"] = true,                -- login / account system
    ["v_admin"]    = true,                -- in-game admin commands
}

--- Human-readable "who ran this" string for the log line.
local function actor(player)
    if not isElement(player) then return "console" end
    return ("%s (#%s)"):format(getPlayerName(player), tostring(getElementData(player, "ID")))
end

--- Resolve a resource-name argument; prints the error and returns nil on failure.
local function resolveResource(player, name)
    if not name or name == "" then
        commandFeedback(player, "res", L.msg("v_main.manageresources.usage_command_resource_name"))
        return nil
    end
    local res = getResourceFromName(name)
    if not res then
        commandFeedback(player, "res", L.msg("v_main.manageresources.no_such_resource", { name = name }))
        return nil
    end
    return res
end

local function cmdStart(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if getResourceState(res) == "running" then
        return commandFeedback(player, "res", L.msg("v_main.manageresources.is_already_running", { name = name }))
    end
    if startResource(res) then
        commandFeedback(player, "res", L.msg("v_main.manageresources.started_by", { name = name, player = actor(player) }))
    else
        commandFeedback(player, "res", L.msg("v_main.manageresources.could_not_start_check_its_meta", { name = name }))
    end
end

local function cmdStop(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if PROTECT[getResourceName(res)] then
        return commandFeedback(player, "res", L.msg("v_main.manageresources.is_protected_it_cannot_be_stopped", { name = name }))
    end
    if getResourceState(res) ~= "running" then
        return commandFeedback(player, "res", L.msg("v_main.manageresources.is_not_running", { name = name }))
    end
    if stopResource(res) then
        commandFeedback(player, "res", L.msg("v_main.manageresources.stop_requested_for_by", { name = name, player = actor(player) }))
    else
        commandFeedback(player, "res", L.msg("v_main.manageresources.could_not_stop", { name = name }))
    end
end

local function cmdRestart(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if PROTECT[getResourceName(res)] then
        return commandFeedback(player, "res", L.msg("v_main.manageresources.is_protected_use_restartallresource_instead", { name = name }))
    end
    if getResourceState(res) ~= "running" then
        return commandFeedback(player, "res", L.msg("v_main.manageresources.is_not_running_use_startres", { name = name }))
    end
    if restartResource(res) then
        commandFeedback(player, "res", L.msg("v_main.manageresources.restarting_by", { name = name, player = actor(player) }))
    else
        commandFeedback(player, "res", L.msg("v_main.manageresources.could_not_restart", { name = name }))
    end
end

addCommandHandler("startresource",   cmdStart,   false, false)
addCommandHandler("startres",        cmdStart,   false, false)
addCommandHandler("stopresource",    cmdStop,    false, false)
addCommandHandler("stopres",         cmdStop,    false, false)
addCommandHandler("restartresource", cmdRestart, false, false)
addCommandHandler("restartres",      cmdRestart, false, false)
