-- ============================================================
--  v_chat / c_commands.lua  (client)
--  Client side command database + the suggestion list under the chat input.
--  Server commands arrive from s_commands.lua ("v_chat:commands").
--  Entry: { name, params, level, desc, resource, auto } (see s_commands.lua)
-- ============================================================

addEvent("v_chat:commandsReady") -- fired locally when v_chat starts: helpers register again

local DB = {}        -- client side commands [lower name]
local serverDB = {}  -- server side commands [lower name]

local HEAD_SCALE, DESC_SCALE = 1.3, 1.1
local HEAD_H, DESC_H, ENTRY_PAD = 22, 17, 8
local MAX_ENTRIES = 5

local function clean(text)
    return (tostring(text):gsub("#%x%x%x%x%x%x", ""))
end

local function adminLevel()
    return tonumber(getElementData(localPlayer, "admin_level")) or 0
end

-- ---------------------------------------------------------------- database

local function dropResource(rname, onlyAuto)
    for k, e in pairs(DB) do
        if e.resource == rname and (not onlyAuto or e.auto) then DB[k] = nil end
    end
end

local function scanResource(res)
    local rname = getResourceName(res)
    dropResource(rname, true)
    local ok, handlers = pcall(getCommandHandlers, res)
    if not ok or type(handlers) ~= "table" then return end
    for _, h in ipairs(handlers) do
        if type(h) == "string" then
            local k = h:lower()
            if not DB[k] then
                DB[k] = { name = clean(h), params = "", level = 0, resource = rname, auto = true }
            end
        end
    end
end

-- rescan every client resource (the chat input calls it each time it opens)
function refreshCommands()
    local ok, list = pcall(getResources)
    if not ok or type(list) ~= "table" then return end
    for _, res in ipairs(list) do scanResource(res) end
end

-- export: registerCommand(name, params, level, description) -> true | false
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
    return true
end

-- export: unregisterCommand(name)
function unregisterCommand(name)
    if type(name) ~= "string" then return false end
    DB[name:lower()] = nil
    return true
end

addEvent("v_chat:commands", true)
addEventHandler("v_chat:commands", root, function(list)
    if type(list) ~= "table" then return end
    serverDB = {}
    for _, c in ipairs(list) do
        serverDB[c[1]:lower()] = { name = c[1], params = c[2] or "", level = c[3] or 0, desc = c[4], auto = c[5] }
    end
end)

addEventHandler("onClientResourceStart", root, function(res)
    if res == resource then return end
    setTimer(function() scanResource(res) end, 200, 1)
end)

addEventHandler("onClientResourceStop", root, function(res)
    if res == resource then return end
    dropResource(getResourceName(res))
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    refreshCommands()
    triggerServerEvent("v_chat:requestCommands", localPlayer)
    setTimer(function() triggerEvent("v_chat:commandsReady", root) end, 200, 1)
end)

-- ---------------------------------------------------------------- running

local function alert(text)
    exports.ui_core:setAlert(text, 255, 90, 90, 4000)
end

-- "/name args" -> runs the client side and / or the server side command
function runChatCommand(text)
    local name, args = text:match("^/(%S+)%s*(.*)$")
    if not name then return end
    local k = name:lower()
    local c, s, level = DB[k], serverDB[k], adminLevel()
    if not c and not s then
        alert(L.msg("v_chat.chat.unknown_command", { cmd = name }))
        return
    end
    local runClient = c and level >= c.level
    local runServer = s and level >= s.level
    if not runClient and not runServer then
        alert(L.msg("v_chat.chat.no_permission"))
        return
    end
    if runClient then executeCommandHandler(c.name, args) end
    if runServer then triggerServerEvent("v_chat:runCommand", localPlayer, name, args) end
end

-- ---------------------------------------------------------------- suggestions

