if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Settings card: sits under the visible panel with the same width and holds the
-- music toggle and the language dropdown side by side. The controls themselves
-- live in music.lua / language.lua; this only lays them out.

Settings = {}

local GAP = 18

-- anchor: the visible panel ({X, Y, W, H}); called from render.lua
function Settings.draw(anchor)
    if not (anchor and anchor.X and anchor.H) then return end
    local w = anchor.W
    local x = anchor.X
    local y = anchor.Y + anchor.H + ui(GAP)
    local pad = ui(22)
    local colGap = ui(10)
    local colW = math.floor((w - pad * 2 - colGap) / 2)
    local btnH = ui(38)

    local labelY = y + ui(46) + ui(14)
    local ctrlY  = labelY + ui(20)
    local h      = (ctrlY + btnH) - y + pad

    drawPanelFrame(x, y, w, h, L("v_accounts.ui.settings.title"))
    drawFieldLabel(L("v_accounts.ui.settings.music"), x + pad, labelY, colW)
    drawFieldLabel(L("v_accounts.ui.settings.language"), x + pad + colW + colGap, labelY, colW)

    if Music then Music.drawToggle(x + pad, ctrlY, colW, btnH) end
    if Lang then Lang.draw(x + pad + colW + colGap, ctrlY, colW, btnH) end -- last: its list opens over everything
end
