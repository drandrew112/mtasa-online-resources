if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- News card: left of the login/register panel, top edges aligned. Data = the
-- newest v_news articles, pushed by the server (acc_ui:news). Display only.

News = { data = nil }

local WIDTH = 400
local GAP   = 24
local BODY_LINES = 4

local cache = nil -- { w, h, ops }

local function build(w)
    local pad = ui(22)
    local innerW = w - pad * 2
    local ops = {}
    local y = ui(46) + ui(12)
    local smallH = dxGetFontHeight(ui(1.0), "default")
    local titleH = dxGetFontHeight(ui(1.2), "default-bold")
    local bodyLineH = dxGetFontHeight(ui(1.05), "default")

    if #News.data == 0 then
        ops[#ops + 1] = { L("acc_ui.news.no_news"), pad, y, w - pad, y + ui(24), Theme.label, ui(1.1), "default", false }
        return { w = w, h = y + ui(24) + pad, ops = ops }
    end

    for i, a in ipairs(News.data) do
        if i > 1 then
            ops[#ops + 1] = { rule = true, x = pad, y = y - ui(8), w = innerW }
        end
        ops[#ops + 1] = { a.dateText, pad, y, w - pad, y + smallH, Theme.label, ui(1.0), "default", false }
        y = y + smallH + ui(2)
        ops[#ops + 1] = { a.title, pad, y, w - pad, y + titleH, Theme.title, ui(1.2), "default-bold", false }
        y = y + titleH + ui(3)
        local _, bh = dxGetTextSize(a.body, innerW, ui(1.05), "default", true)
        bh = math.min(bh, bodyLineH * BODY_LINES)
        ops[#ops + 1] = { a.body, pad, y, w - pad, y + bh, Theme.text, ui(1.05), "default", true }
        y = y + bh + ui(18)
    end
    return { w = w, h = y - ui(18) + pad, ops = ops }
end

function News.setData(d)
    News.data = type(d) == "table" and d or nil
    cache = nil
end

-- anchor: the visible form panel ({X, Y, W}); called from render.lua
function News.draw(anchor)
    if not (News.data and anchor and anchor.X) then return end
    local w = math.min(ui(WIDTH), anchor.X - ui(GAP) - ui(20))
    if w < ui(260) then return end
    local x = anchor.X - ui(GAP) - w
    if not cache or cache.w ~= w then cache = build(w) end

    local y = anchor.Y
    drawPanelFrame(x, y, w, cache.h, L("acc_ui.news.title"))
    for _, o in ipairs(cache.ops) do
        if o.rule then
            dxDrawRectangle(x + o.x, y + o.y, o.w, 1, Theme.accentDim)
        else
            dxDrawText(o[1], x + o[2], y + o[3], x + o[4], y + o[5], o[6], o[7], o[8], "left", "top", true, o[9])
        end
    end
end

addEvent("acc_ui:news", true)
addEventHandler("acc_ui:news", localPlayer, News.setData)

addEvent("v_locals:onClientLanguageChange")
addEventHandler("v_locals:onClientLanguageChange", root, function() cache = nil end)
