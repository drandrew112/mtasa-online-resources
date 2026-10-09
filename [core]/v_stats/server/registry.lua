-- Builds the stat registry from STATS (config.lua) once at load time.
--
--   REG.list      ordered definitions (config order)
--   REG.byId[id]  definition

REG = { list = {}, byId = {} }

local function warn(fmt, ...)
    outputDebugString("[v_stats] " .. string.format(fmt, ...), 2)
end

local function str(v)
    return (type(v) == "string" and v ~= "") and v or nil
end

for i, src in ipairs(STATS.LIST) do
    local id = type(src) == "table" and str(src.id)
    if not id then
        warn("entry #%d has no id, skipped", i)
    elseif REG.byId[id] then
        warn("duplicate id '%s', skipped", id)
    elseif not str(src.name) then
        warn("'%s': name is required, skipped", id)
    else
        local def = { id = id, name = src.name, unit = str(src.unit) or "", achStat = str(src.achStat) }
        REG.byId[id] = def
        REG.list[#REG.list + 1] = def
    end
end
