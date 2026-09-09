-- v_customs :: temp-menu builder + wiring (client)
--
-- shared/tuning.lua is a flat alphabetical list of parts. Each part becomes one
-- root entry that opens a submenu of its options. Items carry `price` and
-- `checked` (the currently fitted option) - ui_inac renders those on the right.

Menu   = Menu or {}
uicore = exports.ui_core

local menuId         = nil
local curVeh         = nil
local previewByPath  = {}   -- path -> Preview.onHover info
local basePriceByPath = {}  -- path -> catalogue price (for un-checking)
local partOfPath     = {}   -- path -> part index
local partPaths      = {}   -- part index -> { option path, ... }
local plateToken     = nil

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")
addEvent("v_customs:notify", true)
addEvent("v_customs:buyResult", true)
addEvent("v_customs:promptPlate", true)

--------------------------------------------------------------------------------
-- "currently fitted option" detection
--------------------------------------------------------------------------------

local function extras()
    local t = getElementData(curVeh, "customs:extras")
    return type(t) == "table" and t or {}
end

local function isFlagSet(val, flag) return bitAnd(val, flag) == flag end

local WHEEL_FLAGS = {
    front = { verynarrow = 0x100,  narrow = 0x200,  wide = 0x400,  verywide = 0x800  },
    rear  = { verynarrow = 0x1000, narrow = 0x2000, wide = 0x4000, verywide = 0x8000 },
}
local OFFROAD_FLAGS = { dirt = 0x100000, sand = 0x200000 }

local function nearly(a, b) return math.abs((a or 0) - (b or 0)) < 0.001 end

-- Returns the option index currently active for a static part, or nil.
local function activeStatic(part)
    local opts = part.options
    local h = getVehicleHandling(curVeh)
    local orig = getOriginalHandling(getElementModel(curVeh))
    local kind = opts[1].kind

    if kind == "performance" then
        for i, opt in ipairs(opts) do
            local ok = true
            for _, prop in ipairs(opt.data) do
                local target = prop[2] == nil and orig[prop[1]] or (orig[prop[1]] + prop[2])
                if not nearly(h[prop[1]], target) then ok = false break end
            end
            if ok then return i end
        end

    elseif kind == "handlingProp" then
        for i, opt in ipairs(opts) do
            if opt.data == false then
                if nearly(h[opt.prop], orig[opt.prop]) or h[opt.prop] == orig[opt.prop] then return i end
            elseif h[opt.prop] == opt.data or nearly(tonumber(h[opt.prop]) or -1, tonumber(opt.data) or -2) then
                return i
            end
        end

    elseif kind == "wheelWidth" then
        local flags = h.handlingFlags
        local side  = opts[1].side
        for i, opt in ipairs(opts) do
            local f = WHEEL_FLAGS[side][opt.data]
            if not f then
                -- "default" = no width flag on that side
                local any = false
                for _, ff in pairs(WHEEL_FLAGS[side]) do if isFlagSet(flags, ff) then any = true end end
                if not any then return i end
            elseif isFlagSet(flags, f) then
                return i
            end
        end

    elseif kind == "offroad" then
        local flags = h.handlingFlags
        for i, opt in ipairs(opts) do
            local f = OFFROAD_FLAGS[opt.data]
            if not f then
                if not isFlagSet(flags, OFFROAD_FLAGS.dirt) and not isFlagSet(flags, OFFROAD_FLAGS.sand) then return i end
            elseif isFlagSet(flags, f) then
                return i
            end
        end

    elseif kind == "nitro" then
        local lvl = tonumber(extras().nitro) or 0
        for i, opt in ipairs(opts) do if opt.data == lvl then return i end end
        return 1

    elseif kind == "airride" then
        local lvl = tonumber(extras().airride) or 0
        for i, opt in ipairs(opts) do if opt.data == lvl then return i end end
        return 1

    elseif kind == "flagToggle" then
        local on
        if opts[1].flag == "bulletproof" then on = extras().bulletproof and true or false
        else on = getElementData(curVeh, "tuning.lsdDoor") and true or false end
        return on and 2 or 1
    end
    return nil
end

--------------------------------------------------------------------------------
-- option lists
--------------------------------------------------------------------------------

local function priceOf(base) return Customs.price(base or 0) end

local function makeOption(path, name, base, checked, preview)
    basePriceByPath[path] = priceOf(base)
    if preview then previewByPath[path] = preview end
    return {
        label   = name,
        value   = path,
        checked = checked or nil,
        price   = checked and false or priceOf(base),
        closeOnSelect = false,
    }
end

