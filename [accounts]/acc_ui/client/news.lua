if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- News card: left of the login/register panel, top edges aligned. Data = the
-- newest v_news articles, pushed by the server (acc_ui:news) with every
-- language; shown in the player's language, else the default one. Display only.
-- Every article is shown in full: as many of the newest as fit the screen
-- height under the card's top edge (the newest one always).

News = { data = nil }

local WIDTH = 560
local GAP   = 24
local BOTTOM_MARGIN = 40 -- free space kept under the card

local cache = nil -- { w, maxH, h, ops }

-- title, body of an article in the current language (else the server's default pick)
local function localized(a)
    local t = type(a.texts) == "table" and a.texts[L.lang()]
    if t then return t.title, t.body end
    return a.title, a.body
end

local function build(w, maxH)
    local pad = ui(22)
    local innerW = w - pad * 2
    local ops = {}
    local y = ui(46) + ui(12)
    local smallH = dxGetFontHeight(ui(1.0), "default")
    local titleH = dxGetFontHeight(ui(1.2), "default-bold")

    if #News.data == 0 then
        ops[#ops + 1] = { L("acc_ui.news.no_news"), pad, y, w - pad, y + ui(24), Theme.label, ui(1.1), "default", false }
        return { w = w, maxH = maxH, h = y + ui(24) + pad, ops = ops }
    end

    for i, a in ipairs(News.data) do
        local title, body = localized(a)
        local _, bh = dxGetTextSize(body, innerW, ui(1.05), "default", true)
        local top = y
        local bodyY = y + smallH + ui(2) + titleH + ui(3)
        -- the newest one always; the others only when they fit whole
        if i > 1 and bodyY + bh + pad > maxH then break end

        if i > 1 then
            ops[#ops + 1] = { rule = true, x = pad, y = top - ui(8), w = innerW }
        end
        ops[#ops + 1] = { a.dateText, pad, top, w - pad, top + smallH, Theme.label, ui(1.0), "default", false }
        local titleY = top + smallH + ui(2)
        ops[#ops + 1] = { title, pad, titleY, w - pad, titleY + titleH, Theme.title, ui(1.2), "default-bold", false }
        ops[#ops + 1] = { body, pad, bodyY, w - pad, bodyY + bh, Theme.text, ui(1.05), "default", true }
        y = bodyY + bh + ui(18)
    end
    return { w = w, maxH = maxH, h = y - ui(18) + pad, ops = ops }
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
    local y = anchor.Y
    local maxH = sh - y - ui(BOTTOM_MARGIN)
    if not cache or cache.w ~= w or cache.maxH ~= maxH then cache = build(w, maxH) end

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
