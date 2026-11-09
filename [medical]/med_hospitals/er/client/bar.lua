-- Intervention bar of the hospital patient panel (bottom of exam.lua, every tab, bedside only).
-- Hospital staff never get the medsys examination panel: medsys runs in host mode for them
-- (medsys client/host.lua) and this bar is its front. The model (buttons, availability, infusion
-- menu) comes from medsys as onClientMedicHostState; the result lines as onClientMedicHostMessage.
-- A procedure (medsys minigame / timed step) hides the panel; it comes back when it ends.

BAR = { model = false, infusionOpen = false, resume = nil }

local s = HGfx.s
local T = HTheme
local function t(key, p) return L("med_hospitals.bar." .. key, p) end

local function medsysRunning()
    local res = getResourceFromName("medsys")
    return res and getResourceState(res) == "running"
end

local function notify(text, alert)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("med_hospitals.er.title"), tostring(text), alert == true)
    end
end

---------------------------------------------------------------- medsys host link

-- the ER ped of the open case (the case data carries it: er/server/his.lua detail)
local function casePed()
    local c = EXAM.case
    return c and isElement(c.ped) and c.ped or nil
end

local function wanted()
    if not EXAM.open or not EXAM.bedside or not EXAM.case or EXAM.case.dead then return nil end
    return casePed()
end

local watching -- the ped medsys host mode was asked for
local function sync()
    if not medsysRunning() then watching = nil return end
    if BAR.resume then return end -- a procedure runs, the panel comes back on its own
    local ped = wanted()
    if ped then
        watching = ped
        exports.medsys:hostWatch(ped, true) -- repeats are cheap (medsys throttles, no-op while open)
    elseif watching then
        watching = nil
        BAR.infusionOpen = false
        exports.medsys:hostWatch(nil, false)
        exports.medsys:setHostAnchor(false)
    end
end
setTimer(sync, 500, 0)

addEvent("onClientMedicHostState", false)
addEventHandler("onClientMedicHostState", localPlayer, function(model)
    BAR.model = model or false
    if not (model and model.infusion) then BAR.infusionOpen = false end
end)

addEvent("onClientMedicHostMessage", false)
addEventHandler("onClientMedicHostMessage", localPlayer, function(text, isError)
    if text and text ~= "" then notify(text, isError) end
end)

-- a procedure runs: the panel steps aside, then comes back on the same patient
addEvent("onClientMedicHostBusy", false)
addEventHandler("onClientMedicHostBusy", localPlayer, function(busy)
    if busy then
        if EXAM.open and EXAM.bedside and EXAM.caseId then
            BAR.resume = EXAM.caseId
            EXAM.close()
        end
    elseif BAR.resume then
        local id = BAR.resume
        setTimer(function()
            BAR.resume = nil
            if not EXAM.open and not (HIS and HIS.open) then EXAM.show(id, true, "bedside") end
        end, 250, 1)
    end
end)

-- a click on a medsys device window (Lifepak, glucometer) is not the panel's
-- (the 12-lead ECG viewer of the Lifepak too: it covers the whole screen)
function BAR.blocksClick(cx, cy)
    return EXAM.bedside and medsysRunning() and exports.medsys:isHostWindowAt(cx, cy) == true or false
end

-- a device window (Lifepak with the monitor on, glucometer) is out next to the bedside panel
function BAR.devicesShown()
    local model = BAR.model
    if not EXAM.bedside or not model or model.dead or model.target ~= (EXAM.case and EXAM.case.ped) then return false end
    for _, g in ipairs(model.groups or {}) do
        for _, b in ipairs(g.buttons) do
            if (b.id == "defib" and b.active and model.monitor) or (b.id == "glucometer" and b.active) then return true end
        end
    end
    return false
end

-- the cursor is over a device window / the 12-lead viewer: no hover, no tooltip on the panel under it
function BAR.cursorBlocked()
    if not EXAM.bedside or not isCursorShowing() then return false end
    local cx, cy = HGfx.cursor()
    return BAR.blocksClick(cx, cy)
end

---------------------------------------------------------------- drawing

BAR.HEIGHT = 58

local GROUP_TAGS = { AB = "AB", C = "C", D = "D", MON = "MON" }

local function press(b)
    if b.id == "medication" then
        -- the medicines are on the Drugs tab (orders, doses, the hospital stock)
        EXAM.tab = "drugs"
        return
    end
    if b.menu then
        BAR.infusionOpen = not BAR.infusionOpen
        return
    end
    BAR.infusionOpen = false
    exports.medsys:hostAction(b.id == "defib" and "defib" or b.action)
end

-- lx, ty: left / top edge of the device windows (right of the panel)
local lastAnchor
local function setAnchor(lx, ty)
    local key = lx and (math.floor(lx) .. ":" .. math.floor(ty)) or "off"
    if key == lastAnchor then return end
    lastAnchor = key
    if medsysRunning() then exports.medsys:setHostAnchor(lx or false, ty or false) end
