if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_customs :: temp-menu builder + wiring (client)
--
-- shared/tuning.lua is an alphabetical list of parts / folders. Folders nest one
-- level; every part opens a submenu of its options. Items carry `price` and
-- `checked` (the currently fitted option) which ui_inac renders on the right.

Menu   = Menu or {}
uicore = exports.ui_core

local menuId          = nil
local menuMode        = nil  -- "main" | "repair" (damaged car) | "confirm" (exit prompt)
local curVeh          = nil
local previewByPath   = {}   -- option path -> Preview.onHover info
local basePriceByPath = {}   -- option path -> catalogue price
local partOfPath      = {}   -- option path -> owning part's path prefix
local partPaths       = {}   -- part path prefix -> { option path, ... }
local uiPrefixOf      = {}   -- part path prefix -> its positional ui_inac path (differs once parts are hidden)
local plateToken      = nil

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")
addEvent("v_customs:notify", true)
addEvent("v_customs:buyResult", true)
addEvent("v_customs:repairResult", true)
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

local function nearly(a, b) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.001 end

-- option index currently active for a static part, or nil
local function activeStatic(part)
    local opts = part.options
    local h    = getVehicleHandling(curVeh)
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
                if h[opt.prop] == orig[opt.prop] or nearly(h[opt.prop], orig[opt.prop]) then return i end
            elseif type(opt.data) == "number" then
                if nearly(h[opt.prop], opt.data) then return i end
            elseif h[opt.prop] == opt.data then
                return i
            end
        end

    elseif kind == "wheelWidth" then
        local flags, side = h.handlingFlags, opts[1].side
        for i, opt in ipairs(opts) do
            local f = WHEEL_FLAGS[side][opt.data]
            if not f then
                local any = false
                for _, ff in pairs(WHEEL_FLAGS[side]) do if isFlagSet(flags, ff) then any = true end end
                if not any then return i end
            elseif isFlagSet(flags, f) then
                return i
            end
        end

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

local function opticalOptions(part, prefix)
    local ups = getVehicleCompatibleUpgrades(curVeh, part.slot) or {}
    local cur = getVehicleUpgradeOnSlot(curVeh, part.slot) or 0
    local items, paths = {}, {}

    paths[1] = prefix .. "/1"
    items[1] = makeOption(paths[1], L("v_customs.menu.default"), 0, cur == 0,
        { kind = "optical", slot = part.slot, upgrade = 0 })

    for k, up in ipairs(ups) do
        local p = prefix .. "/" .. (k + 1)
        paths[k + 1] = p
        items[k + 1] = makeOption(p, part.name .. " " .. k, part.price, cur == up,
            { kind = "optical", slot = part.slot, upgrade = up })
    end
    return items, paths
end

local function colorOptions(part, prefix)
    local items, paths = {}, {}
    for k, entry in ipairs(Customs.PALETTE) do
        local p = prefix .. "/" .. k
        paths[k] = p
        items[k] = makeOption(p, entry.name, part.price, false,
            { kind = "color", slot = part.slot, rgb = entry.rgb })
    end
    return items, paths
end

local function staticOptions(part, prefix)
    local active = activeStatic(part)
    local items, paths = {}, {}
    for k, opt in ipairs(part.options) do
        local p = prefix .. "/" .. k
        paths[k] = p
        local preview = (opt.kind ~= "horn" and opt.kind ~= "plate") and { kind = opt.kind, opt = opt } or nil
        items[k] = makeOption(p, opt.name, opt.price, active == k, preview)
    end
    return items, paths
end

--------------------------------------------------------------------------------
-- tree build
--------------------------------------------------------------------------------

local function buildPart(part, prefix, uiPrefix)
    local opts, paths
    if part.group == "optical" then
        opts, paths = opticalOptions(part, prefix)
    elseif part.group == "color" then
        opts, paths = colorOptions(part, prefix)
    else
        opts, paths = staticOptions(part, prefix)
    end

    partPaths[prefix]  = paths
    uiPrefixOf[prefix] = uiPrefix
    for _, p in ipairs(paths) do partOfPath[p] = prefix end

    return { label = part.name, title = part.name, items = opts }
end

-- Parts the vehicle can't use are left out (and folders left empty by that);
-- paths keep the catalogue indices so the server resolves them unchanged.
local function buildLevel(nodes, prefix, uiPrefix)
    local items = {}
    for i, node in ipairs(nodes) do
        local p  = prefix == "" and tostring(i) or (prefix .. "/" .. i)
        local n  = #items + 1
        local up = uiPrefix == "" and tostring(n) or (uiPrefix .. "/" .. n)
        if node.folder then
            local sub = buildLevel(node.items, p, up)
            if #sub > 0 then
                items[n] = { label = node.name, title = node.name, items = sub }
            end
        elseif Customs.isPartAvailable(curVeh, node) then
            items[n] = buildPart(node, p, up)
        end
    end
    return items
