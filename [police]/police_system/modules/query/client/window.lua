-- police_system / modules/query/client/window.lua
-- The query window left of the mini panel: the last person / vehicle check of the unit. Flags colour coded
-- (WARRANT, WANTED, Suspended, Stolen, Expired). Backspace hides it (always, the decision), it hides by itself after
-- HIDE_AFTER; the MDC keeps the checks (Overview / profile). A search result (kind "search") gets its own panel in
-- the centre of the screen instead (below).

local QW = POL.module("queryw", { data = nil, shownAt = 0 })

local function rows(r)
    local out, flags = {}, {}
    local c = POL.colors
    if r.kind == "search" then
        -- search/server/search.lua: every item, green / orange / red by its class
        local col = { legal = c.green, questionable = c.orange, illegal = c.red }
        out[#out + 1] = { L(r.what == "vehicle" and "police_system.query.plate" or "police_system.query.name"), tostring(r.name) }
        local illegal = 0
        for _, it in ipairs(r.items or {}) do
            if it.class == "illegal" then illegal = illegal + 1 end
            out[#out + 1] = { L("police_system.search.class_" .. tostring(it.class)), L("police_system.item." .. tostring(it.id)), col[it.class] }
        end
        if #(r.items or {}) == 0 then out[#out + 1] = { "", L("police_system.search.nothing"), c.dim } end
        if illegal > 0 then flags[#flags + 1] = { L.upper(L("police_system.search.illegal_found")), c.red } end
    elseif r.kind == "person" then
        out[#out + 1] = { L("police_system.query.name"), r.name .. (r.npc and "  (NPC)" or "") }
        out[#out + 1] = { L("police_system.query.citizen_id"), "#" .. tostring(r.id) }
        out[#out + 1] = { L("police_system.query.birth"), tostring(r.birth or "-") }
        out[#out + 1] = { L("police_system.query.licence"), L("police_system.query.licence_" .. tostring(r.licence)),
                          r.licence ~= "valid" and c.red or nil }
        if (r.warrants or 0) > 0 then flags[#flags + 1] = { "WARRANT", c.red } end
        if (r.wanted or 0) > 0 then flags[#flags + 1] = { "WANTED " .. ("★"):rep(r.wanted), c.yellow } end
        if r.licence ~= "valid" then flags[#flags + 1] = { L.upper(L("police_system.query.licence_" .. tostring(r.licence))), c.orange } end
    else
        out[#out + 1] = { L("police_system.query.plate"), tostring(r.plate or "-") }
        out[#out + 1] = { L("police_system.query.model"), exports.veh_manager:getModelName(r.model or 0) or "?" }
        out[#out + 1] = { L("police_system.query.owner"), tostring(r.owner) .. (r.ownerNpc and "  (NPC)" or "") }
        out[#out + 1] = { L("police_system.query.registration"), tostring(r.registration),
                          tostring(r.registration):find("expired") and c.red or nil }
        local exp = tostring(r.inspection):find("expired") or tostring(r.registration):find("expired")
        out[#out + 1] = { L("police_system.query.inspection"), tostring(r.inspection),
                          tostring(r.inspection):find("expired") and c.red or nil }
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
        local title = r.kind == "search" and L(r.what == "vehicle" and "police_system.search.title_vehicle" or "police_system.search.title_person")
            or r.kind == "person" and L("police_system.query.person_check") or L("police_system.query.vehicle_check")
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

------------------------------------------------------------------------ search panel (centre of the screen)
-- A search result is its own panel: subject (person + name / vehicle + plate), every item with its class colour.
-- Opening it closes the stop menu; Backspace or Enter closes it (no timeout).

local sv = POL.canvas()
local searchOpen = false

local function paintSearch(r)
    local c = POL.colors
    local list, illegal = {}, 0
    for _, it in ipairs(r.items or {}) do
        if it.class == "illegal" then illegal = illegal + 1 end
        list[#list + 1] = it
    end
    local w = POL.px(420)
    local lh = POL.px(26)
    local rowsH = math.max(#list, 1) * lh
    local h = POL.px(30) + POL.px(46) + (illegal > 0 and POL.px(30) or 0) + rowsH + POL.px(40)
    sv:paint(w, h, function()
        local col = { legal = c.green, questionable = c.orange, illegal = c.red }
        dxDrawRectangle(0, 0, w, h, c.bg)
        dxDrawRectangle(0, 0, w, POL.px(30), c.panel2)
        local title = L(r.what == "vehicle" and "police_system.search.title_vehicle" or "police_system.search.title_person")
        dxDrawText(L.upper(title), POL.px(12), 0, w, POL.px(30), c.text, 1, POL.font(10, true), "left", "center")
        local y = POL.px(36)
        dxDrawText(L(r.what == "vehicle" and "police_system.query.plate" or "police_system.query.name"),
            POL.px(12), y, w, y + POL.px(18), c.dim, 1, POL.font(9), "left", "center")
        dxDrawText(tostring(r.name), POL.px(12), y + POL.px(14), w - POL.px(12), y + POL.px(44), c.text, 1,
            POL.font(13, true), "left", "center", true)
        y = y + POL.px(46)
        if illegal > 0 then
            local txt = L.upper(L("police_system.search.illegal_found")) .. " ×" .. illegal
            dxDrawRectangle(POL.px(12), y + POL.px(2), w - POL.px(24), POL.px(24), c.red)
            dxDrawText(txt, POL.px(12), y + POL.px(2), w - POL.px(12), y + POL.px(26), c.white, 1, POL.font(9, true), "center", "center")
            y = y + POL.px(30)
        end
        if #list == 0 then
            dxDrawText(L("police_system.search.nothing"), POL.px(12), y, w - POL.px(12), y + lh, c.dim, 1, POL.font(10), "left", "center")
        end
        for _, it in ipairs(list) do
            local k = col[it.class] or c.text
            dxDrawRectangle(POL.px(12), y + POL.px(6), POL.px(6), lh - POL.px(12), k)
            dxDrawText(L("police_system.item." .. tostring(it.id)), POL.px(26), y, w - POL.px(110), y + lh, c.text, 1,
                POL.font(10, true), "left", "center", true)
            dxDrawText(L("police_system.search.class_" .. tostring(it.class)), w - POL.px(110), y, w - POL.px(12), y + lh,
                k, 1, POL.font(9), "right", "center")
            y = y + lh
        end
        dxDrawText(L("police_system.search.close_hint"), 0, h - POL.px(26), w - POL.px(10), h, c.dim, 1, POL.font(8), "right", "center")
    end)
end

local function closeSearch()
    searchOpen = false
    POL.layers.set("searchpanel", false)
end

POL.layers.add("searchpanel", function()
    if not searchOpen then return end
    sv:draw(math.floor((POL.sw - sv.w) / 2), math.floor((POL.sh - sv.h) / 2))
end, 12)

local function showSearch(r)
    -- the stop menu closes with the search
    local ok, m = pcall(function() return getResourceState(getResourceFromName("ui_inac")) == "running" and exports.ui_inac end)
    if ok and m then pcall(function() if m:isTempMenuOpen() then m:closeTempMenu() end end) end
    paintSearch(r)
    searchOpen = true
    POL.layers.set("searchpanel", true)
end

POL.key("searchpanel", function(button, press)
    if not searchOpen then return false end
    if button == "backspace" or button == "enter" or button == "num_enter" then
        if press then closeSearch() end
        return true
    end
    return false
end, 75)

POL.handle("query:result", function(r)
    if type(r) ~= "table" then return end
    if r.kind == "search" then return showSearch(r) end
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
