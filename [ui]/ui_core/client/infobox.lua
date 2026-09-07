UI.infobox = {
    active = false,
    text = nil,
    r = 255,
    g = 255,
    b = 255,
    startTick = 0,
    duration = 5000,
    fadeTime = 300,
}

local function getAlpha()
    local now = getTickCount()
    local elapsed = now - UI.infobox.startTick

    if elapsed < UI.infobox.fadeTime then
        return elapsed / UI.infobox.fadeTime * 255
    end

    if elapsed > UI.infobox.duration - UI.infobox.fadeTime then
        return (UI.infobox.duration - elapsed) / UI.infobox.fadeTime * 255
    end

    return 255
end

function UI.infobox:set(text, r, g, b)
    local s = playSound("client/sounds/infobox.wav")
    if s then setSoundVolume(s, 1.0) end

    self.text = text
    self.r = r ~= nil and r or 255
    self.g = g ~= nil and g or 255
    self.b = b ~= nil and b or 255
    self.startTick = getTickCount()
    self.active = true
end

function UI.infobox:draw()
    if not self.active then return end
    if not self.text then return end

    local now = getTickCount()
    if now > self.startTick + self.duration then
        self.active = false
        return
    end

    local alpha = math.max(0, math.min(255, getAlpha()))
    local s = UI.slots.topLeft
        
    local h = 20*ui(1.7)
    local w = dxGetTextWidth(self.text, ui(1.7), "default-bold", true)+10
    outputDebugString(w.." - "..h)

    local a = alpha
    local target_a = 160
    if alpha > target_a then a = target_a end

    dxDrawRectangle(s.x, s.y, w, h, tocolor(0,0,0,a), true)
    dxDrawText(
        self.text,
        s.x + 5, s.y + 5,
        _,_,
        tocolor(self.r, self.g, self.b, alpha),
        ui(1.7), "default-bold", "left", "top", false, false, false, true
    )
end
