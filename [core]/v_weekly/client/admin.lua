-- /weekly admin panel (mouse-driven DX window). The server sends an overview;
-- every change goes back as weekly:adminEdit and the server answers with a
-- fresh overview that refreshes the open panel. Text values are typed through
-- the ui_core text-input overlay.

local uicore = exports.ui_core
local function S(z) return uicore:ui(z) end

local adm = nil         -- { data, week, tab, scroll }
local buttons = {}      -- built during the frame being drawn
local hitList = {}      -- buttons of the last finished frame (click targets)
local pending           -- text-input flow: { kind, offset, ... }
local textToken

local C = {
    bg      = tocolor(14, 16, 24, 242),
    side    = tocolor(20, 23, 34, 255),
    row     = tocolor(26, 30, 44, 255),
    btn     = tocolor(40, 46, 66, 255),
    btnHot  = tocolor(58, 66, 94, 255),
    accent  = tocolor(0, 130, 220, 255),
    text    = tocolor(235, 238, 245, 255),
    dim     = tocolor(150, 158, 175, 255),
    head    = tocolor(0, 150, 255, 255),
    money   = tocolor(110, 220, 130, 255),
    xp      = tocolor(255, 200, 90, 255),
    danger  = tocolor(170, 50, 50, 255),
    dangerHot = tocolor(200, 70, 70, 255),
}

local TABS = {
    { id = "jobs",  label = "Job multipliers" },
    { id = "trial", label = "Time trial" },
    { id = "login", label = "Login bonus" },
    { id = "news",  label = "News" },
}

local function fmtInt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

--------------------------------------------------------------------------------
-- server requests
--------------------------------------------------------------------------------

local function curWeek() return adm.data.weeks[adm.week] end

local function edit(action, ...)
    triggerServerEvent("weekly:adminEdit", localPlayer, action, curWeek().offset, ...)
end

local function askText(kind, title, max, default, extra)
    pending = extra or {}
    pending.kind = kind
    pending.offset = curWeek().offset
    textToken = uicore:openTextInput(title, max, default)
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= textToken or not pending then return end
    textToken = nil
    local p = pending
    pending = nil
    if not text or not adm then return end -- cancelled
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    local function send(action, ...)
        triggerServerEvent("weekly:adminEdit", localPlayer, action, p.offset, ...)
    end

    if p.kind == "money" or p.kind == "xp" then
        local n = tonumber(text)
        if not n or n < 0 then
            uicore:addNotification("Weekly", "Enter a whole number (0 removes it).", true)
            return
        end
        n = math.floor(n)
        if p.kind == "money" then send("login", n, p.xp) else send("login", p.money, n) end
    elseif p.kind == "newsTitle" then
        send("news", text, p.body)
    elseif p.kind == "newsBody" then
        send("news", p.title, text)
    end
end)

--------------------------------------------------------------------------------
-- drawing helpers
--------------------------------------------------------------------------------

local function cursorPx()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    local sw, sh = guiGetScreenSize()
    return cx * sw, cy * sh
end

