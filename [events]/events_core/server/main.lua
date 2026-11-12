-- events_core: registry of the seasonal events and their on / off state.
--
-- An event resource (events_xmas ...) registers { name, description, models, maps }. An event is ON when
--   * the running week of v_weekly has it switched on (v_admin Weekly > Events, week value "events"), or
--   * the /events test override says so (until the next week change).
-- events_core then asks v_modloader (setEventModelEnabled) and maps_loader (setEventMapEnabled) to load the
-- models / maps of every ON event and to drop those of every OFF one; a model or map shared by two events
-- stays loaded while either of them is on. Nothing is saved here: the weekly row is the source of truth, so a
-- restart of any resource just pushes the state again.

local events = {}       -- [id] = { id, name, description, models, maps, resource }
local order = {}        -- ids in registration order
local weekly = {}       -- [id] = true: switched on by the running week
local override = {}     -- [id] = true | false: /events test override
local active = {}       -- [id] = true: state the event resources were told about
local weekStart = nil
local warned = {}

addEvent("onEventsCoreStart")
addEvent("onEventStarted")
addEvent("onEventStopped")
addEvent("onWeeklyChanged")
addEvent("onModLoaderStart")
addEvent("onMapsLoaderStart")

local function log(text) outputServerLog("[events_core] " .. text) end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running" or false
end

local function desired(id)
    if override[id] ~= nil then return override[id] end
    return weekly[id] == true
end

---------------------------------------------------------------------------- weekly

-- reads the running week; false when v_weekly is not available (the state is then left as it is)
local function readWeekly()
    if not running("v_weekly") then return false end
    local ok, value = pcall(function() return exports.v_weekly:getWeekValue(EVENTS.WEEKLY_KEY) end)
    if not ok then return false end
    local new = {}
    if type(value) == "table" then
        for id, on in pairs(value) do
            if on == true then new[tostring(id)] = true end
        end
    end
    weekly = new
    return true
end

---------------------------------------------------------------------------- apply

local function warnOnce(key, text)
    if warned[key] then return end
    warned[key] = true
    log(text)
end

-- pushes the models / maps of every registered event and tells the event resources about changes
local function apply()
    local models, maps = {}, {}     -- [id / name] = wanted
    for _, id in ipairs(order) do
        local on = desired(id)
        for _, m in ipairs(events[id].models) do models[m] = models[m] or on end
        for _, m in ipairs(events[id].maps) do maps[m] = maps[m] or on end
    end

    if running("v_modloader") then
        for model, on in pairs(models) do
            local ok, res = pcall(function() return exports.v_modloader:setEventModelEnabled(model, on) end)
            if not ok then
                warnOnce("modelcall", "v_modloader:setEventModelEnabled call failed (export missing from v_modloader meta.xml?)")
            elseif res == false then
                warnOnce("model" .. model, ("v_modloader refused event model %d (not in config EVENT_OBJECTS?)"):format(model))
            end
        end
    end
    if running("maps_loader") then
        for name, on in pairs(maps) do
            local ok, res = pcall(function() return exports.maps_loader:setEventMapEnabled(name, on) end)
            if not ok or res == false then
                warnOnce("map" .. name, ("maps_loader refused event map %s (settings.json \"event\": true missing?)"):format(name))
            end
        end
    end

    for _, id in ipairs(order) do
        local on = desired(id)
        if on ~= (active[id] == true) then
            active[id] = on or nil
            log(("event %s %s"):format(id, on and "STARTED" or "STOPPED"))
            triggerEvent(on and "onEventStarted" or "onEventStopped", root, id)
        end
    end
end

local function refresh()
    readWeekly()
    apply()
end

addEventHandler("onWeeklyChanged", root, function(ws)
    ws = tonumber(ws)
    -- a new week ends the /events test overrides
    if ws and weekStart and ws ~= weekStart and next(override) then
        override = {}
        log("new week: /events overrides cleared")
    end
    weekStart = ws or weekStart
    refresh()
end)

-- the consumers lose their runtime state when restarted
addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "v_weekly" or name == "v_modloader" or name == "maps_loader" then
        setTimer(refresh, EVENTS.SYNC_DELAY, 1)
    end
end)
addEventHandler("onModLoaderStart", root, function() setTimer(apply, 500, 1) end)
addEventHandler("onMapsLoaderStart", root, function() setTimer(apply, 500, 1) end)

---------------------------------------------------------------------------- registry

