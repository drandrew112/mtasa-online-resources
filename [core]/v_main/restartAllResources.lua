--[[
    restartAllResources.lua
    ---------------------------------------------------------------------------
    /restartallresource

    Stops every running server resource except v_main itself (plus a short
    protect list), then re-runs v_main's dependency-ordered loader
    (loadResources.lua) to bring everything back up in the correct order.

    Access: server console, or an in-game player with admin_level >= 5.
    See commandAuth.lua.
]]

-- Milliseconds to wait after requesting the stops before reloading.
-- stopResource takes effect on the next server frame, so we must not start
-- again in the same tick.
local RELOAD_DELAY = 2000

-- Never stopped from here.
local PROTECT = {
    [getResourceName(resource)] = true,   -- ourselves (v_main)

    -- Never auto-started by loadResources.lua either - stopping them here
    -- would leave them down.
    ["ai_autoplayer"] = true,
    ["tiktok-live"]   = true,

    -- Shared DB layer. Keeping it up avoids every just-restarted resource
    -- racing to reconnect, and v_main's own admin-level check needs it. It
    -- changes rarely; restart it by hand when it does.
    ["v_mysql"] = true,

    -- MTA's own management resources, if this server has them installed.
    ["admin"]           = true,
    ["webadmin"]        = true,
    ["resourcebrowser"] = true,
    ["runcode"]         = true,
}

local function log(msg)
    outputServerLog("[v_main:restartall] " .. tostring(msg))
end

local busy = false

--- Stop every running, non-protected resource. Returns the count.
local function stopAll()
    local stopped = 0
    for _, res in ipairs(getResources()) do
        local name = getResourceName(res)
        if name and not PROTECT[name] and getResourceState(res) == "running" then
            if stopResource(res) then
                stopped = stopped + 1
            else
                log("WARNING: could not stop " .. name)
            end
        end
    end
    return stopped
end

--- Public: stop everything (except the protect list) and reload in order.
function restartAllResources(triggeredBy)
    if busy then
        log("A restart is already in progress - ignoring this request.")
        return false
    end
    busy = true

    log(("Full resource restart requested (%s)."):format(triggeredBy or "unknown"))

    local stopped = stopAll()
    log(("Stop requested for %d resource(s); reloading in %d ms.")
        :format(stopped, RELOAD_DELAY))

    setTimer(function()
        -- Pick up any meta/file changes made on disk (e.g. a manual git pull)
        -- before starting everything back up.
        refreshResources(false)

        if type(loadAllResources) == "function" then
            loadAllResources()
        else
            log("ERROR: loadAllResources() unavailable - is loadResources.lua loaded?")
        end
        busy = false
    end, RELOAD_DELAY, 1)

    return true
end

addCommandHandler("restartallresource", function(player)
    if not canRunAdminCommand(player) then
        return denyAdminCommand(player, "restartallresource")
    end

    local who = isElement(player)
        and ("player " .. getPlayerName(player) .. " (#" .. tostring(getElementData(player, "ID")) .. ")")
        or  "console"

    commandFeedback(player, "restartall", "Restarting all resources...")
    restartAllResources(who)
end, false, false)
