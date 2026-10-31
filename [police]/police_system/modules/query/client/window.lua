-- police_system / modules/query/client/window.lua
-- The query window left of the mini panel: the last person / vehicle check of the unit. Flags colour coded
-- (WARRANT, WANTED, Suspended, Stolen, Expired). Backspace hides it (always, the decision), it hides by itself after
-- HIDE_AFTER; the MDC keeps the checks (Overview / profile).

local QW = POL.module("queryw", { data = nil, shownAt = 0 })

local function rows(r)
    local out, flags = {}, {}
    local c = POL.colors
    if r.kind == "person" then
        out[#out + 1] = { L("police_system.query.name"), r.name .. (r.npc and "  (NPC)" or "") }
        out[#out + 1] = { L("police_system.query.citizen_id"), "#" .. tostring(r.id) }
        out[#out + 1] = { L("police_system.query.birth"), tostring(r.birth or "-") }
        out[#out + 1] = { L("police_system.query.licence"), L("police_system.query.licence_" .. tostring(r.licence)),
                          r.licence == "suspended" and c.red or nil }
        if (r.warrants or 0) > 0 then flags[#flags + 1] = { "WARRANT", c.red } end
        if (r.wanted or 0) > 0 then flags[#flags + 1] = { "WANTED " .. ("★"):rep(r.wanted), c.yellow } end
        if r.licence == "suspended" then flags[#flags + 1] = { L.upper(L("police_system.query.suspended")), c.orange } end
    else
        out[#out + 1] = { L("police_system.query.plate"), tostring(r.plate or "-") }
        out[#out + 1] = { L("police_system.query.model"), exports.veh_manager:getModelName(r.model or 0) or "?" }
        out[#out + 1] = { L("police_system.query.owner"), tostring(r.owner) .. (r.ownerNpc and "  (NPC)" or "") }
        out[#out + 1] = { L("police_system.query.registration"), tostring(r.registration) }
        local exp = tostring(r.inspection):find("expired")
        out[#out + 1] = { L("police_system.query.inspection"), tostring(r.inspection), exp and c.red or nil }
        if r.stolen then flags[#flags + 1] = { "STOLEN", c.red } end
        if (r.ownerWarrants or 0) > 0 then flags[#flags + 1] = { "OWNER WARRANT", c.red } end
        if exp then flags[#flags + 1] = { L.upper(L("police_system.query.expired")), c.orange } end
    end
    return out, flags
end

local cv = POL.canvas()

-- the window into the canvas (only when a new result arrives)
local function paint()
    local r = QW.data
    if not r then return end
    local list, flags = rows(r)
    local w = POL.px(290)
    local lh = POL.px(20)
    local h = POL.px(40) + #list * lh + (#flags > 0 and POL.px(26) or 0) + POL.px(22)
    cv:paint(w, h, function()
        local c = POL.colors
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, w, POL.px(30), c.panel2)
        local title = r.kind == "person" and L("police_system.query.person_check") or L("police_system.query.vehicle_check")
        dxDrawText(L.upper(title), POL.px(10), 0, w, POL.px(30), c.text, 1, POL.font(10, true), "left", "center")
        local fy = POL.px(36)
        if #flags > 0 then
            local fx = POL.px(10)
            for _, f in ipairs(flags) do
                local tw = dxGetTextWidth(f[1], 1, POL.font(9, true)) + POL.px(12)
                dxDrawRectangle(fx, fy, tw, POL.px(20), f[2])
                dxDrawText(f[1], fx, fy, fx + tw, fy + POL.px(20), c.white, 1, POL.font(9, true), "center", "center")
                fx = fx + tw + POL.px(6)
            end
            fy = fy + POL.px(26)
        end
        for _, row in ipairs(list) do
            dxDrawText(row[1], POL.px(10), fy, POL.px(110), fy + lh, c.dim, 1, POL.font(9), "left", "center")
            dxDrawText(row[2], POL.px(110), fy, w - POL.px(10), fy + lh, row[3] or c.text, 1, POL.font(10, true),
                "left", "center", true)
            fy = fy + lh
        end
        dxDrawText(L("police_system.query.backspace_hide"), 0, h - POL.px(20), w - POL.px(8), h, c.dim, 1,
            POL.font(8), "right", "center")
    end)
end

local function draw()
    if not QW.data then return end
    if getTickCount() - QW.shownAt > POLICE.QUERY.HIDE_AFTER then
        QW.data = nil
        POL.layers.set("query", false)
        return
    end
    local mx, my = POL.hud.rect()
    local x, y = mx - cv.w - POL.px(10), my + POL.px(96) - cv.h
    if not POL.onDuty() then x, y = POL.sw - cv.w - POL.px(22), POL.sh - cv.h - POL.px(22) end
    cv:draw(x, y)
end
POL.layers.add("query", draw, 11)

POL.handle("query:result", function(r)
    if type(r) ~= "table" then return end
    QW.data = r
    QW.shownAt = getTickCount()
    paint()
    POL.layers.set("query", true)
end)

POL.key("query", function(button, press)
    if button ~= "backspace" or not QW.data then return false end
    if press then
        QW.data = nil
        POL.layers.set("query", false)
    end
    return true
end, 70)

addEventHandler("onClientRestore", root, function(cleared) if cleared and QW.data then paint() end end)
