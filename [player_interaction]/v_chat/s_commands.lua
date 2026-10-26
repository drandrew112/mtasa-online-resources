-- ============================================================
--  v_chat / s_commands.lua  (server)
--  Command database for the "/" commands of the chat.
--
--  Entry: { name, params, level, desc, resource, auto }
--    * auto = true  -> found with getCommandHandlers (no params / description, level 0)
--    * auto = false -> registered by a resource with registerCommand (wins over auto)
--  Level = minimum element data "admin_level" needed to see / run it from the chat.
--  Server commands are pushed to every client (c_commands.lua), which merges them
--  with its own client side commands.
--
--  Resources register through the helper: loadstring(exports.v_chat:importCommands())()
--  then CMD.register(name, params, level, description)  (see COMMANDS.md)
-- ============================================================

addEvent("v_chat:commandsReady") -- fired (root) when v_chat starts: helpers register again

local DB = {}            -- [lower name] = entry
local pushTimer
local MAX_ARGS = 300

local function clean(text)
    return (tostring(text):gsub("#%x%x%x%x%x%x", ""))
end

local function adminLevel(player)
    return tonumber(getElementData(player, "admin_level")) or 0
end

local function alert(player, text)
    triggerClientEvent(player, "chat:muteAlert", player, text, 255, 90, 90, 4000)
end

local function pushList(target)
    local list = {}
    for _, e in pairs(DB) do
        list[#list + 1] = { e.name, e.params, e.level, e.desc }
    end
    triggerClientEvent(target, "v_chat:commands", root, list)
end

-- one push after a burst of changes (many resources start together)
local function schedulePush()
    if isTimer(pushTimer) then return end
    pushTimer = setTimer(function() pushList(root) end, 1000, 1)
end

local function dropResource(rname, onlyAuto)
    for k, e in pairs(DB) do
        if e.resource == rname and (not onlyAuto or e.auto) then DB[k] = nil end
    end
end

local function scanResource(res)
    local rname = getResourceName(res)
    dropResource(rname, true)
    local handlers = getCommandHandlers(res)
    if type(handlers) ~= "table" then return end
    for _, h in ipairs(handlers) do
        if type(h) == "string" then
            local k = h:lower()
            if not DB[k] then
                DB[k] = { name = clean(h), params = "", level = 0, resource = rname, auto = true }
            end
        end
    end
end

local function scanAll()
    for _, res in ipairs(getResources()) do
        if getResourceState(res) == "running" then scanResource(res) end
    end
    schedulePush()
end

-- export: registerCommand(name, params, level, description)  -> true | false
-- params e.g. "<player> [minutes]", level = admin level (default 0)
function registerCommand(name, params, level, description)
    if type(name) ~= "string" or not name:match("^[%w_%-%.]+$") then return false end
    DB[name:lower()] = {
        name = name,
        params = type(params) == "string" and clean(params) or "",
        level = tonumber(level) or 0,
        desc = type(description) == "string" and clean(description) or nil,
        resource = sourceResource and getResourceName(sourceResource) or "?",
        auto = false,
    }
    schedulePush()
    return true
end

-- export: unregisterCommand(name)
function unregisterCommand(name)
    if type(name) ~= "string" then return false end
    DB[name:lower()] = nil
    schedulePush()
    return true
end

-- export: getCommandInfo(name) -> { name, params, level, desc, resource } | false
function getCommandInfo(name)
    local e = type(name) == "string" and DB[name:lower()]
    if not e then return false end
    return { name = e.name, params = e.params, level = e.level, desc = e.desc, resource = e.resource }
end

-- export: Lua source of the helper other resources load (CMD.register)
function importCommands()
    return [[
if not CMD then
    CMD = {}
    local list = {}
    local function send(c) pcall(function() exports.v_chat:registerCommand(c[1], c[2], c[3], c[4]) end) end
    -- CMD.register(name, params, level, description)  e.g. CMD.register("kill", "<player>", 3, "Kills a player.")
    function CMD.register(name, params, level, description)
        local c = { name, params, level, description }
        list[#list + 1] = c
        send(c)
    end
    -- v_chat (re)started: its database is empty again
    addEvent("v_chat:commandsReady", false)
    addEventHandler("v_chat:commandsReady", root, function()
        for _, c in ipairs(list) do send(c) end
    end)
end
]]
end

addEvent("v_chat:requestCommands", true)
addEventHandler("v_chat:requestCommands", root, function()
    if isElement(client) then pushList(client) end
end)

-- "/name args" typed in the chat
addEvent("v_chat:runCommand", true)
addEventHandler("v_chat:runCommand", root, function(name, args)
    local player = client
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return end
    if type(name) ~= "string" then return end
    args = type(args) == "string" and args or ""
    if #args > MAX_ARGS then args = args:sub(1, MAX_ARGS) end
    local e = DB[name:lower()]
    if not e then
        alert(player, L.msg("v_chat.chat.unknown_command", { cmd = name }))
        return
    end
    if adminLevel(player) < e.level then
        alert(player, L.msg("v_chat.chat.no_permission"))
        return
    end
    executeCommandHandler(e.name, player, args)
end)

addEventHandler("onResourceStart", root, function(res)
    if res == resource then return end
    setTimer(function() if getResourceState(res) == "running" then scanResource(res) schedulePush() end end, 200, 1)
end)

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    dropResource(getResourceName(res))
    schedulePush()
end)

addEventHandler("onResourceStart", resourceRoot, function()
    scanAll()
    -- registrations made before v_chat was running are lost: ask the helpers to send them again
    setTimer(function() triggerEvent("v_chat:commandsReady", root) end, 100, 1)
end)
