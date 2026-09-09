-- v_customs :: live preview (client)
--
-- Every option previews on the real vehicle the moment it is highlighted and
-- rolls back when the highlight moves away or the menu closes. A purchase
-- commits the new look as the baseline (the server has already applied it for
-- real / for everyone).
--
-- info shapes from client/menu.lua:
--   { kind = "color",    slot, rgb }
--   { kind = "optical",  slot, upgrade }
--   { kind = "neon",     id | false }
--   { kind = "performance"|"handlingProp"|"wheelWidth"|"offroad"|"nitro"|
--            "airride"|"flagToggle", opt = <catalogue option> }

Preview = { veh = nil }

local base   = nil   -- committed baseline
local active = nil   -- { undo = function }

local function ex()
    local t = getElementData(Preview.veh, "customs:extras")
    return type(t) == "table" and t or {}
end

--------------------------------------------------------------------------------

function Preview.init(veh)
    Preview.veh = veh
    base = {
        colors   = { getVehicleColor(veh, true) },
        head     = { getVehicleHeadLightColor(veh) },
        flags    = getVehicleHandling(veh).handlingFlags,
        handling = {},   -- [prop] = committed value (lazy)
        slots    = {},   -- [slot] = committed upgrade id (lazy)
        nitroUp  = getVehicleUpgradeOnSlot(veh, 8) == 1010,
        neon     = ex().neon or false,
        lsd      = getElementData(veh, "tuning.lsdDoor") and true or false,
    }
    active = nil
end

--------------------------------------------------------------------------------

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

-- Applies info, returns an undo function (or nil = nothing to preview).
local function apply(info)
    local veh   = Preview.veh
    local k     = info.kind
    local opt   = info.opt
    local model = getElementModel(veh)
    local orig  = getOriginalHandling(model)

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

    elseif k == "neon" then
        if NeonFX then
            if info.id then NeonFX.add(veh, info.id) else NeonFX.remove(veh) end
        end
        return function()
            if not NeonFX then return end
            if base.neon then NeonFX.add(veh, base.neon) else NeonFX.remove(veh) end
        end

    elseif k == "performance" then
        for _, p in ipairs(opt.data) do
            local b = baseHandling(p[1])
            local target = p[2] == nil and orig[p[1]] or (orig[p[1]] + p[2])
            setVehicleHandling(veh, p[1], target, false)
        end
        return function()
            for _, p in ipairs(opt.data) do
                setVehicleHandling(veh, p[1], base.handling[p[1]], false)
            end
        end

    elseif k == "handlingProp" then
        local b = baseHandling(opt.prop)
        local target = opt.data == false and orig[opt.prop] or opt.data
        setVehicleHandling(veh, opt.prop, target, false)
        return function() setVehicleHandling(veh, opt.prop, base.handling[opt.prop], false) end

    elseif k == "airride" then
        baseHandling("suspensionLowerLimit")
        local lvl = tonumber(opt.data) or 0
        setVehicleHandling(veh, "suspensionLowerLimit",
            lvl <= 0 and orig.suspensionLowerLimit or (Customs.AIRRIDE_DROP[lvl] or -0.2), false)
        return function()
            setVehicleHandling(veh, "suspensionLowerLimit", base.handling.suspensionLowerLimit, false)
        end

    elseif k == "wheelWidth" then
        Customs.setHandlingFlagByte(veh, opt.side == "front" and 3 or 4, Customs.WHEEL_SIZE[opt.data] or 0)
        return function() setVehicleHandling(veh, "handlingFlags", base.flags, false) end

    elseif k == "offroad" then
        Customs.setHandlingFlagByte(veh, 6, Customs.OFFROAD[opt.data] or 0)
        return function() setVehicleHandling(veh, "handlingFlags", base.flags, false) end

    elseif k == "nitro" then
        local lvl = tonumber(opt.data) or 0
        if lvl > 0 then addVehicleUpgrade(veh, 1010) else removeVehicleUpgrade(veh, 1010) end
        return function()
            if base.nitroUp then addVehicleUpgrade(veh, 1010) else removeVehicleUpgrade(veh, 1010) end
        end

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

-- The option was purchased: bank the current look as the new baseline.
function Preview.commit(info)
    if type(info) ~= "table" or not isElement(Preview.veh) then return end
    active = nil
    local veh = Preview.veh
    base.colors  = { getVehicleColor(veh, true) }
    base.head    = { getVehicleHeadLightColor(veh) }
    base.flags   = getVehicleHandling(veh).handlingFlags
    base.nitroUp = getVehicleUpgradeOnSlot(veh, 8) == 1010
    base.neon    = ex().neon or false
    base.lsd     = getElementData(veh, "tuning.lsdDoor") and true or false
    for prop in pairs(base.handling) do base.handling[prop] = getVehicleHandling(veh)[prop] end
    for slot in pairs(base.slots) do base.slots[slot] = getVehicleUpgradeOnSlot(veh, slot) or 0 end
end

function Preview.restore()
    if active and active.undo and isElement(Preview.veh) then active.undo() end
    active = nil
    Preview.veh = nil
end