local function opticalOptions(part, pIdx)
    local ups = getVehicleCompatibleUpgrades(curVeh, part.slot) or {}
    local cur = getVehicleUpgradeOnSlot(curVeh, part.slot) or 0
    local items, paths = {}, {}

    local defPath = pIdx .. "/1"
    paths[1] = defPath
    items[1] = makeOption(defPath, "Default", 0, cur == 0,
        { kind = "optical", slot = part.slot, upgrade = 0 })

    for k, up in ipairs(ups) do
        local p = pIdx .. "/" .. (k + 1)
        paths[k + 1] = p
        items[k + 1] = makeOption(p, part.name .. " " .. k, part.price, cur == up,
            { kind = "optical", slot = part.slot, upgrade = up })
    end

    if #ups == 0 then
        items = { { label = "(not available for this vehicle)", closeOnSelect = false } }
        paths = {}
    end
    return items, paths
end

local function colorOptions(part, pIdx)
    local items, paths = {}, {}
    for k, entry in ipairs(Customs.PALETTE) do
        local p = pIdx .. "/" .. k
        paths[k] = p
        items[k] = makeOption(p, entry.name, part.price, false,
            { kind = "color", slot = part.slot, rgb = entry.rgb })
    end
    return items, paths
end

local function neonOptions(part, pIdx)
    local curId = extras().neon
    local items, paths = {}, {}

    paths[1] = pIdx .. "/1"
    items[1] = makeOption(paths[1], "Remove", 0, not curId,
        { kind = "neon", id = false })

    for k, entry in ipairs(Customs.NEONS) do
        local p = pIdx .. "/" .. (k + 1)
        paths[k + 1] = p
        items[k + 1] = makeOption(p, entry.name, part.price, curId == entry.id,
            { kind = "neon", id = entry.id })
    end
    return items, paths
end

local function staticOptions(part, pIdx)
    local active = activeStatic(part)
    local items, paths = {}, {}
    for k, opt in ipairs(part.options) do
        local p = pIdx .. "/" .. k
        paths[k] = p
        local preview = nil
        if opt.kind ~= "horn" and opt.kind ~= "plate" then
            preview = { kind = opt.kind, opt = opt }
        end
        items[k] = makeOption(p, opt.name, opt.price, active == k, preview)
    end
    return items, paths
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

function Menu.open(veh)
    curVeh          = veh
    previewByPath   = {}
    basePriceByPath = {}
    partOfPath      = {}
    partPaths       = {}
    Preview.init(veh)

    local items = {}
    for pIdx, part in ipairs(Customs.parts) do
        local opts, paths
        if part.group == "optical" then
            opts, paths = opticalOptions(part, pIdx)
        elseif part.group == "color" then
            opts, paths = colorOptions(part, pIdx)
        elseif part.group == "neon" then
            opts, paths = neonOptions(part, pIdx)
        else
            opts, paths = staticOptions(part, pIdx)
        end

        partPaths[pIdx] = paths
        for _, p in ipairs(paths) do partOfPath[p] = pIdx end

        items[pIdx] = { label = part.name, title = part.name, items = opts }
    end

    menuId = exports.ui_inac:createTempMenu({ title = "SA CUSTOMS", items = items }) or nil
    return menuId ~= nil
end

function Menu.close()
    if menuId and exports.ui_inac:isTempMenuOpen() then
        exports.ui_inac:closeTempMenu()
    end
    menuId = nil
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

addEventHandler("ui_inac:tempMenuHover", root, function(id, value, path)
    if id ~= menuId then return end
    Preview.onHover(previewByPath[path])
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "string" or not isElement(curVeh) then return end
    triggerServerEvent("v_customs:buy", localPlayer, curVeh, value)
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id ~= menuId then return end
    menuId = nil
    if Shop and Shop.onMenuClosed then Shop.onMenuClosed() end
end)

addEventHandler("v_customs:notify", root, function(title, text)
    uicore:addNotification(tostring(title), tostring(text))
end)

addEventHandler("v_customs:buyResult", root, function(ok, path, charged)
    if not ok then return end
    if path and previewByPath[path] then Preview.commit(previewByPath[path]) end
    if tonumber(charged) and tonumber(charged) > 0 then
        uicore:showMoney("take", tonumber(charged))
    end

    -- move the tick onto the bought option within its part
    local pIdx = path and partOfPath[path]
    if pIdx and partPaths[pIdx] then
        for _, p in ipairs(partPaths[pIdx]) do
            exports.ui_inac:updateTempMenuItem(p, {
                checked = (p == path),
                price   = (p == path) and false or basePriceByPath[p],
            })
        end
    end
end)

addEventHandler("v_customs:promptPlate", root, function()
    plateToken = exports.ui_core:openTextInput("Custom license plate", 8)
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= plateToken then return end
    plateToken = nil
    if type(text) == "string" and text ~= "" then
        triggerServerEvent("v_customs:setCustomPlate", localPlayer, text)
    end
end)
