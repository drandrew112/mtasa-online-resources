if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    resourceGroups.lua
    ---------------------------------------------------------------------------
    /restartgroup <name>

    Restarts a named group of resources: stops every running member, then
    starts them again in dependency order (loadResources.lua's buildOrder).
    Resources outside the group that went down with it (they <include> a
    member) are started again as well.

    Only members that were running are restarted - a resource stopped on
    purpose stays stopped.

    Access: server console, or an in-game player with admin_level >= 5.
    See commandAuth.lua.
]]

-- name -> { folders = { "[folder]", ... }, names = { "resource", ... } }
-- folders = organizational path (the [folder] the resource sits in),
-- names   = extra resources listed one by one.
local GROUPS = {
    gov = { folders = { "[government]" } },
    med = { folders = { "[medical]" } },
    rw  = { folders = { "[railways]" } },
}

-- Never restarted from here, even if a group would match them.
local PROTECT = {
    [getResourceName(resource)] = true,   -- ourselves (v_main)
    ["v_mysql"] = true,                   -- shared DB layer - backs the level check
}

-- stopResource takes effect on the next server frame; wait before starting.
local RESTART_DELAY = 2000

local busy = false

local function log(msg)
    outputServerLog("[v_main:restartgroup] " .. tostring(msg))
end

local function actor(player)
    if not isElement(player) then return "console" end
    return ("%s (#%s)"):format(getPlayerName(player), tostring(getElementData(player, "ID")))
end

local function groupList()
    local names = {}
    for name in pairs(GROUPS) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ", ")
end

--- True when `res` belongs to `group`.
local function isMember(group, res)
    local name = getResourceName(res)
    if not name or PROTECT[name] then return false end

    for _, n in ipairs(group.names or {}) do
        if n == name then return true end
    end
    local path = getResourceOrganizationalPath(res) or ""
    for _, folder in ipairs(group.folders or {}) do
        -- the folder can be nested: "[a]/[b]"
        if path == folder or path:find(folder, 1, true) then return true end
    end
    return false
end

--- Running members of a group: { name = true }, count.
local function runningMembers(group)
    local members, count = {}, 0
    for _, res in ipairs(getResources()) do
        if getResourceState(res) == "running" and isMember(group, res) then
            members[getResourceName(res)] = true
            count = count + 1
        end
    end
    return members, count
end

--- Public: restart the group `groupName`. Calls `done(started, failed)` when finished.
--- Returns false + reason ("unknown" | "busy" | "empty"), or true + member count.
function restartResourceGroup(groupName, triggeredBy, done)
    local group = GROUPS[groupName]
    if not group then return false, "unknown" end
    if busy then return false, "busy" end

    local members, count = runningMembers(group)
    if count == 0 then return false, "empty" end
    busy = true

    -- everything running now: dependents outside the group are stopped by MTA
    -- together with the member they include, and must come back too
    local wasRunning = {}
    for _, res in ipairs(getResources()) do
        if getResourceState(res) == "running" then
            wasRunning[getResourceName(res)] = true
        end
    end

    log(("Restarting group '%s' (%d resource(s), by %s)."):format(groupName, count, tostring(triggeredBy)))
    for name in pairs(members) do
        local res = getResourceFromName(name)
        if not (res and stopResource(res)) then
            log("WARNING: could not stop " .. name)
        end
    end

    setTimer(function()
        -- pick up meta/file changes made on disk
        refreshResources(false)

        local started, failed = 0, 0
        local resources, order = buildResourceOrder()
        for _, name in ipairs(order) do
            local res = resources[name]
            if wasRunning[name] and res and getResourceState(res) ~= "running" then
                if startResource(res, true) then
                    started = started + 1
                else
                    failed = failed + 1
                    log("  FAILED to start: " .. name)
                end
            end
        end

        log(("Group '%s' done. Started: %d, failed: %d."):format(groupName, started, failed))
        busy = false
        if done then done(started, failed) end
    end, RESTART_DELAY, 1)

    return true, count
end

addCommandHandler("restartgroup", function(player, cmd, groupName)
    if not canRunAdminCommand(player) then return denyAdminCommand(player, cmd) end

    if not groupName or groupName == "" then
        return commandFeedback(player, "group", L.msg("v_main.resourcegroups.usage", { groups = groupList() }))
    end
    groupName = groupName:lower()

    local ok, result = restartResourceGroup(groupName, actor(player), function(started, failed)
        commandFeedback(player, "group", L.msg("v_main.resourcegroups.done", { name = groupName, started = started, failed = failed }))
    end)

    if ok then
        commandFeedback(player, "group", L.msg("v_main.resourcegroups.restarting", { name = groupName, count = result, player = actor(player) }))
    elseif result == "unknown" then
        commandFeedback(player, "group", L.msg("v_main.resourcegroups.unknown_group", { name = groupName, groups = groupList() }))
    elseif result == "busy" then
        commandFeedback(player, "group", L.msg("v_main.resourcegroups.busy"))
    else
        commandFeedback(player, "group", L.msg("v_main.resourcegroups.nothing_running", { name = groupName }))
    end
end, false, false)
