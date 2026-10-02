-- veh_manager :: forced vehicle colors
--
-- vehcolor.json forces colors onto every vehicle of a model, whoever created
-- it: { "<model id>": [ slot1, slot2, slot3, slot4 ], ... }
-- A slot is "#RRGGBB" or [r, g, b]; give only as many slots as needed, and
-- use null to leave a slot untouched. Edit the JSON and restart the resource.
--
-- Enforcement: on resource start, on model change, on enter, and a periodic
-- sweep that also reverts later setVehicleColor calls (paint shops etc.).
-- Creators can call applyForcedColor(vehicle) right after createVehicle to
-- skip the short window before the next sweep.

local COLORS_FILE    = "vehcolor.json"
local SWEEP_INTERVAL = 1000 -- ms

local forced = {} -- [model] = { [slot] = {r, g, b} }

local function parseSlot(v)
    if type(v) == "string" then
        local hex = v:match("^#?(%x%x%x%x%x%x)$")
        if hex then
            return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
        end
    elseif type(v) == "table" then
        local r, g, b = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
        if r and g and b then
            return { math.floor(r) % 256, math.floor(g) % 256, math.floor(b) % 256 }
        end
    end
    return nil
end

local function loadForcedColors()
    forced = {}
    if not fileExists(COLORS_FILE) then
        outputDebugString("[veh_manager] " .. COLORS_FILE .. " not found", 2)
        return
    end
    local f = fileOpen(COLORS_FILE, true)
    if not f then return end
    local raw = fileRead(f, fileGetSize(f))
    fileClose(f)

    local data = fromJSON(raw)
    if type(data) ~= "table" then
        outputDebugString("[veh_manager] " .. COLORS_FILE .. " is not valid JSON", 1)
        return
    end
    local count = 0
    for k, slots in pairs(data) do
        local id = tonumber(k)
        if id and type(slots) == "table" then
            local entry, any = {}, false
            for i = 1, 4 do
                local c = parseSlot(slots[i])
                if c then entry[i] = c; any = true end
            end
            if any then
                forced[id] = entry
                count = count + 1
            else
                outputDebugString("[veh_manager] " .. COLORS_FILE .. ": no valid color for model " .. tostring(k), 2)
            end
        end
    end
    outputDebugString("[veh_manager] loaded forced colors for " .. count .. " model(s)")
end

-- Re-color a vehicle if its model has forced colors and they differ.
-- -> true if the vehicle is (now) in its forced colors, false otherwise
function applyForcedColor(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    local entry = forced[getElementModel(vehicle)]
    if not entry then return false end

    local cur = { getVehicleColor(vehicle, true) }
    local changed = false
    for slot, c in pairs(entry) do
        local base = (slot - 1) * 3
        for j = 1, 3 do
            if cur[base + j] ~= c[j] then
                cur[base + j] = c[j]
                changed = true
            end
        end
    end
    if changed then setVehicleColor(vehicle, unpack(cur, 1, 12)) end
    return true
end

-- Forced colors of a model: { [slot] = {r, g, b} }, or false.
function getForcedColor(model)
    local entry = forced[tonumber(model)]
    if not entry then return false end
    local copy = {}
    for slot, c in pairs(entry) do copy[slot] = { c[1], c[2], c[3] } end
    return copy
end

local function sweep()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        applyForcedColor(veh)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadForcedColors()
    sweep()
    setTimer(sweep, SWEEP_INTERVAL, 0)
end)

addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "vehicle" then applyForcedColor(source) end
end)

addEventHandler("onVehicleEnter", root, function()
    applyForcedColor(source)
end)
