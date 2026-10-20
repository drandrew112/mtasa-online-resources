if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Weekly updates card: sits right of the login/register panel, top edges aligned,
-- and grows downwards with its content. Data = exports.v_weekly:getWeeklyInfo,
-- pushed by the server (acc:weekly). Display only, no input.

Weekly = { data = nil }

local WIDTH = 540
local GAP   = 24

local COL = {
    text  = Theme.text,
    dim   = Theme.label,
    head  = Theme.accent,
    money = tocolor(110, 220, 130, 255),
    xp    = tocolor(255, 200, 90, 255),
    line  = Theme.accentDim,
}

local cache = nil -- { w, h, ops }

local function fmt(n)
    n = tonumber(n) or 1
    return ("%sx"):format((("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")))
end

-- Lays the card out once per (data, width, language); draw() only replays ops.
local function build(w)
    local d = Weekly.data
    local pad = ui(22)
    local innerW = w - pad * 2
    local fh = dxGetFontHeight(ui(1.2), "default-bold")
    local rowH = fh + ui(8)
    local ops = {}

    local function text(str, x, y, x2, color, scale, font, align, h)
        ops[#ops + 1] = { str, x, y, x2, y + h, color, scale, font, align }
    end
    local function rule(y)
        ops[#ops + 1] = { rule = true, x = pad, y = y, w = innerW }
    end

    local y = ui(46) + ui(14)
    text(d.from .. "  -  " .. d.to, pad, y, w - pad, COL.dim, ui(1.1), "default", "left", ui(18))
    y = y + ui(28)
    rule(y - ui(6))

    local news = d.news
    local hasNews = news and ((news.title and news.title ~= "") or (news.body and news.body ~= ""))
    if hasNews then
        if news.title and news.title ~= "" then
            text(news.title, pad, y, w - pad, COL.text, ui(1.35), "default-bold", "left", fh + ui(4))
            y = y + fh + ui(10)
        end
        if news.body and news.body ~= "" then
            local _, bh = dxGetTextSize(news.body, innerW, ui(1.2), "default", true)
            ops[#ops + 1] = { news.body, pad, y, pad + innerW, y + bh + ui(4), COL.dim, ui(1.2), "default", "left", wrap = true }
            y = y + bh + ui(8)
        end
    else
        text(L("v_accounts.weekly.no_news"), pad, y, w - pad, COL.dim, ui(1.2), "default", "left", rowH)
        y = y + rowH
    end
    y = y + ui(14)
    rule(y - ui(6))

    text(L("v_weekly.panel.bonuses"), pad, y, w - pad, COL.head, ui(1.1), "default-bold", "left", ui(18))
    y = y + ui(22)
    if #d.jobs == 0 then
        text(L("v_weekly.panel.no_active_bonuses_this_week"), pad, y, w - pad, COL.dim, ui(1.2), "default", "left", rowH)
        y = y + rowH
    else
        for _, j in ipairs(d.jobs) do
            text(j.name, pad, y, w * 0.5, COL.text, ui(1.2), "default-bold", "left", rowH)
            text(L("v_weekly.panel.money", { money = fmt(j.money) }), w * 0.5, y, w * 0.68, COL.money, ui(1.2), "default-bold", "left", rowH)
            text(L("v_weekly.panel.xp", { xp = fmt(j.xp) }), w * 0.68, y, w * 0.8, COL.xp, ui(1.2), "default-bold", "left", rowH)
            text(j.label or "", w * 0.8, y, w - pad, COL.dim, ui(1.0), "default", "right", rowH)
            y = y + rowH
        end
    end
    y = y + ui(14)

    local b = d.loginBonus
    if b then
        text(L("v_weekly.panel.login_bonus"), pad, y, w - pad, COL.head, ui(1.1), "default-bold", "left", ui(18))
        y = y + ui(22)
        if (b.money or 0) > 0 then
            text(("€%d"):format(b.money), pad, y, w * 0.3, COL.money, ui(1.2), "default-bold", "left", rowH)
        end
        if (b.xp or 0) > 0 then
            text(L("v_weekly.panel.xp_2", { xp = b.xp }), w * 0.3, y, w * 0.6, COL.xp, ui(1.2), "default-bold", "left", rowH)
        end
        text(L("v_weekly.panel.once_per", { login_bonus_period = L("v_weekly.period." .. (b.period or "day")) }),
            w * 0.6, y, w - pad, COL.dim, ui(1.0), "default", "right", rowH)
        y = y + rowH + ui(14)
    end

    local t = d.timetrial
    if t then
        text(L("v_weekly.panel.time_trial_of_week"), pad, y, w - pad, COL.head, ui(1.1), "default-bold", "left", ui(18))
        y = y + ui(22)
        text(t.name, pad, y, w * 0.5, COL.text, ui(1.2), "default-bold", "left", rowH)
        text(L("v_weekly.panel.limit_s", { time = t.time or 0 }), w * 0.5, y, w * 0.68, COL.dim, ui(1.2), "default", "left", rowH)
        text(L("v_weekly.panel.reward", { reward = t.reward or 0 }), w * 0.68, y, w - pad, COL.money, ui(1.2), "default-bold", "right", rowH)
        y = y + rowH + ui(14)
    end

    return { w = w, h = y + pad - ui(14), ops = ops }
end

function Weekly.setData(d)
    Weekly.data = type(d) == "table" and d or nil
    cache = nil
end

-- anchor: the visible login/register panel ({X, Y, W}); called from render.lua
function Weekly.draw(anchor)
    if not (Weekly.data and anchor and anchor.X) then return end
    local x = anchor.X + anchor.W + ui(GAP)
    local w = math.min(ui(WIDTH), sw - x - ui(20))
    if w < ui(320) then return end
    if not cache or cache.w ~= w then cache = build(w) end

    local y = anchor.Y
    drawPanelFrame(x, y, w, cache.h, L("v_accounts.weekly.title"))
    for _, o in ipairs(cache.ops) do
        if o.rule then
            dxDrawRectangle(x + o.x, y + o.y, o.w, 1, COL.line)
        elseif o.wrap then
            dxDrawText(o[1], x + o[2], y + o[3], x + o[4], y + o[5], o[6], o[7], o[8], o[9], "top", true, true)
        else
            dxDrawText(o[1], x + o[2], y + o[3], x + o[4], y + o[5], o[6], o[7], o[8], o[9], "center")
        end
    end
end

addEvent("acc:weekly", true)
addEventHandler("acc:weekly", root, Weekly.setData)

addEvent("v_locals:onClientLanguageChange")
addEventHandler("v_locals:onClientLanguageChange", root, function() cache = nil end)