end

-- The infusion menu above the bar: the bag, the drip rates, hang / remove
local function drawInfusion(inf, x, y, w)
    local h = s(84)
    local by = y - h - s(6)
    HGfx.round(x, by, w, h, s(6), T.panel)
    local bag = inf.bag
    local head = bag and t("bag", { name = bag.name or "", left = bag.left or 0, total = bag.total or 0 }) or t("no_bag")
    HGfx.text(head, x + s(10), by + s(4), w - s(20), s(22), bag and T.text or T.faint, HGfx.font(9, true))
    local n = #inf.options
    local bw = (w - s(20) - s(6) * (n - 1)) / n
    for i, o in ipairs(inf.options) do
        local bx = x + s(10) + (i - 1) * (bw + s(6))
        local ok = o.ok == true and not BAR.model.pending
        local color = o.active and { 47, 134, 232 } or (o.high and { 120, 80, 30 } or { 38, 46, 56 })
        local label = o.note and (o.label .. " · " .. o.note) or o.label
        HGfx.button(bx, by + s(30), bw, s(44), HGfx.fit(label, bw - s(10), HGfx.font(8, true)), { color = color, disabled = not ok and not o.active, font = HGfx.font(8, true) },
            ok and function()
                BAR.infusionOpen = false
                exports.medsys:hostAction("infusion", o.option)
            end or nil)
        if type(o.ok) == "string" and not o.active then HIS.tooltip(bx, by + s(30), bw, s(44), o.ok) end
    end
end

-- x, y, w: the strip at the bottom of the panel (BAR.HEIGHT tall, scaled);
-- ax, ay: where the device windows (Lifepak, glucometer) go: right of the panel, top aligned
function BAR.draw(x, y, w, ax, ay)
    local h = s(BAR.HEIGHT)
    HGfx.round(x, y, w, h, s(6), T.panel)
    local model = BAR.model
    if not EXAM.bedside then
        setAnchor(false)
        HGfx.text(t("bedside_only"), x, y, w, h, T.faint, HGfx.font(9), "center")
        return
    end
    if not medsysRunning() or not model or model.target ~= casePed() then
        setAnchor(false)
        HGfx.text(t("connecting"), x, y, w, h, T.faint, HGfx.font(9), "center")
        return
    end
    if model.dead then
        setAnchor(false)
        HGfx.text(t("patient_dead"), x, y, w, h, T.faint, HGfx.font(9), "center")
        return
    end
    -- the device windows sit right of the panel
    setAnchor(ax or (x + w + s(20)), ay or y)

    -- button widths: groups side by side, a tag column each
    local count, groups = 0, model.groups or {}
    for _, g in ipairs(groups) do count = count + #g.buttons end
    local tagW, gap, groupGap = s(34), s(5), s(12)
    local inner = w - s(16) - #groups * tagW - (#groups - 1) * groupGap
    local bw = (inner - (count - #groups) * gap) / math.max(1, count)
    local bx, bh = x + s(8), h - s(16)
    for gi, g in ipairs(groups) do
        HGfx.text(GROUP_TAGS[g.tag] or g.tag, bx, y, tagW, h, T.faint, HGfx.font(g.tag == "MON" and 7 or 10, true), "center")
        bx = bx + tagW
        for _, b in ipairs(g.buttons) do
            local ok = b.ok == true
            local color = b.active and { 47, 134, 232 } or { 38, 46, 56 }
            if b.menu and BAR.infusionOpen then color = { 60, 74, 90 } end
            local label = b.label or b.id
            if b.menu then label = label .. " ▾" end
            HGfx.button(bx, y + s(8), bw, bh, HGfx.fit(label, bw - s(8), HGfx.font(8, true)),
                { color = color, disabled = not ok, font = HGfx.font(8, true) }, function() press(b) end)
            if not ok and type(b.ok) == "string" then HIS.tooltip(bx, y + s(8), bw, bh, b.ok) end
            bx = bx + bw + gap
        end
        bx = bx - gap + (gi < #groups and groupGap or 0)
        if gi < #groups then dxDrawRectangle(bx - groupGap / 2, y + s(10), 1, h - s(20), T.line) end
    end
    if BAR.infusionOpen and model.infusion then drawInfusion(model.infusion, x, y, math.min(w, s(620))) end
end

-- the panel is gone / covered: the device windows go with it
function BAR.hidden()
    setAnchor(false)
end

-- the open panel is not at the bedside any more, or closed: medsys host mode ends (sync timer)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if watching and medsysRunning() then
        exports.medsys:hostWatch(nil, false)
        exports.medsys:setHostAnchor(false)
    end
end)
