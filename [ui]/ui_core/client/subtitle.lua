UI.subtitle = { text = nil, untilTick = 0 }

function UI.subtitle:set(text, duration)
    self.text = text
    self.untilTick = getTickCount() + (duration or 4000)
end

function UI.subtitle:draw()
    if not self.text or getTickCount() > self.untilTick then return end

    -- Centered at 80% of screen height; up to 50% of screen width, wraps beyond.
    local scale = 1.7
    local font = "default-bold"
    local maxW = UI.sw * 0.5
    local textW = dxGetTextWidth(self.text, scale, font, true)
    local w = math.min(textW, maxW)
    local x = (UI.sw - w) / 2
    local lineH = dxGetFontHeight(scale, font)
    local lines = math.max(1, math.ceil(textW / maxW))
    local top = UI.sh * 0.9 - lineH / 2
    local bottom = top + lineH * lines

    -- Shadow for legibility, then text.
    dxDrawText(self.text, x + 1, top + 1, x + w + 1, bottom + 1,
        tocolor(0, 0, 0, 220), scale, font, "center", "top",
        false, true, false, true)
    dxDrawText(self.text, x, top, x + w, bottom,
        tocolor(255, 255, 255, 240), scale, font, "center", "top",
        false, true, false, true)
end