local function cleanList(list, kind)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, v in ipairs(list) do
        if kind == "number" then v = tonumber(v) else v = type(v) == "string" and v or nil end
        if v then out[#out + 1] = v end
    end
    return out
end

--- registerEvent(id, { name, description, models = { id, ... }, maps = { "name", ... } }) -> bool
--- Registering an id again replaces the earlier definition (event resources register on every start).
function registerEvent(id, def)
    if type(id) ~= "string" or not id:match("^[%w_]+$") or type(def) ~= "table" then return false end
    local owner = sourceResource
    local known = events[id] ~= nil
    events[id] = {
        id = id,
        name = type(def.name) == "string" and def.name or id,
        description = type(def.description) == "string" and def.description or "",
        models = cleanList(def.models, "number"),
        maps = cleanList(def.maps, "string"),
        resource = owner and getResourceName(owner) or nil,
    }
    if not known then order[#order + 1] = id end
    log(("event %s registered by %s (%d model(s), %d map(s))"):format(id, events[id].resource or "?",
        #events[id].models, #events[id].maps))
    -- an event that is already on when its resource (re)starts hears about it from apply()
    refresh()
    return true
end

local function remove(id)
    if not events[id] then return false end
    -- switch its models / maps off while the definition is still known
    local wasOn = desired(id)
    override[id] = nil
    local keep = events[id]
    events[id] = nil
    for i, v in ipairs(order) do if v == id then table.remove(order, i) break end end
    active[id] = nil
    -- models / maps only this event used: push them off
    if running("v_modloader") then
        for _, m in ipairs(keep.models) do
            local shared = false
            for _, other in pairs(events) do
                for _, om in ipairs(other.models) do if om == m and desired(other.id) then shared = true end end
            end
            if not shared then pcall(function() exports.v_modloader:setEventModelEnabled(m, false) end) end
        end
    end
    if running("maps_loader") then
        for _, m in ipairs(keep.maps) do
            local shared = false
            for _, other in pairs(events) do
                for _, om in ipairs(other.maps) do if om == m and desired(other.id) then shared = true end end
            end
            if not shared then pcall(function() exports.maps_loader:setEventMapEnabled(m, false) end) end
        end
    end
    if wasOn then triggerEvent("onEventStopped", root, id) end
    log("event " .. id .. " unregistered")
    return true
end

function unregisterEvent(id)
    if type(id) ~= "string" then return false end
    return remove(id)
end

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local name = getResourceName(res)
    local gone = {}
    for id, e in pairs(events) do
        if e.resource == name then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do remove(id) end
end)

function isEventRegistered(id) return events[tostring(id)] ~= nil end
function isEventActive(id) return active[tostring(id)] == true end

function getActiveEvents()
    local out = {}
    for _, id in ipairs(order) do
        if active[id] then out[#out + 1] = id end
    end
    return out
end

function getEvents()
    local out = {}
    for _, id in ipairs(order) do
        local e = events[id]
        out[#out + 1] = {
            id = id, name = e.name, description = e.description, models = e.models, maps = e.maps, resource = e.resource,
            active = active[id] == true, weekly = weekly[id] == true, override = override[id],
        }
    end
    return out
end

--- state: true | false | nil (nil = follow the weekly schedule again)
function setEventOverride(id, state)
    id = tostring(id)
    if not events[id] then return false end
    if state == nil then override[id] = nil else override[id] = state == true end
    apply()
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        refresh()
        triggerEvent("onEventsCoreStart", root)
    end, 500, 1)
end)

---------------------------------------------------------------------------- /events (test command)

local function say(player, text)
    if isElement(player) then outputConsole("[events] " .. text, player) else outputServerLog("[events] " .. text) end
end

local function allowed(player)
    if not isElement(player) then return true end
    if getElementData(player, "isLogged") ~= true then return false end
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(level) or 0) >= EVENTS.ADMIN_LEVEL
end

local function listEvents(player)
    if #order == 0 then return say(player, "No event is registered.") end
    for _, id in ipairs(order) do
        local e = events[id]
        local src = override[id] ~= nil and (override[id] and "override ON" or "override OFF")
            or (weekly[id] and "weekly" or "weekly off")
        say(player, ("%s (%s): %s [%s] - %d model(s), %d map(s)"):format(id, e.name,
            active[id] and "ACTIVE" or "inactive", src, #e.models, #e.maps))
    end
end

-- /events                   list
-- /events list              list
-- /events <id> [on|off|auto]  test: switch an event (no argument = toggle) until the next week change;
--                             auto = follow the weekly schedule again
addCommandHandler("events", function(player, _, sub, mode)
    if not allowed(player) then return say(player, "Access denied.") end
    sub = tostring(sub or ""):lower()
    if sub == "" or sub == "list" then return listEvents(player) end

    if not events[sub] then
        say(player, ("Unknown event '%s'. Usage: /events | /events list | /events <id> [on|off|auto]"):format(sub))
        return listEvents(player)
    end
    mode = tostring(mode or ""):lower()
    local state
    if mode == "on" then state = true
    elseif mode == "off" then state = false
    elseif mode == "auto" then state = nil
    elseif mode == "" then state = not desired(sub)
    else return say(player, "Usage: /events <id> [on|off|auto]") end
    setEventOverride(sub, state)
    say(player, ("%s: %s%s"):format(sub, active[sub] and "ACTIVE" or "inactive",
        state == nil and " (weekly schedule)" or " (test override until the next week change)"))
end)
