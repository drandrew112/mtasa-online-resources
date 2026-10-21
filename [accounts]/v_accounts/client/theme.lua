-- Shared visual language for every account panel.

Theme = {
    panelBG   = tocolor(16, 19, 24, 240),
    accent    = tocolor(64, 156, 180, 255),
    accentDim = tocolor(64, 156, 180, 45),
    title     = tocolor(255, 255, 255, 255),
    label     = tocolor(146, 158, 170, 255),
    text      = tocolor(228, 233, 238, 255),
    danger    = tocolor(232, 96, 96, 255),
    fieldBG   = tocolor(32, 36, 42, 255),

    -- button background per state: { normal, hover, pressed }
    btnPrimary = { tocolor(40, 118, 136, 255), tocolor(64, 156, 180, 255), tocolor(28, 84, 98, 255) },
    btnGhost   = { tocolor(38, 43, 50, 255),   tocolor(56, 63, 72, 255),   tocolor(28, 32, 38, 255) },
}

-- Draws the shared panel container: drop shadow, body, left accent bar and
-- a header strip with the given title.
function drawPanelFrame(x, y, w, h, titleText)
    dxDrawRectangle(x + ui(7), y + ui(9), w, h, tocolor(0, 0, 0, 130))      -- shadow
    dxDrawRectangle(x, y, w, h, Theme.panelBG)                              -- body
    dxDrawRectangle(x, y, ui(4), h, Theme.accent)                          -- accent bar
    dxDrawRectangle(x, y, w, ui(46), tocolor(255, 255, 255, 10))           -- header tint
    dxDrawRectangle(x + ui(22), y + ui(45), w - ui(44), 1, Theme.accentDim) -- header rule
    dxDrawText(titleText, x + ui(22), y, x + w - ui(16), y + ui(46),
        Theme.title, ui(1.6), "default-bold", "left", "center")
end

-- Draws a small field caption above an input.
function drawFieldLabel(text, x, y, w)
    dxDrawText(text, x, y, x + w, y + ui(16),
        Theme.label, ui(1.2), "default-bold", "left", "center")
end
