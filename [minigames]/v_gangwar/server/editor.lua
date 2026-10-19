-- /gangwareditor (admin_level >= GW.ADMIN_LEVEL): the client edits a copy of a gang war on foot (positions are taken
-- from the editor's own ped) and sends the whole doc on save. Every request re-checks the permission.

local editors = {}  -- player -> true

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= GW.ADMIN_LEVEL
end

local function accountName(player)
    local ok, name = pcall(function() return exports.v_accounts:getName(player) end)
    return ok and type(name) == "string" and name ~= "" and name or getPlayerName(player)
end

local function notify(player, key, params)
    triggerClientEvent(player, "gangwar:notify", resourceRoot, L.msg("v_gangwar.editor.title"), L.msg(key, params))
end

-- the list the editor shows: every gang war with its run state and cooldown
local function listFor()
    local t = getRealTime().timestamp
    local out = {}
    for id, gw in pairs(GangWars.list) do
        local state, starter = Runtime_status(id)
        local copy = {}
        for k, v in pairs(gw) do copy[k] = v end
        copy.state = state
        copy.starter = isElement(starter) and getPlayerName(starter) or false
        copy.cooldown = GangWars.cooldownLeft(gw, t)
        out[#out + 1] = copy
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function sendList(player)
    triggerClientEvent(player, "gangwar:editorList", resourceRoot, listFor())
end

local function guard(player)
    if not editors[player] then return false end
    if not isAdmin(player) then
        editors[player] = nil
        triggerClientEvent(player, "gangwar:editorStop", resourceRoot)
        return false
    end
    return true
end

addCommandHandler("gangwareditor", function(player)
    if not isAdmin(player) then
        notify(player, "v_gangwar.editor.no_permission")
        return
    end
    if not GangWars.loaded then
        notify(player, "v_gangwar.editor.not_loaded")
        return
    end
    if editors[player] then
        editors[player] = nil
        triggerClientEvent(player, "gangwar:editorStop", resourceRoot)
        return
    end
    editors[player] = true
    triggerClientEvent(player, "gangwar:editorStart", resourceRoot, listFor())
end)

local function on(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function(...)
        if not guard(client) then return end
        fn(client, ...)
    end)
end

on("gangwar:editorClose", function(player)
    editors[player] = nil
end)

on("gangwar:editorRequestList", function(player)
    sendList(player)
end)

on("gangwar:editorSave", function(player, doc)
    local gw, err = Sanitize.doc(doc)
    if not gw then
        triggerClientEvent(player, "gangwar:editorSaved", resourceRoot, false, err)
        return
    end
    if gw.id and not GangWars.get(gw.id) then
        triggerClientEvent(player, "gangwar:editorSaved", resourceRoot, false, "not_found")
        return
    end
    if gw.id then Runtime_abort(gw.id, "admin") end
    GangWars.save(gw, accountName(player), function(id)
        if not isElement(player) then return end
        triggerClientEvent(player, "gangwar:editorSaved", resourceRoot, id or false, not id and "db_error" or nil,
            id and GangWars.get(id) or nil)
        if editors[player] then sendList(player) end
    end)
end)

on("gangwar:editorDelete", function(player, id)
    id = tonumber(id)
    if not GangWars.get(id) then return end
    Runtime_abort(id, "deleted")
    GangWars.delete(id)
    notify(player, "v_gangwar.editor.deleted")
    sendList(player)
end)

on("gangwar:editorResetCooldown", function(player, id)
    if GangWars.setLastRun(id, false) then
        notify(player, "v_gangwar.editor.cooldown_reset")
        sendList(player)
    end
end)

on("gangwar:editorAbort", function(player, id)
    Runtime_abort(id, "admin")
    sendList(player)
end)

on("gangwar:editorTest", function(player, id)
    local gw = GangWars.get(id)
    if not gw then return end
    local ok, err = Runtime_testRun(gw, player)
    if ok then
        notify(player, "v_gangwar.editor.test_started")
    else
        notify(player, "v_gangwar.editor.test_failed_" .. tostring(err))
    end
    sendList(player)
end)

addEventHandler("onPlayerQuit", root, function() editors[source] = nil end)
