if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Settings card: sits left of the visible panel, top edges aligned, and holds
-- the music toggle and the language dropdown under each other. The controls
-- themselves live in music.lua / language.lua; this only lays them out.

Settings = {}

local WIDTH = 220
local GAP   = 24

-- anchor: the visible panel ({X, Y, W}); called from render.lua
function Settings.draw(anchor)
    if not (anchor and anchor.X) then return end
    local w = ui(WIDTH)
    local x = anchor.X - ui(GAP) - w
    local y = anchor.Y
    local pad = ui(22)
    local cx, fieldW, btnH = x + pad, w - pad * 2, ui(38)

    local musicLabelY = y + ui(46) + ui(16)
    local musicY      = musicLabelY + ui(20)
    local langLabelY  = musicY + btnH + ui(12)
    local langY       = langLabelY + ui(20)
    local h           = (langY + btnH) - y + pad

    drawPanelFrame(x, y, w, h, L("v_accounts.settings.title"))
    drawFieldLabel(L("v_accounts.settings.music"), cx, musicLabelY, fieldW)
    drawFieldLabel(L("v_accounts.settings.language"), cx, langLabelY, fieldW)

    if Music then Music.drawToggle(cx, musicY, fieldW, btnH) end
    if Lang then Lang.draw(cx, langY, fieldW, btnH) end -- last: its list opens over everything
end