-- commands whose name starts with prefix (all of them when exact is false), the ones above the player's level left out
local function matches(prefix, exact)
    local level, found = adminLevel(), {}
    local seen = {}
    for _, db in ipairs({ DB, serverDB }) do
        for k, e in pairs(db) do
            if not seen[k] and e.level <= level and (exact and k == prefix or (not exact and k:sub(1, #prefix) == prefix)) then
                seen[k] = true
                local other = (db == DB) and serverDB[k] or DB[k]
                local params, desc = e.params, e.desc
                if other then
                    if (params == nil or params == "") then params = other.params end
                    if not desc then desc = other.desc end
                end
                found[#found + 1] = {
                    name = e.name, key = k, params = params or "", level = math.max(e.level, other and other.level or 0), desc = desc,
                    auto = e.auto and (not other or other.auto) or false, -- registered on either side counts as registered
                }
            end
        end
    end
    -- registered commands first, then the automatic ones; alphabetical inside each group
    table.sort(found, function(a, b)
        if a.auto ~= b.auto then return not a.auto end
        return a.key < b.key
    end)
    return found
end

local function wrap(text, width)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local candidate = (line == "") and word or (line.." "..word)
        if line ~= "" and dxGetTextWidth(candidate, DESC_SCALE, "default") > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local cache = { text = nil }

function resetCommandSuggestions() cache.text = nil end

local function build(text, width, maxH)
    local token = text:match("^/(%S*)")
    local list = token and matches(token:lower(), text:find("^/%S*%s") ~= nil) or {}
    local out = { entries = {}, more = 0, h = 0 }
    for i, e in ipairs(list) do
        local lines = e.desc and wrap(e.desc, width - 16) or {}
        local h = HEAD_H + #lines * DESC_H + ENTRY_PAD
        if i > MAX_ENTRIES or out.h + h > maxH then
            out.more = #list - i + 1
            break
        end
        local head = "#FFFFFF/"..e.name
        if e.params ~= "" then head = head.." #9AA0A6"..e.params end
        if e.level > 0 then head = head.." #FF6B6B[admin "..e.level.."]" end
        out.entries[#out.entries + 1] = { head = head, lines = lines, h = h }
        out.h = out.h + h
    end
    if out.more > 0 then out.h = out.h + DESC_H end
    return out
end

-- draws the list with its top at y; call every frame while the input starts with "/"
function drawCommandSuggestions(text, left, y, width, maxH)
    if text:sub(1, 1) ~= "/" then return end
    if cache.text ~= text or cache.width ~= width then
        cache = build(text, width, maxH)
        cache.text, cache.width = text, width
    end
    if #cache.entries == 0 then return end
    dxDrawRectangle(left, y, width, cache.h, tocolor(0, 0, 0, 170))
    local cy = y
    for _, e in ipairs(cache.entries) do
        dxDrawText(e.head, left + 8, cy + 3, _, _, tocolor(255, 255, 255, 255), HEAD_SCALE, "default-bold", "left", "top", false, false, false, true)
        for i, line in ipairs(e.lines) do
            dxDrawText(line, left + 8, cy + HEAD_H + (i - 1) * DESC_H, _, _, tocolor(200, 200, 200, 255), DESC_SCALE, "default")
        end
        cy = cy + e.h
    end
    if cache.more > 0 then
        dxDrawText("+"..cache.more, left + 8, cy, _, _, tocolor(160, 160, 160, 255), DESC_SCALE, "default")
    end
end

-- Tab: "/na" -> "/name ", pressing Tab again cycles through the matches
local tab -- { base, names, i, text }
function completeCommand(text)
    if tab and tab.text == text then
        tab.i = tab.i % #tab.names + 1
    else
        local token = text:match("^/(%S*)$")
        if not token then return nil end
        local names = {}
        for _, e in ipairs(matches(token:lower(), false)) do names[#names + 1] = e.name end
        if #names == 0 then return nil end
        tab = { names = names, i = 1 }
    end
    tab.text = "/"..tab.names[tab.i].." "
    return tab.text
end
