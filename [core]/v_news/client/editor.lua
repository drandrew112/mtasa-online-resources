if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /news editor: every article on the left, the editor on the right.
-- Text input is our own (field.lua), not ui_core's: the text needs new lines.
-- While open every key bind is off (guiSetInputMode "no_binds"); while a field
-- is focused every key press is cancelled and "textInputOpen" is set as well
-- (same rules as the v_admin panel).

local sw, sh = guiGetScreenSize()
local S = math.max(0.6, sh / 1080)
local function s(v) return v * S end

local C = {
    shade  = tocolor(0, 0, 0, 150),
    win    = tocolor(19, 23, 29, 250),
    head   = tocolor(25, 30, 38, 255),
    accent = tocolor(64, 156, 180, 255),
    sel    = tocolor(64, 156, 180, 50),
    textSel= tocolor(64, 156, 180, 120),
    field  = tocolor(32, 36, 42, 255),
    text   = tocolor(228, 233, 238, 255),
    dim    = tocolor(146, 158, 170, 255),
    btn    = tocolor(40, 118, 136, 255),
    btnHi  = tocolor(64, 156, 180, 255),
    ghost  = tocolor(38, 43, 50, 255),
    ghostHi= tocolor(56, 63, 72, 255),
    danger = tocolor(122, 45, 45, 255),
    dangerHi = tocolor(170, 60, 60, 255),
    warn   = tocolor(255, 200, 90, 255),
    line   = tocolor(255, 255, 255, 14),
}

local open = false
local list = {}          -- { id, dateText, timeText, title, body, author, scheduled }
local nowDate, nowTime = "", ""
local selected = nil     -- article id being edited, nil = new article
local listScroll = 0
local focus = nil        -- "date" | "time" | "title" | "body"
local deleteArmed = 0    -- tick of the first Delete click (second click within 3 s deletes)
local hits = {}
local dragging = nil     -- field id while the left button is held after clicking into it (selection)
local dragFrom = nil     -- press point; the selection only follows the mouse once it moved away

local fields = {
    date  = TextField.new{ max = 10, filter = function(ch) return ch:match("[%d%.]") ~= nil end },
    time  = TextField.new{ max = 5,  filter = function(ch) return ch:match("[%d:]") ~= nil end },
    title = TextField.new{ max = NEWS.TITLE_MAX },
    body  = TextField.new{ max = NEWS.BODY_MAX, multiline = true },
}
local ORDER = { "date", "time", "title", "body" }

local function notify(text)
    exports.ui_core:addNotification(L("v_news.panel.title"), text)
end

local function setFocus(id)
    if focus and focus ~= id then fields[focus].anchor = nil end
    focus = id
    setElementData(localPlayer, "textInputOpen", id ~= nil, false)
end

local function articleById(id)
    for _, a in ipairs(list) do
        if a.id == id then return a end
    end
end

local function loadArticle(a)
    deleteArmed = 0
    if a then
        selected = a.id
        fields.date:setText(a.dateText)
        fields.time:setText(a.timeText)
        fields.title:setText(a.title)
        fields.body:setText(a.body)
    else
        selected = nil
        fields.date:setText(nowDate)
        fields.time:setText(nowTime)
        fields.title:setText("")
        fields.body:setText("")
    end
end

local function save()
    triggerServerEvent("v_news:save", localPlayer, selected, fields.date:getText(), fields.time:getText(),
        fields.title:getText(), fields.body:getText())
end

--------------------------------------------------------------------------------
-- drawing helpers
--------------------------------------------------------------------------------

local function cursor()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * sw, cy * sh
end

