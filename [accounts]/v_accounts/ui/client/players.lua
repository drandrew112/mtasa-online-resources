if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Players card: under the Settings card. Top right: current/max players (green);
-- below it a green curve of the last 24 h in 15-minute slots with a transparent
-- green fill under it, and a grey curve of the 24 h before that (same clock
-- times, for comparing the two days). A green slot without data is red and
-- sits at zero; grey gaps are simply not drawn. Hovering the chart shows both
-- values of the slot under the cursor. Data pushed by stats/server/stats.lua.

Players = { data = nil }

local GAP = 18
local GREEN = tocolor(96, 206, 120, 255)
local FILL  = tocolor(96, 206, 120, 45)
local GREY  = tocolor(150, 156, 164, 200)
local RED   = tocolor(232, 96, 96, 255)

function Players.setData(d)
    Players.data = type(d) == "table" and d or nil
end

local function clock(ts)
    local t = getRealTime(ts)
    return ("%02d:%02d"):format(t.hour, t.minute)
end

local function drawTooltip(px, cx, cw, top, i, d, slots, prev)
    local slotT = (d.startT or 0) + (i - 1) * (d.slotSeconds or 900)
    local hm = clock(slotT)
    local function val(v) return v and tostring(v) or "-" end
    local lines = {
        { ("%s %s - %s"):format(L("v_accounts.ui.players.yesterday"), hm, val(prev[i])), GREY },
        { ("%s %s - %s"):format(L("v_accounts.ui.players.today"), hm, val(slots[i])), GREEN },
    }
    local scale, lh, pad = ui(1.0), ui(18), ui(8)
    local tw = 0
    for _, l in ipairs(lines) do tw = math.max(tw, dxGetTextWidth(l[1], scale, "default-bold")) end
    local bw, bh = tw + pad * 2, lh * #lines + pad * 2
    local bx = px + ui(10)
    if bx + bw > cx + cw then bx = px - ui(10) - bw end
    if bx < cx then bx = cx end
    local by = top
    dxDrawRectangle(bx, by, bw, bh, tocolor(10, 12, 16, 235))
    dxDrawRectangle(bx, by, ui(3), bh, Theme.accent)
    for k, l in ipairs(lines) do
        local ly = by + pad + (k - 1) * lh
        dxDrawText(l[1], bx + pad, ly, bx + bw - pad, ly + lh, l[2], scale, "default-bold", "left", "center")
    end
end

-- anchor: the Settings card rect ({X, Y, W, H}); called from render.lua
function Players.draw(anchor)
    if not (Players.data and anchor and anchor.X and anchor.H) then return end
    local d = Players.data
    local x, w = anchor.X, anchor.W
    local y = anchor.Y + anchor.H + ui(GAP)
    local pad = ui(22)
    local h = ui(46) + ui(150)

    drawPanelFrame(x, y, w, h, L("v_accounts.ui.players.title"))
    dxDrawText(("%d/%d"):format(d.current or 0, d.max or 0), x, y, x + w - ui(22), y + ui(46),
        GREEN, ui(1.6), "default-bold", "right", "center")

    local slots = d.slots or {}
    local prev = d.prev or {}
    local count = #slots
    if count < 2 then return end
    local cx, cw = x + pad, w - pad * 2
    local cy, ch = y + ui(46) + ui(18), ui(150) - ui(18) - ui(30)
    local peak = 1
    for _, v in ipairs(slots) do if v and v > peak then peak = v end end
    for i = 1, count do local v = prev[i]; if v and v > peak then peak = v end end
    peak = math.max(peak, 5)

    local base = cy + ch
    dxDrawRectangle(cx, base, cw, 1, Theme.accentDim) -- baseline
    local step = cw / (count - 1)
    local function px(i) return cx + (i - 1) * step end
    local function py(v) return base - ((v or 0) / peak) * ch end

    -- previous 24 h (grey), behind everything
    for i = 1, count - 1 do
        if prev[i] and prev[i + 1] then
            dxDrawLine(px(i), py(prev[i]), px(i + 1), py(prev[i + 1]), GREY, ui(1.5))
        end
    end

    -- transparent green fill under the green curve
    for i = 1, count - 1 do
        if slots[i] and slots[i + 1] then
            local x1, y1, x2, y2 = px(i), py(slots[i]), px(i + 1), py(slots[i + 1])
            dxDrawPrimitive("trianglelist", false,
                x1, y1, FILL, x2, y2, FILL, x1, base, FILL,
                x2, y2, FILL, x2, base, FILL, x1, base, FILL)
        end
    end

    for i = 1, count - 1 do
        -- red where either end has no data
        local missing = not slots[i] or not slots[i + 1]
        dxDrawLine(px(i), py(slots[i]), px(i + 1), py(slots[i + 1]), missing and RED or GREEN, ui(2))
    end

    -- time labels: -24h .. now
    local fy = base + ui(6)
    dxDrawText("-24h", cx, fy, cx + ui(60), fy + ui(16), Theme.label, ui(1.0), "default", "left", "top")
    dxDrawText("-12h", cx, fy, cx + cw, fy + ui(16), Theme.label, ui(1.0), "default", "center", "top")
    dxDrawText(L("v_accounts.ui.players.now"), cx + cw - ui(60), fy, cx + cw, fy + ui(16), Theme.label, ui(1.0), "default", "right", "top")

    -- hover: nearest slot under the cursor
    local mx, my = getCursorPosition()
    if not mx then return end
    mx, my = mx * sw, my * sh
    if mx < cx - step / 2 or mx > cx + cw + step / 2 or my < cy - ui(6) or my > base + ui(6) then return end
    local i = math.max(1, math.min(count, math.floor((mx - cx) / step + 0.5) + 1))
    local hx = px(i)
    dxDrawRectangle(hx, cy, 1, ch, tocolor(255, 255, 255, 60))
    if prev[i] then dxDrawRectangle(hx - ui(3), py(prev[i]) - ui(3), ui(6), ui(6), GREY) end
    dxDrawRectangle(hx - ui(3), py(slots[i]) - ui(3), ui(6), ui(6), slots[i] and GREEN or RED)
    drawTooltip(hx, cx, cw, cy, i, d, slots, prev)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_accounts:requestStats", localPlayer)
end)

addEvent("v_accounts:stats", true)
addEventHandler("v_accounts:stats", localPlayer, Players.setData)
