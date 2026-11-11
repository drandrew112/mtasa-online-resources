if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Players card: under the Settings card. Top right: current/max players (green);
-- below it a green curve of the last 12 h in 30-minute slots. A slot without
-- data is red and sits at zero. Data pushed by stats/server/stats.lua.

Players = { data = nil }

local GAP = 18
local GREEN = tocolor(96, 206, 120, 255)
local RED   = tocolor(232, 96, 96, 255)

function Players.setData(d)
    Players.data = type(d) == "table" and d or nil
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
    local count = #slots
    if count < 2 then return end
    local cx, cw = x + pad, w - pad * 2
    local cy, ch = y + ui(46) + ui(18), ui(150) - ui(18) - ui(30)
    local peak = 1
    for _, v in ipairs(slots) do if v and v > peak then peak = v end end
    peak = math.max(peak, 5)

    dxDrawRectangle(cx, cy + ch, cw, 1, Theme.accentDim) -- baseline
    local step = cw / (count - 1)
    local function pt(i) return cx + (i - 1) * step, cy + ch - ((slots[i] or 0) / peak) * ch end

    for i = 1, count - 1 do
        local x1, y1 = pt(i)
        local x2, y2 = pt(i + 1)
        -- red where either end has no data
        local missing = not slots[i] or not slots[i + 1]
        dxDrawLine(x1, y1, x2, y2, missing and RED or GREEN, ui(2))
    end

    -- time labels: -12h .. now
    local fy = cy + ch + ui(6)
    dxDrawText("-12h", cx, fy, cx + ui(60), fy + ui(16), Theme.label, ui(1.0), "default", "left", "top")
    dxDrawText("-6h", cx, fy, cx + cw, fy + ui(16), Theme.label, ui(1.0), "default", "center", "top")
    dxDrawText(L("v_accounts.ui.players.now"), cx + cw - ui(60), fy, cx + cw, fy + ui(16), Theme.label, ui(1.0), "default", "right", "top")
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_accounts:requestStats", localPlayer)
end)

addEvent("v_accounts:stats", true)
addEventHandler("v_accounts:stats", localPlayer, Players.setData)