end

--------------------------------------------------------------------------------

local function openMain()
    previewByPath   = {}
    basePriceByPath = {}
    partOfPath      = {}
    partPaths       = {}
    uiPrefixOf      = {}
    Preview.init(curVeh)

    menuMode = "main"
    menuId = exports.ui_inac:createTempMenu({
        title = L("v_customs.menu.sa_customs"),
        items = buildLevel(Customs.parts, "", ""),
    }) or nil
    return menuId ~= nil
end

-- Damaged car: only Repair / Exit until it is fixed.
local function openRepair()
    menuMode = "repair"
    menuId = exports.ui_inac:createTempMenu({
        title = L("v_customs.menu.sa_customs"),
        items = {
            { label = L("v_customs.menu.repair_vehicle"), value = "repair",
              price = Customs.repairPrice(curVeh), closeOnSelect = false },
            { label = L("v_customs.menu.exit"), value = "exit", closeOnSelect = false },
        },
    }) or nil
    return menuId ~= nil
end

-- Backspace at the main menu's root: Back / Exit. Closing this one = Back.
local function openConfirm()
    menuMode = "confirm"
    menuId = exports.ui_inac:createTempMenu({
        title = L("v_customs.menu.sa_customs"),
        items = {
            { label = L("common.back"),         value = "back", closeOnSelect = false },
            { label = L("v_customs.menu.exit"), value = "exit", closeOnSelect = false },
        },
    }) or nil
    return menuId ~= nil
end

-- Leave the workshop (drive-out). menuId is cleared first so the close event
-- of our own closeTempMenu is ignored.
local function leave()
    menuId, menuMode = nil, nil
    exports.ui_inac:closeTempMenu()
    if Shop and Shop.onMenuClosed then Shop.onMenuClosed() end
end

function Menu.open(veh)
    curVeh = veh
    if Customs.repairPrice(veh) > 0 then return openRepair() end
    return openMain()
end

function Menu.close()
    local open = menuId
    menuId, menuMode = nil, nil
    if open and exports.ui_inac:isTempMenuOpen() then
        exports.ui_inac:closeTempMenu()
    end
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

addEventHandler("ui_inac:tempMenuHover", root, function(id, value)
    if id ~= menuId or menuMode ~= "main" then return end
    Preview.onHover(value and previewByPath[value])
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "string" or not isElement(curVeh) then return end

    if menuMode == "repair" then
        if value == "repair" then
            triggerServerEvent("v_customs:repair", localPlayer)
        elseif value == "exit" then
            leave()
        end
    elseif menuMode == "confirm" then
        if value == "back" then
            if not openMain() then leave() end
        elseif value == "exit" then
            leave()
        end
    else
        triggerServerEvent("v_customs:buy", localPlayer, curVeh, value)
    end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id ~= menuId then return end
    local mode = menuMode
    menuId, menuMode = nil, nil

    if mode == "main" then
        Preview.restore()
        if openConfirm() then return end
    elseif mode == "confirm" then
        if openMain() then return end
    end
    if Shop and Shop.onMenuClosed then Shop.onMenuClosed() end
end)

addEventHandler("v_customs:repairResult", root, function(ok, charged)
    if not ok or menuMode ~= "repair" then return end
    if tonumber(charged) and tonumber(charged) > 0 then
        uicore:showMoney("take", tonumber(charged), "cash")
    end
    if not openMain() then leave() end
end)

addEventHandler("v_customs:notify", root, function(title, text)
    uicore:addNotification(tostring(title), tostring(text))
end)

addEventHandler("v_customs:buyResult", root, function(ok, path, charged)
    if not ok then return end
    if path and previewByPath[path] then Preview.commit(previewByPath[path]) end
    if tonumber(charged) and tonumber(charged) > 0 then
        uicore:showMoney("take", tonumber(charged), "cash")
    end

    local node    = path and Customs.resolve(path)
    local oneShot = node and (node.kind == "plate" or node.kind == "horn")
    local prefix  = (path and not oneShot) and partOfPath[path]
    if prefix and partPaths[prefix] then
        local uiPrefix = uiPrefixOf[prefix]
        for _, p in ipairs(partPaths[prefix]) do
            exports.ui_inac:updateTempMenuItem(uiPrefix .. p:sub(#prefix + 1), {
                checked = (p == path),
                price   = (p == path) and false or basePriceByPath[p],
            })
        end
    end
end)

addEventHandler("v_customs:promptPlate", root, function()
    plateToken = exports.ui_core:openTextInput(L("v_customs.menu.custom_license_plate"), 8)
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= plateToken then return end
    plateToken = nil
    if type(text) == "string" and text ~= "" then
        triggerServerEvent("v_customs:setCustomPlate", localPlayer, text)
    end
end)
