if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- News card: left of the login/register panel, top edges aligned, down to the
-- bottom of the screen. Data = the v_news articles of the last 7 days, pushed
-- by the server (acc_ui:news) with every language; shown in the player's
-- language, else the default one. Display only.
-- Every article is shown in full; the list scrolls with the mouse wheel while
-- the cursor is over the card.

News = { data = nil }

local WIDTH = 780
local GAP   = 24
local BOTTOM_MARGIN = 40 -- free space kept under the card
local SCROLL_STEP   = 60 -- px per wheel tick (ui-scaled)

local cache  = nil -- { w, h, viewH, contentH, ops }
local target = nil -- render target the list is clipped into
local rect   = nil -- where the card was drawn this frame (wheel hit test)
local scroll, scrollGoal = 0, 0

-- title, body of an article in the current language (else the server's default pick)
local function localized(a)
    local t = type(a.texts) == "table" and a.texts[L.lang()]
    if t then return t.title, t.body end
    return a.title, a.body
end

-- ops in list coordinates (0 = top of the scroll view)
local function build(w, h)
    local pad = ui(22)
    local innerW = w - pad * 2
    local viewH = h - ui(52) - ui(12)
    local ops = {}
    local y = ui(6)
    local smallH = dxGetFontHeight(ui(1.0), "default")
    local titleH = dxGetFontHeight(ui(1.2), "default-bold")

    if #News.data == 0 then
        ops[#ops + 1] = { L("acc_ui.news.no_news"), pad, y, w - pad, y + ui(24), Theme.label, ui(1.1), "default", false }
        return { w = w, h = h, viewH = viewH, contentH = y + ui(24), ops = ops }
    end

    for i, a in ipairs(News.data) do
        local title, body = localized(a)
        local _, bh = dxGetTextSize(body, innerW, ui(1.05), "default", true)
        local top = y
        local bodyY = y + smallH + ui(2) + titleH + ui(3)

        if i > 1 then
            ops[#ops + 1] = { rule = true, x = pad, y = top - ui(8), w = innerW }
        end
        ops[#ops + 1] = { a.dateText, pad, top, w - pad, top + smallH, Theme.label, ui(1.0), "default", false }
        local titleY = top + smallH + ui(2)
        ops[#ops + 1] = { title, pad, titleY, w - pad, titleY + titleH, Theme.title, ui(1.2), "default-bold", false }
        ops[#ops + 1] = { body, pad, bodyY, w - pad, bodyY + bh, Theme.text, ui(1.05), "default", true }
        y = bodyY + bh + ui(18)
    end
    return { w = w, h = h, viewH = viewH, contentH = y - ui(18) + ui(6), ops = ops }
end

local function maxScroll()
    return cache and math.max(0, cache.contentH - cache.viewH) or 0
end

function News.setData(d)
    News.data = type(d) == "table" and d or nil
    cache = nil
    scroll, scrollGoal = 0, 0
end

-- anchor: the visible form panel ({X, Y, W}); called from render.lua
function News.draw(anchor)
    rect = nil
    if not (News.data and anchor and anchor.X) then return end
    local w = math.min(ui(WIDTH), anchor.X - ui(GAP) - ui(20))
    if w < ui(260) then return end
    local x = anchor.X - ui(GAP) - w
    local y = anchor.Y
    local h = sh - y - ui(BOTTOM_MARGIN)
    if h < ui(120) then return end
    if not cache or cache.w ~= w or cache.h ~= h then cache = build(w, h) end

    local viewW, viewH = math.floor(w), math.floor(cache.viewH)
    if target and (target.w ~= viewW or target.h ~= viewH) then
        destroyElement(target.rt)
        target = nil
    end
    if not target then
        local rt = dxCreateRenderTarget(viewW, viewH, true)
        if rt then target = { rt = rt, w = viewW, h = viewH } end
    end

    local maxS = maxScroll()
    scrollGoal = math.max(0, math.min(maxS, scrollGoal))
    scroll = scroll + (scrollGoal - scroll) * 0.25
    if math.abs(scrollGoal - scroll) < 0.5 then scroll = scrollGoal end

    drawPanelFrame(x, y, w, h, L("acc_ui.news.title"))
    rect = { x = x, y = y, w = w, h = h }
    if not target then return end

    local viewY = y + ui(52)
    local off = math.floor(scroll)
    dxSetRenderTarget(target.rt, true)
    dxSetBlendMode("modulate_add")
    for _, o in ipairs(cache.ops) do
        local top, bottom = o.rule and o.y or o[3], o.rule and o.y + 1 or o[5]
        if bottom - off >= 0 and top - off <= viewH then
            if o.rule then
                dxDrawRectangle(o.x, o.y - off, o.w, 1, Theme.accentDim)
            else
                dxDrawText(o[1], o[2], o[3] - off, o[4], o[5] - off, o[6], o[7], o[8], "left", "top", false, o[9])
            end
        end
    end
    dxSetBlendMode("blend")
    dxSetRenderTarget()

    dxSetBlendMode("add")
    dxDrawImage(x, viewY, viewW, viewH, target.rt)
    dxSetBlendMode("blend")

    -- scrollbar
    if maxS > 0 then
        local barH = math.max(ui(30), viewH * viewH / cache.contentH)
        local barY = viewY + (viewH - barH) * (scroll / maxS)
        dxDrawRectangle(x + w - ui(9), viewY, ui(3), viewH, tocolor(255, 255, 255, 18))
        dxDrawRectangle(x + w - ui(9), barY, ui(3), barH, Theme.accent)
    end
end

addEventHandler("onClientKey", root, function(key, press)
    if not press or (key ~= "mouse_wheel_up" and key ~= "mouse_wheel_down") then return end
    if not (rect and cache and isCursorShowing()) then return end
    local cx, cy = getCursorPosition()
    if not cx then return end
    local mx, my = cx * sw, cy * sh
    if mx < rect.x or mx > rect.x + rect.w or my < rect.y or my > rect.y + rect.h then return end
    local dir = key == "mouse_wheel_down" and 1 or -1
    scrollGoal = math.max(0, math.min(maxScroll(), scrollGoal + dir * ui(SCROLL_STEP)))
end)

addEvent("acc_ui:news", true)
addEventHandler("acc_ui:news", localPlayer, News.setData)

addEvent("v_locals:onClientLanguageChange")
addEventHandler("v_locals:onClientLanguageChange", root, function() cache = nil end)
