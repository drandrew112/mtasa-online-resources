-- ui_pause / c_api.lua
--
-- Settings API: the pause menu's SETTINGS_TREE as plain data, and setters that
-- apply + persist exactly like the pause menu does. Works before the player is
-- spawned (account menu): the tree is built on the first call.

addEvent("ui_pause:onClientSettingChanged") -- (id, value), source = localPlayer

local function findItem(id)
    ensureSettingsTree()
    for _, cat in ipairs(SETTINGS_TREE) do
        for _, item in ipairs(cat.items) do
            if item.id == id then return item end
        end
    end
end

local function isAvailable(item)
    return (not item.available) or item.available() and true or false
end

local function currentValue(item)
    if not isAvailable(item) then return nil end
    local v = item.get and item.get()
    if item.type == "toggle" then return v and true or false end
    if item.type == "range" then return tonumber(v) or item.default or item.min end
    return v
end

local function optionsOf(item)
    if item.type ~= "choice" or not item.options then return nil end
    local out = {}
    for i, o in ipairs(item.options() or {}) do out[i] = { id = o.id, label = o.label } end
    return out
end

-- shown text of the current value (labels of choices, suffix of ranges)
local function valueTextOf(item, value)
    if not isAvailable(item) then return L("ui_pause.settings.unavailable") end
    local text
    if item.type == "toggle" then
        text = value and L("ui_pause.settings.on") or L("ui_pause.settings.off")
    elseif item.type == "range" then
        text = tostring(value) .. (item.suffix or "")
    elseif item.type == "choice" then
        text = tostring(value or "")
        for _, o in ipairs(optionsOf(item) or {}) do
            if o.id == value then text = o.label break end
        end
    end
    if item.valueText then text = item.valueText() or text end
    return text or ""
end

function getSettingsCategories()
    ensureSettingsTree()
    local out = {}
    for ci, cat in ipairs(SETTINGS_TREE) do
        local items = {}
        for ii, item in ipairs(cat.items) do
            local value = currentValue(item)
            items[ii] = {
                id = item.id, label = item.label, desc = item.desc, type = item.type,
                min = item.min, max = item.max, step = item.step, suffix = item.suffix,
                options = optionsOf(item), value = value, valueText = valueTextOf(item, value),
                available = isAvailable(item),
            }
        end
        out[ci] = { id = cat.id, label = cat.label, items = items }
    end
    return out
end

function getSettingValue(id)
    local item = findItem(id)
    if not item then return nil end
    return currentValue(item)
end

function setSettingValue(id, value)
    local item = findItem(id)
    if not item or not item.set or not isAvailable(item) then return false end
    if item.type == "toggle" then
        value = value == true
    elseif item.type == "range" then
        value = tonumber(value)
        if not value then return false end
        value = math.max(item.min, math.min(item.max, value))
    elseif item.type == "choice" then
        local ok = false
        for _, o in ipairs(optionsOf(item) or {}) do
            if o.id == value then ok = true break end
        end
        if not ok then return false end
    end
    item.set(value)
    -- persist the change to the player's account (c_settings.lua)
    pauseSettingsPersist(item.id, value)
    triggerEvent("ui_pause:onClientSettingChanged", localPlayer, item.id, value)
    return true
end

-- one step the way the pause menu's arrow keys do: toggle flips, range +- step,
-- choice to the previous / next option. Returns the new value or nil.
function stepSetting(id, dir)
    local item = findItem(id)
    if not item or not isAvailable(item) then return nil end
    dir = (tonumber(dir) or 1) < 0 and -1 or 1
    local cur = currentValue(item)
    local new
    if item.type == "toggle" then
        new = not cur
    elseif item.type == "range" then
        new = math.max(item.min, math.min(item.max, cur + dir * item.step))
        if new == cur then return nil end
    elseif item.type == "choice" then
        local opts = optionsOf(item) or {}
        if #opts == 0 then return nil end
        local idx = 1
        for i, o in ipairs(opts) do
            if o.id == cur then idx = i break end
        end
        idx = (idx - 1 + dir) % #opts + 1
        new = opts[idx].id
        if new == cur then return nil end
    else
        return nil
    end
    if setSettingValue(id, new) then return new end
    return nil
end
