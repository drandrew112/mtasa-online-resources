UI.alert = {
    active = false,
    text = nil,
    r = 255,
    g = 255,
    b = 255,
    startTick = 0,
    duration = 5000,
    fadeTime = 400,
}

local function getAlpha()
    local elapsed = getTickCount() - UI.alert.startTick

    if elapsed < UI.alert.fadeTime then
        return elapsed / UI.alert.fadeTime * 255
    end

    if elapsed > UI.alert.duration - UI.alert.fadeTime then
        return (UI.alert.duration - elapsed) / UI.alert.fadeTime * 255
    end

    return 255
end

function UI.alert:set(text, r, g, b, duration)
    self.text = text
    self.r = r ~= nil and r or 255
    self.g = g ~= nil and g or 255
    self.b = b ~= nil and b or 255
    self.duration = duration or 5000
    self.startTick = getTickCount()
    self.active = true
end

function UI.alert:draw()
    if not self.active then return end
    if not self.text then return end

    local now = getTickCount()
    if now > self.startTick + self.duration then
        self.active = false
        return
    end

    local alpha = math.max(0, math.min(255, getAlpha()))
    local s = UI.slots.alert

    local scale = ui(1.2)

    dxDrawText(
        self.text,
        0, s.y - ui(30),
        UI.sw, s.y + ui(30),
        tocolor(self.r, self.g, self.b, alpha),
        scale, "default-bold", "center", "center",
        false, false, false, true
    )
end
