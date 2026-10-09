-- Weekly news panel (DX). Shown once per week by the server; ENTER / SPACE closes it.

local uicore = exports.ui_core
local function ui(z) return uicore:ui(z) end

local panel = nil -- { data, openedAt, lines }

local COL = {
    bg      = tocolor(14, 16, 24, 235),
    head    = tocolor(0, 150, 255, 255),
    text    = tocolor(235, 238, 245, 255),
    dim     = tocolor(150, 158, 175, 255),
    money   = tocolor(110, 220, 130, 255),
    xp      = tocolor(255, 200, 90, 255),
    line    = tocolor(60, 66, 85, 255),
}

local function fmt(n)
    n = tonumber(n) or 1
    return ("%sx"):format((("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")))
end

local function close()
    if not panel then return end
    panel = nil
    unbindKey("enter", "down", close)
    unbindKey("space", "down", close)
    removeEventHandler("onClientRender", root, drawPanel)
end

function drawPanel()
    if not panel then return end
    local sw, sh = guiGetScreenSize()
    local d = panel.data
    local t = math.min(1, (getTickCount() - panel.openedAt) / 300)
    local a = math.floor(255 * t)

    local w = ui(620)
    local pad = ui(24)
    local innerW = w - pad * 2
    local fontH = dxGetFontHeight(ui(1.2), "default-bold")
    local rowH = fontH + ui(8)

    -- height: header + news + bonuses + timetrial + footer
    local h = pad * 2 + ui(46) + ui(28)
    local newsH = 0
    if d.news and ((d.news.body and d.news.body ~= "") or (d.news.title and d.news.title ~= "")) then
        newsH = ui(20) + fontH + dxGetFontHeight(ui(1.2), "default") * 5 + ui(16)
        h = h + newsH
    end
    h = h + ui(22) + math.max(1, #d.jobs) * rowH + ui(14)
    if d.loginBonus then h = h + ui(22) + rowH + ui(14) end
    if d.timetrial then h = h + ui(22) + rowH + ui(14) end

    local x, y = (sw - w) / 2, (sh - h) / 2 - (1 - t) * ui(30)
    dxDrawRectangle(x, y, w, h, COL.bg)
    dxDrawRectangle(x, y, w, ui(4), tocolor(0, 150, 255, a))

    local cy = y + pad
    dxDrawText("WEEKLY UPDATE", x + pad, cy, x + w - pad, cy + ui(30), COL.head, ui(1.9), "default-bold")
    cy = cy + ui(32)
    dxDrawText(d.from .. "  -  " .. d.to, x + pad, cy, x + w - pad, cy + ui(18), COL.dim, ui(1.1), "default")
    cy = cy + ui(28)
    dxDrawRectangle(x + pad, cy - ui(8), innerW, 1, COL.line)

    if newsH > 0 then
        if d.news.title and d.news.title ~= "" then
            dxDrawText(d.news.title, x + pad, cy, x + w - pad, cy + fontH, COL.text, ui(1.2), "default-bold")
        end
        cy = cy + fontH + ui(6)
        local bodyH = dxGetFontHeight(ui(1.2), "default") * 5
        dxDrawText(d.news.body or "", x + pad, cy, x + w - pad, cy + bodyH, COL.dim, ui(1.2), "default",
            "left", "top", true, true)
        cy = cy + bodyH + ui(24)
    end

    dxDrawText("BONUSES", x + pad, cy, x + w - pad, cy + ui(18), COL.head, ui(1.1), "default-bold")
    cy = cy + ui(22)
    if #d.jobs == 0 then
        dxDrawText("No active bonuses this week.", x + pad, cy, x + w - pad, cy + rowH, COL.dim, ui(1.2), "default")
        cy = cy + rowH
    else
        for _, j in ipairs(d.jobs) do
            dxDrawText(j.name, x + pad, cy, x + w * 0.5, cy + rowH, COL.text, ui(1.2), "default-bold")
            dxDrawText("Money " .. fmt(j.money), x + w * 0.5, cy, x + w * 0.68, cy + rowH, COL.money, ui(1.2), "default-bold")
            dxDrawText("XP " .. fmt(j.xp), x + w * 0.68, cy, x + w * 0.8, cy + rowH, COL.xp, ui(1.2), "default-bold")
            dxDrawText(j.label or "", x + w * 0.8, cy, x + w - pad, cy + rowH, COL.dim, ui(1.0), "default", "right")
            cy = cy + rowH
        end
    end
    cy = cy + ui(14)

    if d.loginBonus then
        dxDrawText("LOGIN BONUS", x + pad, cy, x + w - pad, cy + ui(18), COL.head, ui(1.1), "default-bold")
        cy = cy + ui(22)
        local b = d.loginBonus
        if (b.money or 0) > 0 then
            dxDrawText(("€%d"):format(b.money), x + pad, cy, x + w * 0.3, cy + rowH, COL.money, ui(1.2), "default-bold")
        end
        if (b.xp or 0) > 0 then
            dxDrawText(("%d XP"):format(b.xp), x + w * 0.3, cy, x + w * 0.6, cy + rowH, COL.xp, ui(1.2), "default-bold")
        end
        dxDrawText("once per " .. WEEKLY.LOGIN_BONUS_PERIOD, x + w * 0.6, cy, x + w - pad, cy + rowH, COL.dim, ui(1.0), "default", "right")
        cy = cy + rowH + ui(14)
    end

    if d.timetrial then
        dxDrawText("TIME TRIAL OF THE WEEK", x + pad, cy, x + w - pad, cy + ui(18), COL.head, ui(1.1), "default-bold")
        cy = cy + ui(22)
        dxDrawText(d.timetrial.name, x + pad, cy, x + w * 0.5, cy + rowH, COL.text, ui(1.2), "default-bold")
        dxDrawText(("Limit: %ds"):format(d.timetrial.time or 0), x + w * 0.5, cy, x + w * 0.68, cy + rowH, COL.dim, ui(1.2), "default")
        dxDrawText(("Reward: €%d"):format(d.timetrial.reward or 0), x + w * 0.68, cy, x + w - pad, cy + rowH, COL.money, ui(1.2), "default-bold", "right")
    end

    dxDrawText("Press ENTER to close", x, y + h - pad - ui(2), x + w, y + h, COL.dim, ui(1.0), "default", "center", "bottom")
end

addEvent("weekly:showPanel", true)
addEventHandler("weekly:showPanel", localPlayer, function(data)
    if type(data) ~= "table" then return end
    if panel then close() end
    panel = { data = data, openedAt = getTickCount() }
    bindKey("enter", "down", close)
    bindKey("space", "down", close)
    addEventHandler("onClientRender", root, drawPanel)
end)

addEvent("weekly:notify", true)
addEventHandler("weekly:notify", localPlayer, function(text, title)
    uicore:addNotification(title or "Weekly", tostring(text), title == nil)
end)