local function button(x, y, w, h, label, onClick, style)
    local mx, my = cursorPx()
    local hot = mx >= x and mx <= x + w and my >= y and my <= y + h and not textToken
    local col
    if style == "active" then col = C.accent
    elseif style == "danger" then col = hot and C.dangerHot or C.danger
    else col = hot and C.btnHot or C.btn end
    dxDrawRectangle(x, y, w, h, col)
    dxDrawText(label, x, y, x + w, y + h, C.text, S(1.1), "default-bold", "center", "center", true)
    buttons[#buttons + 1] = { x = x, y = y, w = w, h = h, fn = onClick }
end

local function text(str, x, y, w, h, color, scale, font, ax, ay, wrap)
    dxDrawText(str, x, y, x + w, y + h, color or C.text, S(scale or 1.2), font or "default",
        ax or "left", ay or "center", true, wrap or false)
end

local function jobName(id)
    for _, j in ipairs(adm.data.jobs) do if j.id == id then return j.name end end
    return id
end

--------------------------------------------------------------------------------
-- tabs
--------------------------------------------------------------------------------

local function drawJobs(x, y, w, h)
    local data, week = adm.data, curWeek()
    local rowH = S(46)
    text("JOB", x + S(14), y, w * 0.4, S(26), C.dim, 1.0, "default-bold")
    text("MONEY", x + w * 0.45, y, w * 0.25, S(26), C.money, 1.0, "default-bold")
    text("XP", x + w * 0.73, y, w * 0.25, S(26), C.xp, 1.0, "default-bold")
    y = y + S(28)
    h = h - S(28)

    if #data.jobs == 0 then
        text("v_jobmanager has no official Jobs (or is not running).", x + S(14), y, w, S(40), C.dim)
        return
    end

    local visible = math.max(1, math.floor(h / rowH))
    adm.scroll = math.max(0, math.min(adm.scroll, #data.jobs - visible))
    adm.visible = visible

    local bw, bh = S(54), S(30)
    for i = 1, visible do
        local j = data.jobs[adm.scroll + i]
        if not j then break end
        local ry = y + (i - 1) * rowH
        dxDrawRectangle(x, ry, w, rowH - S(4), C.row)
        text(j.name, x + S(14), ry, w * 0.42, rowH - S(4), C.text, 1.2, "default-bold")
        local m = week.jobs[j.id]
        local curMoney, curXp = m and m.money or 1, m and m.xp or 1
        for k, mult in ipairs(data.multipliers) do
            local bx = x + w * 0.45 + (k - 1) * (bw + S(6))
            button(bx, ry + (rowH - S(4) - bh) / 2, bw, bh, mult .. "x",
                function() edit("job", j.id, mult, curXp) end, curMoney == mult and "active")
            local bx2 = x + w * 0.73 + (k - 1) * (bw + S(6))
            button(bx2, ry + (rowH - S(4) - bh) / 2, bw, bh, mult .. "x",
                function() edit("job", j.id, curMoney, mult) end, curXp == mult and "active")
        end
    end
    if #data.jobs > visible then
        text(("%d-%d of %d  (mouse wheel)"):format(adm.scroll + 1, math.min(#data.jobs, adm.scroll + visible), #data.jobs),
            x, y + visible * rowH, w, S(22), C.dim, 1.0, "default", "right")
    end
end

local function drawTrial(x, y, w, h)
    local data, week = adm.data, curWeek()
    if #data.trials == 0 then
        text("v_timetrial is not running.", x + S(14), y, w, S(40), C.dim)
        return
    end
    local rowH = S(46)
    for i, t in ipairs(data.trials) do
        local ry = y + (i - 1) * rowH
        if ry + rowH > y + h then break end
        dxDrawRectangle(x, ry, w, rowH - S(4), C.row)
        text(t.name, x + S(14), ry, w * 0.4, rowH - S(4), C.text, 1.2, "default-bold")
        text(("limit %ds"):format(t.time or 0), x + w * 0.45, ry, w * 0.2, rowH - S(4), C.dim)
        text("€" .. fmtInt(t.reward), x + w * 0.62, ry, w * 0.2, rowH - S(4), C.money, 1.2, "default-bold")
        local active = week.timetrial == i
        button(x + w - S(130), ry + S(7), S(116), S(30), active and "ACTIVE" or "Select",
            function() if not active then edit("trial", i) end end, active and "active")
    end
end

local function drawLogin(x, y, w, h)
    local data, week = adm.data, curWeek()
    local b = week.loginBonus or { money = 0, xp = 0 }
    local rowH = S(56)

    local function line(i, label, valueText, color, onEdit)
        local ry = y + (i - 1) * rowH
        dxDrawRectangle(x, ry, w, rowH - S(6), C.row)
        text(label, x + S(14), ry, w * 0.3, rowH - S(6), C.dim, 1.2, "default-bold")
        text(valueText, x + w * 0.3, ry, w * 0.4, rowH - S(6), color, 1.5, "default-bold")
        button(x + w - S(130), ry + S(10), S(116), S(32), "Edit", onEdit)
    end

    line(1, "Money", b.money > 0 and ("€" .. fmtInt(b.money)) or "none", b.money > 0 and C.money or C.dim, function()
        askText("money", "Login bonus money (0 = none)", 8, tostring(b.money), { xp = b.xp })
    end)
    line(2, "XP", b.xp > 0 and (fmtInt(b.xp) .. " XP") or "none", b.xp > 0 and C.xp or C.dim, function()
        askText("xp", "Login bonus XP (0 = none)", 8, tostring(b.xp), { money = b.money })
    end)

    text(("Paid once per %s to every player who logs in. Max €%s / %s XP."):format(
        data.period, fmtInt(data.maxMoney), fmtInt(data.maxXp)),
        x + S(14), y + rowH * 2 + S(6), w - S(28), S(40), C.dim, 1.1, "default", "left", "top", true)
end

local function drawNews(x, y, w, h)
    local week = curWeek()
    local news = week.news or { title = "", body = "" }
    dxDrawRectangle(x, y, w, S(56), C.row)
    text("Title", x + S(14), y, w * 0.2, S(56), C.dim, 1.2, "default-bold")
    text(news.title ~= "" and news.title or "(none)", x + w * 0.2, y, w * 0.55, S(56),
        news.title ~= "" and C.text or C.dim, 1.3, "default-bold")
    button(x + w - S(130), y + S(12), S(116), S(32), "Edit", function()
        askText("newsTitle", "News title", 60, news.title, { body = news.body })
    end)

    local by = y + S(66)
    local bh = math.min(h - S(66), S(220))
    dxDrawRectangle(x, by, w, bh, C.row)
    text("Text", x + S(14), by + S(8), w * 0.2, S(26), C.dim, 1.2, "default-bold", "left", "top")
    text(news.body ~= "" and news.body or "(none)", x + w * 0.2, by + S(8), w * 0.55 - S(8), bh - S(16),
        news.body ~= "" and C.text or C.dim, 1.2, "default", "left", "top", true)
    button(x + w - S(130), by + S(12), S(116), S(32), "Edit", function()
        askText("newsBody", "News text", 600, news.body, { title = news.title })
    end)
end

local DRAW = { jobs = drawJobs, trial = drawTrial, login = drawLogin, news = drawNews }

--------------------------------------------------------------------------------
-- window
--------------------------------------------------------------------------------

local function weekLabel(w)
    if w.offset == 0 then return "This week" end
    if w.offset == 1 then return "Next week" end
    return "In " .. w.offset .. " weeks"
end

local function closePanel()
    if not adm then return end
    adm = nil
    pending, textToken = nil, nil
    removeEventHandler("onClientRender", root, drawAdmin)
    showCursor(false)
    toggleAllControls(true, true, false)
end

function drawAdmin()
    if not adm then return end
    buttons = {}

    local sw, sh = guiGetScreenSize()
    local W, H = math.min(S(960), sw - S(40)), math.min(S(600), sh - S(40))
    local X, Y = (sw - W) / 2, (sh - H) / 2
    local pad = S(16)

    dxDrawRectangle(X, Y, W, H, C.bg)
    dxDrawRectangle(X, Y, W, S(4), C.accent)
    text("WEEKLY", X + pad, Y + S(10), S(200), S(36), C.head, 1.9, "default-bold")
    text("next change: " .. adm.data.nextChange .. "  (Europe/Budapest)", X + pad + S(150), Y + S(10), W * 0.6, S(36), C.dim, 1.1)
    button(X + W - S(48), Y + S(12), S(32), S(30), "X", closePanel, "danger")

    -- week list
    local sx, sy, sw2 = X + pad, Y + S(58), S(200)
    local weekH = S(58)
    dxDrawRectangle(sx - S(6), sy - S(6), sw2 + S(12), H - S(70), C.side)
    for i, w in ipairs(adm.data.weeks) do
        local by = sy + (i - 1) * (weekH + S(6))
        local sel = adm.week == i
        button(sx, by, sw2, weekH, "", function() adm.week = i; adm.scroll = 0 end, sel and "active")
        text(weekLabel(w), sx + S(10), by + S(6), sw2 - S(20), S(24), C.text, 1.2, "default-bold")
        text(w.from .. (w.inherited and "  (inherited)" or ""), sx + S(10), by + S(30), sw2 - S(20), S(20),
            sel and C.text or C.dim, 1.0)
    end

    -- tabs
    local cx = sx + sw2 + S(20)
    local cw = X + W - pad - cx
    local tabW = cw / #TABS
    for i, t in ipairs(TABS) do
        button(cx + (i - 1) * tabW, Y + S(58), tabW - S(6), S(34), t.label, function() adm.tab = t.id; adm.scroll = 0 end,
            adm.tab == t.id and "active")
    end

    -- content
    local contentY = Y + S(104)
    local contentH = H - S(104) - S(64)
    DRAW[adm.tab](cx, contentY, cw, contentH)

    -- footer
    local fy = Y + H - S(52)
    button(cx, fy, S(170), S(34), "Preview panel", function() triggerServerEvent("weekly:adminPreview", localPlayer) end)
    button(cx + cw - S(230), fy, S(230), S(34), "Reset week (inherit previous)",
        function() edit("reset") end, "danger")
end

addEvent("weekly:openAdmin", true)
addEventHandler("weekly:openAdmin", localPlayer, function(data, refresh)
    if adm then
        if refresh then
            adm.data = data
            adm.week = math.min(adm.week, #data.weeks)
        else
            closePanel() -- /weekly again toggles it off
        end
        return
    end
    adm = { data = data, week = 1, tab = "jobs", scroll = 0 }
    showCursor(true)
    toggleAllControls(false, true, false)
    addEventHandler("onClientRender", root, drawAdmin)
end)

addEventHandler("onClientClick", root, function(btn, state)
    if not adm or btn ~= "left" or state ~= "down" or textToken then return end
    local mx, my = cursorPx()
    for i = #hitList, 1, -1 do
        local b = hitList[i]
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            b.fn()
            return
        end
    end
end)

-- publish the finished frame's buttons as click targets
addEventHandler("onClientRender", root, function()
    if adm then hitList = buttons end
end, false, "low-10")

local function wheel(dir)
    if not adm or adm.tab ~= "jobs" or textToken then return end
    adm.scroll = adm.scroll + dir
end
bindKey("mouse_wheel_up", "down", function() wheel(-1) end)
bindKey("mouse_wheel_down", "down", function() wheel(1) end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if adm then closePanel() end
end)
