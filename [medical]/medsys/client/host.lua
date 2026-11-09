-- Host mode: hospital staff (medsys role kind "hospital") never get the medsys examination panel. The
-- hospital patient panel (med_hospitals er/client) drives medsys through the client exports below:
--   hostWatch(target, on)        the bedside panel is open on this patient (server: Examining in host mode)
--   setHostAnchor(lx, ty)        left / top edge of the device windows (Lifepak, glucometer under it): the
--                                right side of the hospital panel; false = the panel is hidden (nothing drawn)
--   hostAction(action, option)   a procedure (medic:requestTreatment), "defib" / "glucometer" toggle the
--                                device windows
--   isHostWindowAt(x, y)         a click there belongs to a device window or the 12-lead viewer (the
--                                hospital panel ignores it, no hover either)
-- The hospital panel gets the state of its action bar as the client event onClientMedicHostState
-- (localPlayer; model or false) and the result lines as onClientMedicHostMessage (text, isError).

addEvent("medic:hostOpen", true)
addEvent("medic:hostUpdate", true)
addEvent("medic:hostClose", true)
addEvent("medic:hostMessage", true)
addEvent("onClientMedicHostState", false)   -- source: localPlayer, (model | false)
addEvent("onClientMedicHostMessage", false) -- source: localPlayer, (text, isError)
addEvent("onClientMedicHostBusy", false)    -- source: localPlayer, (busy): a procedure runs

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)
local function s(value) return value * scale end

local host       -- { target, data, dataTick, lifepak, glucometer, pending }
local anchor     -- { rx, by } or nil
local requested  -- { target, tick } last hostWatch request
local kept       -- { target, lifepak, glucometer, tick }: the device windows over a procedure (it closes the host)
local rendering = false

-- the bar of the hospital panel: the medsys ABCD rows without transport + the monitor / defibrillator
local BAR_GROUPS = {
    { tag = "AB", actions = { "airway", "oxygen" } },
    { tag = "C", actions = { "bandage", "splint", "cpr", "iv", "medication" } },
    { tag = "D", actions = { "glucometer" } },   -- neuro: the hospital panel has its own neurology exam
    { tag = "MON", actions = { "monitor", "defib" } },
}

local function isInside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

---------------------------------------------------------------- bar model

local function text(v) return type(v) == "table" and L.resolve(v) or tostring(v or "") end

local function infusionState(data, b)
    local infusion = data.infusion
    local denied = medicDeniedReason("action.infusion")
    if denied then return denied end
    if b.kind == "rate" then
        if not infusion then return L("medsys.panel.hang_bag_first") end
        local rate = medicInfusionRate(b.rate)
        if rate and rate.perm and medicDeniedReason(rate.perm) then return medicDeniedReason(rate.perm) end
        if infusion.rate == b.rate then return L("medsys.panel.rate_already_set") end
    elseif b.kind == "stop" then
        if not infusion then return L("medsys.panel.no_bag_hanging") end
    else
        local left = data.equipment and data.equipment.stock and data.equipment.stock.fluids
        if left ~= nil and left <= 0 then return L("medsys.panel.no_infusion_bags_left") end
    end
    return true
end

