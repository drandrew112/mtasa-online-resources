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
        commandFeedback(player, "res", "Usage: <command> <resource name>")
        return nil
    end
    local res = getResourceFromName(name)
    if not res then
        commandFeedback(player, "res", ("No such resource: '%s'."):format(name))
        return nil
    end
    return res
end

local function cmdStart(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if getResourceState(res) == "running" then
        return commandFeedback(player, "res", ("'%s' is already running."):format(name))
    end
    if startResource(res) then
        commandFeedback(player, "res", ("Started '%s' (by %s)."):format(name, actor(player)))
    else
        commandFeedback(player, "res", ("Could not start '%s' - check its meta.xml / dependencies."):format(name))
    end
end

local function cmdStop(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if PROTECT[getResourceName(res)] then
        return commandFeedback(player, "res", ("'%s' is protected - it cannot be stopped from here."):format(name))
    end
    if getResourceState(res) ~= "running" then
        return commandFeedback(player, "res", ("'%s' is not running."):format(name))
    end
    if stopResource(res) then
        commandFeedback(player, "res", ("Stop requested for '%s' (by %s)."):format(name, actor(player)))
    else
        commandFeedback(player, "res", ("Could not stop '%s'."):format(name))
    end
end

local function cmdRestart(player, cmd, name)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    local res = resolveResource(player, name)
    if not res then return end

    if PROTECT[getResourceName(res)] then
        return commandFeedback(player, "res", ("'%s' is protected - use /restartallresource instead."):format(name))
    end
    if getResourceState(res) ~= "running" then
        return commandFeedback(player, "res", ("'%s' is not running - use /startres."):format(name))
    end
    if restartResource(res) then
        commandFeedback(player, "res", ("Restarting '%s' (by %s)."):format(name, actor(player)))
    else
        commandFeedback(player, "res", ("Could not restart '%s'."):format(name))
    end
end

addCommandHandler("startresource",   cmdStart,   false, false)
addCommandHandler("startres",        cmdStart,   false, false)
addCommandHandler("stopresource",    cmdStop,    false, false)
addCommandHandler("stopres",         cmdStop,    false, false)
addCommandHandler("restartresource", cmdRestart, false, false)
addCommandHandler("restartres",      cmdRestart, false, false)
