-- /collecteditor (admin_level >= COLLECT.ADMIN_LEVEL): live list editing. Every change is written to the list's
-- JSON file at once, pushed to every open editor and re-synced to the players (only active lists reach them).

local editors = {}      -- [player] = true

local function log(text) outputServerLog("[v_collectibles] " .. text) end

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true and getElementData(player, "loaded") ~= true then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= COLLECT.ADMIN_LEVEL
end

local function money(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return out .. " €"
end

local function notify(player, key, params)
    triggerClientEvent(player, "v_collectibles:editorNotify", resourceRoot, key, params)
end

-- editor view of one list (with every item, collected or not)
local function editorList(list)
    return { id = list.id, name = list.name, event = list.event, enabled = list.enabled, spin = list.spin, reward = list.reward,
        models = list.models, items = list.items, active = isListActive(list.id), eventOn = isEventListEnabled(list.id) }
end

local function editorData()
    local out = {}
    for _, id in ipairs(ListOrder) do out[#out + 1] = editorList(Lists[id]) end
    return out
end

function pushEditors()
    local data = editorData()
    for p in pairs(editors) do
        if isElement(p) then
            triggerLatentClientEvent(p, "v_collectibles:editorData", 500000, false, resourceRoot, data)
        else
            editors[p] = nil
        end
    end
end

-- after a change of `list`: file, editors, players
local function changed(list, who)
    saveList(list)
    pushEditors()
    syncAll()
    log(("%s changed list %s"):format(getPlayerName(who), list.id))
end

local function editorCall(player)
    if not editors[player] then return false end
    if not isAdmin(player) then
        editors[player] = nil
        triggerClientEvent(player, "v_collectibles:editorState", resourceRoot, false)
        return false
    end
    return true
end

---------------------------------------------------------------------------- open / close

local function setEditor(player, on)
    editors[player] = on or nil
    triggerClientEvent(player, "v_collectibles:editorState", resourceRoot, on, on and editorData() or nil)
end

addCommandHandler("collecteditor", function(player)
    if not isAdmin(player) then return notify(player, "v_collectibles.editor.no_access") end
    setEditor(player, not editors[player])
end)

addEvent("v_collectibles:editorClose", true)
addEventHandler("v_collectibles:editorClose", resourceRoot, function()
    if editors[client] then setEditor(client, false) end
end)

addEventHandler("onPlayerQuit", root, function() editors[source] = nil end)

---------------------------------------------------------------------------- list operations

local function uniqueId(base)
    base = tostring(base or ""):lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if base == "" then base = "list" end
    base = base:sub(1, COLLECT.ID_MAX - 3)
    local id, n = base, 1
    while Lists[id] do
        n = n + 1
        id = base .. "_" .. n
    end
    return id
end

addEvent("v_collectibles:editorCreateList", true)
addEventHandler("v_collectibles:editorCreateList", resourceRoot, function(name)
    if not editorCall(client) then return end
    name = cleanName(name, "")
    if name == "" then return notify(client, "v_collectibles.editor.name_empty") end
    local list = sanitizeList(uniqueId(name), { name = name, enabled = false, spin = true })
    changed(list, client)
    triggerClientEvent(client, "v_collectibles:editorSelect", resourceRoot, list.id)
    notify(client, "v_collectibles.editor.list_created", { name = list.name, id = list.id })
end)

addEvent("v_collectibles:editorDeleteList", true)
addEventHandler("v_collectibles:editorDeleteList", resourceRoot, function(listId)
    if not editorCall(client) or not Lists[listId] then return end
    local name = Lists[listId].name
    deleteListFile(listId)
    pushEditors()
    syncAll()
    log(("%s deleted list %s"):format(getPlayerName(client), listId))
    notify(client, "v_collectibles.editor.list_deleted", { name = name })
end)

-- field: "name" (string) | "reward" (number) | "event" | "enabled" | "spin" (bool) | "addModel" | "removeModel" (model id)
addEvent("v_collectibles:editorSet", true)
addEventHandler("v_collectibles:editorSet", resourceRoot, function(listId, field, value)
    if not editorCall(client) then return end
    local list = Lists[listId]
    if not list then return end
    if field == "name" then
        local name = cleanName(value, "")
        if name == "" then return notify(client, "v_collectibles.editor.name_empty") end
        list.name = name
    elseif field == "reward" then
        local r = tonumber(value)
        if not r or r ~= r or r < 0 or r > COLLECT.MAX_REWARD then
            return notify(client, "v_collectibles.editor.bad_reward", { max = COLLECT.MAX_REWARD })
        end
        list.reward = math.floor(r)
        changed(list, client)
        return notify(client, "v_collectibles.editor.reward_set",
            { reward = money(list.reward), total = money(list.reward * #list.items), count = #list.items })
    elseif field == "event" or field == "enabled" or field == "spin" then
        list[field] = value == true
    elseif field == "addModel" then
        local m = math.floor(tonumber(value) or -1)
        if m < 0 or m > 65535 then return notify(client, "v_collectibles.editor.bad_model") end
        for _, have in ipairs(list.models) do
            if have == m then return notify(client, "v_collectibles.editor.model_exists", { model = m }) end
        end
        if #list.models >= COLLECT.MAX_MODELS then return notify(client, "v_collectibles.editor.too_many_models") end
        list.models[#list.models + 1] = m
        notify(client, "v_collectibles.editor.model_added", { model = m })
    elseif field == "removeModel" then
        local m = tonumber(value)
        for i, have in ipairs(list.models) do
            if have == m then table.remove(list.models, i) break end
        end
    else
        return
    end
    changed(list, client)
end)

---------------------------------------------------------------------------- item operations

local function num(v) v = tonumber(v); return (v and v == v and v ~= math.huge and v ~= -math.huge) and v or nil end

addEvent("v_collectibles:editorAddItem", true)
addEventHandler("v_collectibles:editorAddItem", resourceRoot, function(listId, model, x, y, z, rz)
    if not editorCall(client) then return end
    local list = Lists[listId]
    if not list then return end
    model = math.floor(tonumber(model) or -1)
    local okModel = false
    for _, m in ipairs(list.models) do if m == model then okModel = true end end
    if not okModel then return notify(client, "v_collectibles.editor.bad_model") end
    x, y, z, rz = num(x), num(y), num(z), num(rz) or 0
    if not (x and y and z) then return end
    if #list.items >= COLLECT.MAX_ITEMS then return notify(client, "v_collectibles.editor.too_many_items") end
    local id = list.nextId
    list.nextId = id + 1
    local item = {
        id = id, model = model,
        x = math.floor(x * 1000 + 0.5) / 1000, y = math.floor(y * 1000 + 0.5) / 1000, z = math.floor(z * 1000 + 0.5) / 1000,
        rx = 0, ry = 0, rz = math.floor((rz % 360) * 10 + 0.5) / 10,
        int = getElementInterior(client), dim = getElementDimension(client),
    }
    list.items[#list.items + 1] = item
    list.byId[id] = item
    changed(list, client)
    notify(client, "v_collectibles.editor.item_added", { id = id, count = #list.items })
end)

addEvent("v_collectibles:editorDeleteItem", true)
addEventHandler("v_collectibles:editorDeleteItem", resourceRoot, function(listId, itemId)
    if not editorCall(client) then return end
    local list = Lists[listId]
    itemId = tonumber(itemId)
    if not list or not itemId or not list.byId[itemId] then return end
    for i, it in ipairs(list.items) do
        if it.id == itemId then table.remove(list.items, i) break end
    end
    list.byId[itemId] = nil
    changed(list, client)
    notify(client, "v_collectibles.editor.item_deleted", { id = itemId })
end)

-- teleport to an item (its interior / dimension too)
addEvent("v_collectibles:editorTeleport", true)
addEventHandler("v_collectibles:editorTeleport", resourceRoot, function(listId, itemId)
    if not editorCall(client) then return end
    local list = Lists[listId]
    local it = list and list.byId[tonumber(itemId) or 0]
    if not it then return end
    local veh = getPedOccupiedVehicle(client)
    if veh then removePedFromVehicle(client) end
    setElementInterior(client, it.int)
    setElementDimension(client, it.dim)
    setElementPosition(client, it.x + 1.5, it.y, it.z + 1)
end)
