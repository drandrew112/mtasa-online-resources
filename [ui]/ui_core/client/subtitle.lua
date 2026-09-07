UI.subtitle = { text = nil, untilTick = 0 }

function UI.subtitle:set(text, duration)
    self.text = text
    self.untilTick = getTickCount() + (duration or 4000)
end

function UI.subtitle:draw()
    if not self.text or getTickCount() > self.untilTick then return end
    local s = UI.slots.bottomCenter

    dxDrawText(
        self.text,
        0, s.y,
        UI.sw, s.y + ui(40),
        tocolor(255,255,255,230),
        1.2, "default-bold", "center", "center",
        false, false, false, true
    )
end
