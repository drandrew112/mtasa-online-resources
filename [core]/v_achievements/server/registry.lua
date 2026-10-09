-- Builds the achievement registry from ACH (config.lua) once at load time.
--
--   REG.list        ordered definitions (config order)
--   REG.byId[id]    definition
--   REG.byStat[s]   { def, ... } sorted by goal ascending
--   REG.categories  ordered { id, name }

REG = { list = {}, byId = {}, byStat = {}, categories = {}, catById = {} }

local function warn(fmt, ...)
    outputDebugString("[v_achievements] " .. string.format(fmt, ...), 2)
end

local function str(v)
    return (type(v) == "string" and v ~= "") and v or nil
end

for _, c in ipairs(ACH.CATEGORIES or {}) do
    local id = type(c) == "table" and str(c.id)
    if id and not REG.catById[id] then
        local cat = { id = id, name = str(c.name) or id }
        REG.catById[id] = cat
        REG.categories[#REG.categories + 1] = cat
    end
end

local function build(src, index)
    if type(src) ~= "table" then
        return warn("entry #%d is not a table, skipped", index)
    end
    local id = str(src.id)
    if not id then return warn("entry #%d has no id, skipped", index) end
    if REG.byId[id] then return warn("duplicate id '%s', skipped", id) end
    if src.type ~= "once" and src.type ~= "progress" then
        return warn("'%s': unknown type '%s', skipped", id, tostring(src.type))
    end
    if not str(src.name) or not str(src.desc) then
        return warn("'%s': name and desc are required, skipped", id)
    end

    local goal, stat
    if src.type == "progress" then
        goal = tonumber(src.goal)
        if not goal or goal <= 0 then
            return warn("'%s': progress needs a positive goal, skipped", id)
        end
        stat = str(src.stat)
    elseif src.stat ~= nil or src.goal ~= nil then
        warn("'%s': stat/goal ignored on a 'once' achievement", id)
    end

    local category = str(src.category)
    if category and not REG.catById[category] then
        warn("'%s': unknown category '%s'", id, category)
        category = nil
    end

    return {
        id       = id,
        type     = src.type,
        name     = src.name,
        desc     = src.desc,
        goal     = goal,
        stat     = stat,
        xp       = math.max(0, math.floor(tonumber(src.xp) or 0)),
        category = category,
        series   = str(src.series),
        tier     = tonumber(src.tier),
        unit     = str(src.unit),
        hidden   = src.hidden == true,
        icon     = str(src.icon),
        order    = index,
    }
end

for i, src in ipairs(ACH.LIST or {}) do
    local def = build(src, i)
    if def then
        REG.byId[def.id] = def
        REG.list[#REG.list + 1] = def
        if def.stat then
            local l = REG.byStat[def.stat] or {}
            l[#l + 1] = def
            REG.byStat[def.stat] = l
        end
    end
end

for _, l in pairs(REG.byStat) do
    table.sort(l, function(a, b)
        if a.goal ~= b.goal then return a.goal < b.goal end
        return a.order < b.order
    end)
end

-- shallow copy so callers in other resources can't mutate the registry
function REG.copy(def)
    local t = {}
    for k, v in pairs(def) do t[k] = v end
    return t
end
