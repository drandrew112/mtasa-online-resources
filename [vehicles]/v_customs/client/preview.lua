-- v_customs :: live preview (client)
--
-- Every option previews on the real vehicle the moment it is highlighted and
-- rolls back when the highlight moves away or the menu closes. A purchase
-- commits the new look as the baseline (the server has already applied it for
-- real / for everyone).
--
-- info shapes from client/menu.lua:
--   { kind = "color",   slot, rgb }
--   { kind = "optical",  slot, upgrade }
--   { kind = "performance"|"handlingProp"|"wheelWidth"|"flagToggle", opt = <option> }

Preview = { veh = nil }

local base   = nil   -- committed baseline
local active = nil   -- { undo = function }

function Preview.init(veh)
    Preview.veh = veh
    base = {
        colors   = { getVehicleColor(veh, true) },
        head     = { getVehicleHeadLightColor(veh) },
        flags    = getVehicleHandling(veh).handlingFlags,
        handling = {},   -- [prop] = committed value (lazy)
        slots    = {},   -- [slot] = committed upgrade id (lazy)
        lsd      = getElementData(veh, "tuning.lsdDoor") and true or false,
    }
    active = nil
end

local function baseHandling(prop)
    if base.handling[prop] == nil then
        base.handling[prop] = getVehicleHandling(Preview.veh)[prop]
    end
    return base.handling[prop]
end

local function setDoors(open)
    local r = open and 1 or 0
    setVehicleDoorOpenRatio(Preview.veh, 2, r, 250)
    setVehicleDoorOpenRatio(Preview.veh, 3, r, 250)
end

-- Applies info, returns an undo function (or nil).
local function apply(info)
    local veh   = Preview.veh
    local k     = info.kind
    local opt   = info.opt
    local orig  = getOriginalHandling(getElementModel(veh))

    if k == "color" then
        if info.slot == "headlight" then
            setVehicleHeadLightColor(veh, info.rgb[1], info.rgb[2], info.rgb[3])
        else
            local c = { getVehicleColor(veh, true) }
            local b = info.slot == "primary" and 0 or 3
            c[b + 1], c[b + 2], c[b + 3] = info.rgb[1], info.rgb[2], info.rgb[3]
            setVehicleColor(veh, unpack(c))
        end
        return function()
            setVehicleColor(veh, unpack(base.colors))
            setVehicleHeadLightColor(veh, base.head[1], base.head[2], base.head[3])
        end

    elseif k == "optical" then
        local slot = info.slot
        if base.slots[slot] == nil then base.slots[slot] = getVehicleUpgradeOnSlot(veh, slot) or 0 end
        local cur = getVehicleUpgradeOnSlot(veh, slot) or 0
        if cur ~= 0 then removeVehicleUpgrade(veh, cur) end
        if (info.upgrade or 0) ~= 0 then addVehicleUpgrade(veh, info.upgrade) end
        return function()
            local c = getVehicleUpgradeOnSlot(veh, slot) or 0
            if c ~= 0 then removeVehicleUpgrade(veh, c) end
            if (base.slots[slot] or 0) ~= 0 then addVehicleUpgrade(veh, base.slots[slot]) end
        end

    elseif k == "performance" then
        for _, p in ipairs(opt.data) do
            baseHandling(p[1])
            local target = p[2] == nil and orig[p[1]] or (orig[p[1]] + p[2])
            setVehicleHandling(veh, p[1], target, false)
        end
        return function()
            for _, p in ipairs(opt.data) do
                setVehicleHandling(veh, p[1], base.handling[p[1]], false)
            end
        end

    elseif k == "handlingProp" then
        baseHandling(opt.prop)
        setVehicleHandling(veh, opt.prop, opt.data == false and orig[opt.prop] or opt.data, false)
        return function() setVehicleHandling(veh, opt.prop, base.handling[opt.prop], false) end

    elseif k == "wheelWidth" then
        Customs.setHandlingFlagByte(veh, opt.side == "front" and 3 or 4, Customs.WHEEL_SIZE[opt.data] or 0)
        return function() setVehicleHandling(veh, "handlingFlags", base.flags, false) end

    elseif k == "flagToggle" and opt.flag == "lsdDoor" then
        setElementData(veh, "tuning.lsdDoor", opt.data and true or nil)
        setDoors(opt.data and true or false)
        return function()
            setElementData(veh, "tuning.lsdDoor", base.lsd and true or nil)
            setDoors(false)
        end
    end

    return nil
end

--------------------------------------------------------------------------------

function Preview.onHover(info)
    if not isElement(Preview.veh) then return end
    if active and active.undo then active.undo() end
    active = nil
    if type(info) ~= "table" then return end
    local undo = apply(info)
    if undo then active = { undo = undo } end
end

function Preview.commit(info)
    if type(info) ~= "table" or not isElement(Preview.veh) then return end
    active = nil
    local veh = Preview.veh
    base.colors = { getVehicleColor(veh, true) }
    base.head   = { getVehicleHeadLightColor(veh) }
    base.flags  = getVehicleHandling(veh).handlingFlags
    base.lsd    = getElementData(veh, "tuning.lsdDoor") and true or false
    for prop in pairs(base.handling) do base.handling[prop] = getVehicleHandling(veh)[prop] end
    for slot in pairs(base.slots) do base.slots[slot] = getVehicleUpgradeOnSlot(veh, slot) or 0 end
end

function Preview.restore()
    if active and active.undo and isElement(Preview.veh) then active.undo() end
    active = nil
    Preview.veh = nil
end
