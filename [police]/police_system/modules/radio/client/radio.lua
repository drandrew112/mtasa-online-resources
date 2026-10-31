-- police_system / modules/radio/client/radio.lua
-- The radio panel on the left of the screen while on duty: C opens it, left / right = category, up / down = message,
-- Enter sends, C or Backspace closes. While open the arrows and C do not reach GTA (no crouch, no steering).
-- Every message is a name id (shared/radio.lua); the server's Radio.handle does the rest.

local RC = POL.module("radioc", { open = false, cat = 1, item = 1 })
local cv = POL.canvas()

local function paint()
    local cat = RADIO_CATEGORIES[RC.cat]
    local w = POL.px(270)
    local ih = POL.px(30)
    local h = POL.px(44) + #cat.items * ih + POL.px(30)
    cv:paint(w, h, function()
        local c = POL.colors
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, w, POL.px(36), c.panel2)
        dxDrawText("◀", POL.px(8), 0, w, POL.px(36), c.dim, 1, POL.font(11, true), "left", "center")
        dxDrawText("▶", 0, 0, w - POL.px(8), POL.px(36), c.dim, 1, POL.font(11, true), "right", "center")
        dxDrawText(L("police_system.radio.cat_" .. cat.id), 0, 0, w, POL.px(36), c.text, 1, POL.font(11, true), "center", "center")
        local y = POL.px(44)
        for i, id in ipairs(cat.items) do
            local sel = i == RC.item
            if sel then dxDrawRectangle(POL.px(6), y, w - POL.px(12), ih - POL.px(2), c.accentDim) end
            dxDrawText(L("police_system.radio." .. id:lower()), POL.px(16), y, w, y + ih, sel and c.white or c.text, 1,
                POL.font(10, sel), "left", "center")
            dxDrawText(id, 0, y, w - POL.px(14), y + ih, c.dim, 1, POL.font(7), "right", "center")
            y = y + ih
        end
        dxDrawText(L("police_system.radio.help"), 0, h - POL.px(26), w, h, c.dim, 1, POL.font(8), "center", "center")
    end)
end

local function draw() cv:draw(POL.px(20), POL.sh * 0.32) end
POL.layers.add("radio", draw, 12)

local function setOpen(on)
    RC.open = on
    if on then paint() end
    POL.layers.set("radio", on)
end

POL.on("unit", function(u) if not u and RC.open then setOpen(false) end end)

local NAV = { arrow_l = true, arrow_r = true, arrow_u = true, arrow_d = true, enter = true, num_enter = true, backspace = true, c = true }

POL.key("radio", function(button, press)
    if not RC.open then
        if button == "c" and POL.onDuty() and POL.hasRight() then
            if press and not (POL.mdc and POL.mdc.isOpen()) then setOpen(true) end
            return true
        end
        return false
    end
    if not NAV[button] then return false end
    if not press then return true end
    local cat = RADIO_CATEGORIES[RC.cat]
    if button == "arrow_l" then
        RC.cat = (RC.cat - 2) % #RADIO_CATEGORIES + 1; RC.item = 1
    elseif button == "arrow_r" then
        RC.cat = RC.cat % #RADIO_CATEGORIES + 1; RC.item = 1
    elseif button == "arrow_u" then
        RC.item = (RC.item - 2) % #cat.items + 1
    elseif button == "arrow_d" then
        RC.item = RC.item % #cat.items + 1
    elseif button == "enter" or button == "num_enter" then
        local id = cat.items[RC.item]
        local args
        if id == "STATUS_PURSUIT" and POL.stopc then args = { target = POL.stopc.pursuitTarget() } end
        POL.send("radio", id, args)
        setOpen(false)
        return true
    elseif button == "c" or button == "backspace" then
        setOpen(false)
        return true
    end
    paint()
    return true
end, 80)

addEventHandler("onClientRestore", root, function(cleared) if cleared and RC.open then paint() end end)