local function inRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function hit(x, y, w, h, fn)
    hits[#hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

local function button(x, y, w, h, label, fn, style)
    local mx, my = cursor()
    local hover = inRect(mx, my, x, y, w, h)
    local bg = style == "ghost" and (hover and C.ghostHi or C.ghost)
        or style == "danger" and (hover and C.dangerHi or C.danger)
        or (hover and C.btnHi or C.btn)
    dxDrawRectangle(x, y, w, h, bg)
    dxDrawText(label, x, y, x + w, y + h, C.text, s(1.05), "default-bold", "center", "center", true)
    hit(x, y, w, h, fn)
end

local function label(text, x, y, w)
    dxDrawText(text, x, y, x + w, y + s(18), C.dim, s(0.95), "default-bold", "left", "center")
end

local function fieldBox(id, x, y, w, h)
    local f = fields[id]
    local focused = focus == id
    dxDrawRectangle(x, y, w, h, C.field)
    if focused then
        dxDrawRectangle(x, y, w, s(2), C.accent)
        dxDrawRectangle(x, y + h - s(2), w, s(2), C.accent)
    end
    dxDrawRectangle(x, y, s(3), h, C.accent)
    local pad = s(10)
    local style = { font = "default", scale = s(1.1), color = C.text, caret = C.text, sel = C.textSel }
    if f.multiline then
        f:draw(x + pad, y + pad, w - pad * 2 - s(8), h - pad * 2, focused, style)
    else
        f:draw(x + pad, y, w - pad * 2, h, focused, style)
    end
    hit(x, y, w, h, function(px, py)
        local shift = focus == id and (getKeyState("lshift") or getKeyState("rshift"))
        setFocus(id)
        f:clickAt(px, py, shift)
        dragging, dragFrom = id, { px, py }
    end)
    hits[#hits].field = id
end

--------------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------------

local function render()
    if dragging then
        if getKeyState("mouse1") and isCursorShowing() then
            local cx, cy = getCursorPosition()
            cx, cy = cx * sw, cy * sh
            if dragFrom and math.abs(cx - dragFrom[1]) + math.abs(cy - dragFrom[2]) > 3 then dragFrom = nil end
            if not dragFrom then fields[dragging]:dragTo(cx, cy) end
        else
            dragging = nil
        end
    end
    hits = {}
    local W, H = s(1260), s(760)
    local X, Y = math.floor((sw - W) / 2), math.floor((sh - H) / 2)
    local headH = s(46)

    dxDrawRectangle(0, 0, sw, sh, C.shade)
    dxDrawRectangle(X + s(6), Y + s(8), W, H, tocolor(0, 0, 0, 120))
    dxDrawRectangle(X, Y, W, H, C.win)
    dxDrawRectangle(X, Y, W, headH, C.head)
    dxDrawRectangle(X, Y + headH - s(3), W, s(3), C.accent)
    dxDrawText(L("v_news.panel.editor_title"), X + s(20), Y, X + W, Y + headH, C.text, s(1.5), "default-bold", "left", "center")
    button(X + W - s(46), Y + s(8), s(36), headH - s(16), "X", function() closeEditor() end, "ghost")

    -- left: list
    local LW = math.floor(W * 0.34)
    local lx, ly = X, Y + headH
    local lh = H - headH
    dxDrawRectangle(lx + LW, ly, 1, lh, C.line)
    button(lx + s(14), ly + s(14), LW - s(28), s(38), L("v_news.panel.new_article"), function()
        loadArticle(nil)
        setFocus("title")
    end)

    local rowH = s(62)
    local listY = ly + s(66)
    local listH = lh - s(66)
    local visible = math.floor(listH / rowH)
    listScroll = math.max(0, math.min(listScroll, math.max(0, #list - visible)))
    local mx, my = cursor()
    if #list == 0 then
        dxDrawText(L("v_news.panel.no_articles"), lx + s(16), listY, lx + LW - s(16), listY + s(40), C.dim, s(1.05), "default", "left", "center")
    end
    for i = listScroll + 1, math.min(#list, listScroll + visible) do
        local a = list[i]
        local ry = listY + (i - listScroll - 1) * rowH
        local isSel = a.id == selected
        if isSel then
            dxDrawRectangle(lx, ry, LW, rowH, C.sel)
            dxDrawRectangle(lx, ry, s(3), rowH, C.accent)
        elseif inRect(mx, my, lx, ry, LW, rowH) then
            dxDrawRectangle(lx, ry, LW, rowH, tocolor(255, 255, 255, 8))
        end
        local dateLine = a.dateText .. " " .. a.timeText
        dxDrawText(dateLine, lx + s(16), ry + s(8), lx + LW - s(16), ry + s(26), C.dim, s(0.95), "default", "left", "center")
        if a.scheduled then
            local dw = dxGetTextWidth(dateLine, s(0.95), "default")
            dxDrawText(L("v_news.panel.scheduled"), lx + s(26) + dw, ry + s(8), lx + LW - s(16), ry + s(26), C.warn, s(0.9), "default-bold", "left", "center")
        end
        dxDrawText(a.title, lx + s(16), ry + s(28), lx + LW - s(16), ry + s(54), C.text, s(1.1), "default-bold", "left", "center", true)
        dxDrawRectangle(lx, ry + rowH - 1, LW, 1, C.line)
        hit(lx, ry, LW, rowH, function() loadArticle(a) setFocus(nil) end)
    end
    hits[#hits + 1] = { x = lx, y = listY, w = LW, h = listH, wheel = function(d) listScroll = listScroll + d end }

    -- right: editor
    local ex = X + LW + s(24)
    local ew = W - LW - s(48)
    local ey = Y + headH + s(18)
    local fh = s(40)
    local colW = math.floor((ew - s(130)) / 2)

    label(L("v_news.panel.date"), ex, ey, colW)
    label(L("v_news.panel.time"), ex + colW + s(10), ey, colW)
    fieldBox("date", ex, ey + s(22), colW, fh)
    fieldBox("time", ex + colW + s(10), ey + s(22), colW, fh)
    button(ex + colW * 2 + s(20), ey + s(22), ew - colW * 2 - s(20), fh, L("v_news.panel.now"), function()
        fields.date:setText(nowDate)
        fields.time:setText(nowTime)
    end, "ghost")

    local ty = ey + s(22) + fh + s(14)
    label(L("v_news.panel.article_title"), ex, ty, ew)
    fieldBox("title", ex, ty + s(22), ew, fh)

    local by = ty + s(22) + fh + s(14)
    label(L("v_news.panel.text"), ex, by, ew)
    local footH = s(56)
    local bodyY = by + s(22)
    local bodyH = (Y + H - footH) - bodyY - s(8)
    fieldBox("body", ex, bodyY, ew, bodyH)
    hits[#hits + 1] = { x = ex, y = bodyY, w = ew, h = bodyH, wheel = function(d) fields.body:scrollBy(d * 3) end }

    local fy = Y + H - footH
    local count = (utf8.len(fields.body:getText()) or 0)
    dxDrawText(L("v_news.panel.hint", { count = count, max = NEWS.BODY_MAX }), ex, fy, ex + ew - s(320), fy + footH - s(10),
        C.dim, s(0.95), "default", "left", "center", true)
    local bw = s(140)
    button(ex + ew - bw, fy + s(4), bw, s(40), L("v_news.panel.save"), save)
    if selected then
        local armed = getTickCount() - deleteArmed < 3000
        button(ex + ew - bw * 2 - s(10), fy + s(4), bw, s(40),
            armed and L("v_news.panel.confirm_delete") or L("v_news.panel.delete"), function()
                if getTickCount() - deleteArmed < 3000 then
                    deleteArmed = 0
                    triggerServerEvent("v_news:delete", localPlayer, selected)
                else
                    deleteArmed = getTickCount()
                end
            end, "danger")
    end
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

function closeEditor()
    if not open then return end
    open = false
    setFocus(nil)
    removeEventHandler("onClientRender", root, render)
    setElementData(localPlayer, "newsPanelOpen", false, false)
    guiSetInputMode("allow_binds")
    showCursor(false)
    exports.ui_core:toggleMoveControls(true)
    triggerServerEvent("v_news:close", localPlayer)
end

addEvent("v_news:open", true)
addEventHandler("v_news:open", localPlayer, function()
    if open then return end
    open = true
    list, selected, listScroll = {}, nil, 0
    addEventHandler("onClientRender", root, render)
    setElementData(localPlayer, "newsPanelOpen", true, false)
    guiSetInputMode("no_binds")
    showCursor(true)
    exports.ui_core:toggleMoveControls(false)
end)

addEvent("v_news:data", true)
addEventHandler("v_news:data", localPlayer, function(articles, dateText, timeText, selectId)
    list, nowDate, nowTime = articles or {}, dateText or "", timeText or ""
    if not open then return end
    local keep = articleById(selectId or selected)
    if selectId or (selected and not keep) or (not selected and fields.title:getText() == "" and fields.body:getText() == "") then
        loadArticle(keep)
    end
end)

addEvent("v_news:result", true)
addEventHandler("v_news:result", localPlayer, function(ok, text)
    notify(text)
end)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function nextField(dir)
    local idx = 1
    for i, id in ipairs(ORDER) do
        if id == focus then idx = i end
    end
    setFocus(ORDER[(idx - 1 + dir) % #ORDER + 1])
end

local function ctrlDown()
    return getKeyState("lctrl") or getKeyState("rctrl")
end

addEventHandler("onClientKey", root, function(key, press)
    if not open or not press then return end

    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local mx, my = cursor()
        for i = #hits, 1, -1 do
            local h = hits[i]
            if h.wheel and inRect(mx, my, h.x, h.y, h.w, h.h) then
                h.wheel(key == "mouse_wheel_up" and -1 or 1)
                return
            end
        end
        return
    end
    if key:find("^mouse") then return end
    if focus and key == "v" and ctrlDown() then
        -- MTA only fires onClientPaste for a "v" stroke that onClientKey did not cancel;
        -- keep GTA's V (camera) quiet for that one press instead
        if isControlEnabled("change_camera") then
            toggleControl("change_camera", false)
            setTimer(toggleControl, 250, 1, "change_camera", true)
        end
        return
    end
    cancelEvent()

    if key == "s" and ctrlDown() then return save() end

    if focus then
        local f = fields[focus]
        if key == "escape" then
            setFocus(nil)
        elseif key == "tab" then
            nextField((getKeyState("lshift") or getKeyState("rshift")) and -1 or 1)
        elseif (key == "enter" or key == "num_enter") and not f.multiline then
            nextField(1)
        elseif key == "a" and ctrlDown() then
            f:selectAll()
        elseif (key == "c" or key == "x") and ctrlDown() then
            local sel = f:getSelected()
            if sel then
                setClipboard(sel)
                if key == "x" then f:deleteSelection() end
            end
        else
            f:key(key, getKeyState("lshift") or getKeyState("rshift"))
        end
        return
    end

    if key == "escape" then
        closeEditor()
    elseif key == "tab" then
        setFocus("date")
    elseif key == "arrow_u" or key == "arrow_d" then
        if #list == 0 then return end
        local idx = 0
        for i, a in ipairs(list) do
            if a.id == selected then idx = i end
        end
        idx = math.max(1, math.min(#list, idx + (key == "arrow_u" and -1 or 1)))
        loadArticle(list[idx])
    end
end)

addEventHandler("onClientCharacter", root, function(ch)
    if not open or not focus then return end
    fields[focus]:insert(ch)
end)

addEventHandler("onClientPaste", root, function(text)
    if not open or not focus then return end
    fields[focus]:insert(text)
end)

addEventHandler("onClientClick", root, function(btn, state, absX, absY)
    if not open or btn ~= "left" or state ~= "down" then return end
    for i = #hits, 1, -1 do
        local h = hits[i]
        if h.fn and inRect(absX, absY, h.x, h.y, h.w, h.h) then
            return h.fn(absX, absY)
        end
    end
    setFocus(nil)
end)

addEventHandler("onClientDoubleClick", root, function(btn, absX, absY)
    if not open or btn ~= "left" then return end
    for i = #hits, 1, -1 do
        local h = hits[i]
        if h.field and inRect(absX, absY, h.x, h.y, h.w, h.h) then
            dragging = nil
            fields[h.field]:selectWordAt(absX, absY)
            return
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if open then
        setElementData(localPlayer, "textInputOpen", false, false)
        setElementData(localPlayer, "newsPanelOpen", false, false)
        guiSetInputMode("allow_binds")
        showCursor(false)
    end
end)
