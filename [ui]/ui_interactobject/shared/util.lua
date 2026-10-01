-- Menu definition helpers shared by the server and client registries.

function ioTruthy(value)
    return value ~= nil and value ~= false
end

local function cleanValue(value)
    local t = type(value)
    if t == "function" or t == "thread" then return nil end
    return value
end

local function sanitizeItems(items, depth)
    if type(items) ~= "table" then return nil end
    local out = {}
    for _, item in ipairs(items) do
        if type(item) == "table" and item.label ~= nil then
            local clean = {
                label = tostring(item.label),
                desc = item.desc ~= nil and tostring(item.desc) or nil,
                value = cleanValue(item.value),
                disabled = item.disabled == true or nil,
                closeOnSelect = item.closeOnSelect ~= false,
            }
            if item.items ~= nil and depth < IO.MAX_SUBMENU_DEPTH then
                clean.items = sanitizeItems(item.items, depth + 1) or {}
                clean.title = item.title ~= nil and tostring(item.title) or clean.label
            end
            out[#out + 1] = clean
        end
    end
    return out
end

-- Copies a caller's menu definition into a clean, serialisable table. nil on bad input.
function ioSanitizeDef(def)
    if type(def) ~= "table" then return nil end
    local items = sanitizeItems(def.items, 0)
    if not items then return nil end

    local offset
    if type(def.offset) == "table" then
        offset = { tonumber(def.offset[1]) or 0, tonumber(def.offset[2]) or 0, tonumber(def.offset[3]) or 0 }
    end

    return {
        title = def.title ~= nil and tostring(def.title) or "Interact",
        items = items,
        range = math.max(0.5, math.min(tonumber(def.range) or IO.DEFAULT_RANGE, IO.MAX_RANGE)),
        priority = tonumber(def.priority) or 0,
        offset = offset,
        lineOfSight = def.lineOfSight ~= false,
        allowInVehicle = def.allowInVehicle == true,
        enabled = def.enabled ~= false,
        dataKey = type(def.dataKey) == "string" and def.dataKey or nil,
        dataValue = cleanValue(def.dataValue),
        selfDataKey = type(def.selfDataKey) == "string" and def.selfDataKey or nil,
    }
end

-- def.dataKey / def.dataValue filter on the target element's data.
function ioDataMatches(def, element)
    if not def.dataKey then return true end
    local value = getElementData(element, def.dataKey)
    if def.dataValue ~= nil then return value == def.dataValue end
    return ioTruthy(value)
end

-- Walks an index path ({2, 1} = 2nd item's 1st child). Returns the item and whether any node on
-- the way is disabled.
function ioResolvePath(items, path)
    local item, blocked = nil, false
    for i, index in ipairs(path) do
        item = type(items) == "table" and items[index]
        if not item then return nil end
        if item.disabled then blocked = true end
        if i < #path then items = item.items end
    end
    return item, blocked
end

function ioShallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