local function buildModel()
    if not host or not host.data then return false end
    local data = host.data
    local groups = {}
    for _, g in ipairs(BAR_GROUPS) do
        local group = { tag = g.tag, buttons = {} }
        for _, id in ipairs(g.actions) do
            local action = (id == "iv" and data.ivAccess) and "infusion" or id
            local b = { id = id, action = action }
            if id == "defib" then
                b.label = L("medsys.host.defibrillator")
                b.ok = data.monitor ~= nil or L("medsys.host.attach_monitor_first")
                b.active = host.lifepak == true
            elseif id == "monitor" then
                b.label = data.monitor and L("medsys.host.monitor_on") or L("medsys.host.attach_monitor")
                b.active = data.monitor ~= nil
                local avail = data.actions and data.actions.monitor
                if avail == true then avail = medicDeniedReason("action.monitor") or true end
                b.ok = avail == true or (type(avail) == "string" and avail) or false
                if data.monitor then b.ok = L("medsys.treatment.monitor_attached") end
            else
                local info = MEDIC_ACTIONS[action]
                local avail = data.actions and data.actions[action]
                if avail == true then avail = medicDeniedReason("action." .. action) or true end
                b.ok = avail == true or (type(avail) == "string" and avail) or false
                b.active = (id == "oxygen" and data.oxygenMask) or (id == "neuro" and data.neuroChecked)
                    or (id == "glucometer" and host.glucometer) or false
                b.label = info and ((info.activeLabel and b.active and info.activeLabel) or info.label) or id
                if type(b.label) == "table" then b.label = L.resolve(b.label) end
                local stock = data.equipment and data.equipment.stock
                if stock and action == "iv" and stock.ivKits then b.label = ("%s (%d)"):format(b.label, stock.ivKits) end
                b.menu = action == "infusion"
            end
            if host.pending and b.ok == true and id ~= "defib" and id ~= "glucometer" then b.ok = L("medsys.host.wait") end
            group.buttons[#group.buttons + 1] = b
        end
        groups[#groups + 1] = group
    end
    -- the infusion menu (after the cannula): the bag, the rates, hang / replace / remove
    local infusion
    if data.ivAccess then
        local fluid = MEDIC_FLUIDS[MEDIC_DEFAULT_FLUID]
        local bag = data.infusion
        local elapsed = (getTickCount() - host.dataTick) / 1000
        infusion = {
            bag = bag and { name = bag.name, total = bag.total, left = math.max(0, math.ceil(bag.left - (bag.mlps or 0) * elapsed)),
                            rate = bag.rate, mlps = bag.mlps } or false,
            options = {},
        }
        local hang = { kind = "hang", option = "hang",
            label = L(bag and "medsys.panel.replace_bag" or "medsys.panel.hang_bag", { volume = fluid.volume, name = fluid.name }) }
        hang.ok = infusionState(data, hang)
        infusion.options[1] = hang
        for _, rate in ipairs(MEDIC_INFUSION_RATES) do
            local o = { kind = "rate", rate = rate.id, option = "rate:" .. rate.id, label = text(rate.label),
                        note = text(rate.note), high = rate.perm ~= nil, active = bag and bag.rate == rate.id or false }
            o.ok = infusionState(data, o)
            infusion.options[#infusion.options + 1] = o
        end
        local stop = { kind = "stop", option = "stop", label = L("medsys.panel.remove_bag") }
        stop.ok = infusionState(data, stop)
        infusion.options[#infusion.options + 1] = stop
    end
    return { target = host.target, dead = data.dead == true, groups = groups, infusion = infusion or false,
             monitor = data.monitor ~= nil, pending = host.pending == true }
end

local function pushModel()
    triggerEvent("onClientMedicHostState", localPlayer, buildModel())
end

---------------------------------------------------------------- device windows

-- Lifepak: right of the hospital panel, top aligned with it (kept on the screen); the glucometer under it
-- (or in its place). The medsys window functions take the rectangle of the panel they sit next to: the
-- Lifepak goes left of "panelX", the glucometer right of "panelX + panelW".
-- -> the Lifepak's panelX, y, its left edge and height
local function lifepakPlace()
    local r = getLifepakRect(screenW, 0)
    local lw, lh = r[3], r[4]
    local gap = screenW - lw - r[1]
    local lx = math.max(s(4), math.min(anchor[1], screenW - lw - s(4)))
    local ly = math.max(s(4), math.min(anchor[2], screenH - lh - s(4)))
    return lx + lw + gap, ly, lx, lh
end

-- -> glucometer panelX, panelY, panelW
local function glucometerPlace()
    local probe = getGlucometerRect(0, 0, 0)
    local gw, gh, gap = probe[3], probe[4], probe[1]
    local gx = math.max(s(4), math.min(anchor[1], screenW - gw - s(4)))
    local gy = anchor[2]
    if host.lifepak and host.data.monitor then
        local _, ly, _, lh = lifepakPlace()
        gy = ly + lh + s(10)
    end
    gy = math.max(s(4), math.min(gy, screenH - gh - s(4)))
    return gx - gap, gy, 0
end

local function render()
    if not host or not anchor or not isElement(host.target) then return end
    local data = host.data
    local rx, ry = getCursorPosition()
    local cx, cy = (rx or -1) * screenW, (ry or -1) * screenH
    ecgSetInput(data.rhythm, data.ecgRate, data.spo2)
    local showLifepak = host.lifepak and data.monitor
    ecgSetBeep(showLifepak and data.monitor.sound ~= false or false)
    ecgUpdate()
    if showLifepak then
        local px, py = lifepakPlace()
        drawLifepak(px, py, data, getTickCount() - host.dataTick, cx, cy, host.pending)
    end
    if host.glucometer and not data.dead then
        local gx, gy, gw = glucometerPlace()
        drawGlucometer(gx, gy, gw, cx, cy, false)
    end
end

local function setRendering(on)
    if on == rendering then return end
    rendering = on
    if on then
        addEventHandler("onClientRender", root, render, true, "low-5") -- over the hospital panel
    else
        removeEventHandler("onClientRender", root, render)
        stopLifepakSounds()
        ecgSetBeep(false)
    end
end

local function refreshRendering()
    setRendering(host ~= nil and anchor ~= nil and (host.lifepak or host.glucometer) and true or false)
    if host and not host.lifepak then stopLifepakSounds() end
end

function isHostWindowAt(cx, cy)
    if ECG12 and ECG12.isOpen() then return true end -- the 12-lead viewer covers everything
    if not host or not anchor or not rendering then return false end
    if host.lifepak and host.data.monitor then
        local px, py = lifepakPlace()
        local r = getLifepakRect(px, py)
        if isInside(r[1], r[2], r[3], r[4], cx, cy) then return true end
    end
    if host.glucometer then
        local gx, gy, gw = glucometerPlace()
        local r = getGlucometerRect(gx, gy, gw)
        if isInside(r[1], r[2], r[3], r[4], cx, cy) then return true end
    end
    return false
end

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if button ~= "left" or state ~= "down" or not host or not anchor or not rendering then return end
    if ECG12 and ECG12.isOpen() then return end -- the click is the 12-lead viewer's
    local data = host.data
    if host.lifepak and data.monitor then
        local px, py = lifepakPlace()
        if clickLifepak(px, py, host.target, data, getTickCount() - host.dataTick, ax, ay, host.pending) then return end
    end
    if host.glucometer then
        local gx, gy, gw = glucometerPlace()
        local hit = clickGlucometer(gx, gy, gw, host.target, ax, ay, false)
        if hit == "close" then
            host.glucometer = false
            refreshRendering()
            pushModel()
        end
    end
end)

---------------------------------------------------------------- exports for the hospital panel

function hostWatch(target, on)
    if on then
        if not isElement(target) then return false end
        if host and host.target == target then return true end
        if requested and requested.target == target and getTickCount() - requested.tick < 2000 then return true end
        requested = { target = target, tick = getTickCount() }
        triggerServerEvent("medic:requestExamine", resourceRoot, target)
        return true
    end
    requested = nil
    if host then
        host = nil
        triggerServerEvent("medic:closeExamine", resourceRoot)
        refreshRendering()
        pushModel()
    end
    return true
end

function setHostAnchor(lx, ty)
    if lx and ty then
        if not anchor or anchor[1] ~= lx or anchor[2] ~= ty then anchor = { lx, ty } end
    else
        anchor = nil
    end
    refreshRendering()
    return true
end

function hostAction(action, option, dose)
    if not host or not host.data then return false end
    if action == "defib" then
        host.lifepak = not host.lifepak and host.data.monitor ~= nil
    elseif action == "glucometer" then
        host.glucometer = not host.glucometer
        resetGlucometer(host.target)
    else
        if host.pending then return false end
        host.pending = true
        triggerServerEvent("medic:requestTreatment", resourceRoot, host.target, action, option, dose)
    end
    refreshRendering()
    pushModel()
    return true
end

function getHostState()
    return buildModel()
end

---------------------------------------------------------------- server events

addEventHandler("medic:hostOpen", resourceRoot, function(target, name, data, message, isError)
    local prev = host and host.target == target and host
        or (kept and kept.target == target and getTickCount() - kept.tick < 60000 and kept) or nil
    kept = nil
    if not (host and host.target == target) then ecgReset() end
    host = {
        target = target, data = data, dataTick = getTickCount(),
        lifepak = prev and prev.lifepak or false, glucometer = prev and prev.glucometer or false,
    }
    requested = nil
    if message then triggerEvent("onClientMedicHostMessage", localPlayer, message, isError == true) end
    refreshRendering()
    pushModel()
end)

addEventHandler("medic:hostUpdate", resourceRoot, function(target, data)
    if not host or host.target ~= target then return end
    host.data, host.dataTick = data, getTickCount()
    if not data.monitor then host.lifepak = false end
    refreshRendering()
    pushModel()
end)

addEventHandler("medic:hostClose", resourceRoot, function()
    -- a procedure closes it too (the server reopens it at the end); the device windows are kept then
    kept = host and { target = host.target, lifepak = host.lifepak, glucometer = host.glucometer, tick = getTickCount() } or nil
    host = nil
    requested = nil
    refreshRendering()
    pushModel()
end)

-- a procedure starts / ends (medsys server): the hospital panel steps aside meanwhile
addEventHandler("medic:busy", resourceRoot, function(state)
    triggerEvent("onClientMedicHostBusy", localPlayer, state == true)
end)

addEventHandler("medic:hostMessage", resourceRoot, function(message, isError)
    if host then host.pending = false end
    triggerEvent("onClientMedicHostMessage", localPlayer, message, isError == true)
    pushModel()
end)
