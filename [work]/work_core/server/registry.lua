-- Work registry. work_core stores no works by default: every work resource registers its own
-- with registerWork(). A work is owned by the resource that registered it and is removed
-- (markers destroyed, players taken off duty) when that resource stops.

Works = {}                         -- id -> { id, name, description, color, skins, owner }

local thisResource = getThisResource()
local readyPlayers = {}            -- players whose work_core client scripts are running

-- Name of the resource that called the current export (nil for internal calls)
function getCallerResourceName()
    if sourceResource and sourceResource ~= thisResource then
        return getResourceName(sourceResource)
    end
    return nil
end

local function normaliseColor(c)
    if type(c) ~= "table" then return { unpack(WORK.DEFAULT_COLOR) } end
    local r, g, b = tonumber(c[1] or c.r), tonumber(c[2] or c.g), tonumber(c[3] or c.b)
    if not (r and g and b) then return { unpack(WORK.DEFAULT_COLOR) } end
    return { math.floor(r), math.floor(g), math.floor(b) }
end

-- skins = { 274, { model = 275, name = "Paramedic (F)" }, ... } -> { { model, name }, ... }
local function normaliseSkins(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for _, s in ipairs(list) do
        local model, name
        if type(s) == "table" then
            model, name = tonumber(s.model or s[1]), s.name or s[2]
        else
            model = tonumber(s)
        end
        if model then
            model = math.floor(model)
            if not seen[model] then
                seen[model] = true
                local level = type(s) == "table" and tonumber(s.level) or nil
                out[#out + 1] = { model = model, name = name and tostring(name) or ("Outfit " .. model),
                                  level = level and math.max(1, math.floor(level)) or 1 }
            end
        end
    end
    return out
end

-- level settings: maxLevel, levelXp (XP for level 2), levelStep (added per further level),
-- levelNames = { [level] = "Name" }
local function normaliseLevels(def)
    local names = {}
    if type(def.levelNames) == "table" then
        for k, v in pairs(def.levelNames) do
            k = tonumber(k)
            if k and k >= 1 then names[math.floor(k)] = tostring(v) end
        end
    end
    local function num(v, default, min)
        v = tonumber(v)
        return v and math.max(min, math.floor(v)) or default
    end
    return {
        maxLevel = num(def.maxLevel, WORK.MAX_LEVEL, 1),
        baseXp = num(def.levelXp, WORK.LEVEL_BASE_XP, 1),
        stepXp = num(def.levelStep, WORK.LEVEL_STEP_XP, 0),
        names = names,
    }
end

function isWorkSkin(work, model)
    for _, s in ipairs(work.skins) do
        if s.model == model then return true end
    end
    return false
end

---------------------------------------------------------------- client sync

local function publicWorks()
    local t = {}
    for id, w in pairs(Works) do
        t[id] = { id = id, name = w.name, description = w.description, color = w.color, skins = w.skins,
                  levels = w.levels }
    end
    return t
end

function syncWorks(player)
    local targets = {}
    if player then
        if readyPlayers[player] then targets[1] = player end
    else
        for p in pairs(readyPlayers) do
            if isElement(p) then targets[#targets + 1] = p end
        end
    end
    if #targets > 0 then
        triggerClientEvent(targets, "work:sync", resourceRoot, publicWorks())
    end
    if not player then resyncAllLevels() end
end

function isPlayerReady(player)
    return readyPlayers[player] == true
end

addEventHandler("onPlayerResourceStart", root, function(res)
    if res ~= thisResource then return end
    readyPlayers[source] = true
    syncWorks(source)
end)

addEventHandler("onPlayerQuit", root, function()
    readyPlayers[source] = nil
end)

---------------------------------------------------------------- exports

-- registerWork("ems", {
--     name = "EMS", description = "Emergency Medical Services",
--     color = { 220, 50, 50 },
--     skins = { 274, 275, { model = 276, name = "Doctor", level = 5 } },  -- required; level = work level needed
--     maxLevel = 10, levelXp = 500, levelStep = 250,            -- optional, defaults in WORK.*
--     levelNames = { [1] = "Trainee", [5] = "Paramedic" },      -- optional
-- }) -> true | false
-- Registering an id again from the same resource updates it.
function registerWork(id, def)
    if type(id) ~= "string" or id == "" or type(def) ~= "table" then
        outputDebugString("[work_core] registerWork: bad arguments (id string, def table expected)", 2)
        return false
    end
    local skins = normaliseSkins(def.skins)
    if #skins == 0 then
        outputDebugString(("[work_core] registerWork(%s): at least one skin is required"):format(id), 2)
        return false
    end

    local owner = getCallerResourceName()
    local existing = Works[id]
    if existing and existing.owner and owner and existing.owner ~= owner then
        outputDebugString(("[work_core] registerWork(%s): already registered by %s"):format(id, existing.owner), 2)
        return false
    end

    Works[id] = {
        id = id,
        name = tostring(def.name or id),
        description = def.description and tostring(def.description) or "",
        color = normaliseColor(def.color),
        skins = skins,
        levels = normaliseLevels(def),
        owner = owner or (existing and existing.owner) or nil,
    }
    syncWorks()
    outputDebugString(("[work_core] work %s '%s' %s (%d outfits)"):format(id, Works[id].name,
        existing and "updated" or "registered", #skins))
    return true
end

-- Removes the work: every player on duty in it goes off duty (reason "unregistered"),
-- its markers are destroyed.
function unregisterWork(id)
    if not Works[id] then return false end
    endDutyForWork(id, "unregistered")
    destroyMarkersOfWork(id)
    Works[id] = nil
    syncWorks()
    outputDebugString(("[work_core] work %s unregistered"):format(id))
    return true
end

function isWorkRegistered(id)
    return Works[id] ~= nil
end

local function copyWork(w)
    local skins = {}
    for i, s in ipairs(w.skins) do skins[i] = { model = s.model, name = s.name, level = s.level } end
    local names = {}
    for k, v in pairs(w.levels.names) do names[k] = v end
    return { id = w.id, name = w.name, description = w.description,
             color = { unpack(w.color) }, skins = skins, resource = w.owner,
             levels = { maxLevel = w.levels.maxLevel, baseXp = w.levels.baseXp,
                        stepXp = w.levels.stepXp, names = names } }
end

function getWork(id)
    local w = Works[id]
    return w and copyWork(w) or false
end

function getWorks()
    local t = {}
    for id, w in pairs(Works) do t[id] = copyWork(w) end
    return t
end

---------------------------------------------------------------- lifecycle

addEvent("onWorkCoreStart")

addEventHandler("onResourceStart", resourceRoot, function()
    -- Work resources that were already running register again from this event
    triggerEvent("onWorkCoreStart", root)
end)

addEventHandler("onResourceStop", root, function(res)
    if res == thisResource then
        endAllDuties("shutdown")
        return
    end
    local name = getResourceName(res)
    for id, w in pairs(Works) do
        if w.owner == name then unregisterWork(id) end
    end
    destroyMarkersOfOwner(name)
end)
