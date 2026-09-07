local sw, sh = UI.sw, UI.sh 

UI.banner = {
    active = false,
    title = nil,
    text = nil,
    r = 0,
    g = 0,
    b = 0,
    startTick = 0,
    duration = 5000,
    fadeTime = 1000,
}

local function getAlpha()
    local now = getTickCount()
    local elapsed = now - UI.banner.startTick

    if elapsed < UI.banner.fadeTime then
        return elapsed / UI.banner.fadeTime * 255
    end

    if elapsed > UI.banner.duration - UI.banner.fadeTime then
        return (UI.banner.duration - elapsed) / UI.banner.fadeTime * 255
    end

    return 255
end

function UI.banner:set(title, text, r,g,b)
    self.title = title
    self.text = text
    self.r = r and r or (0)
    self.g = g and g or (0)
    self.b = b and b or (0)
    self.startTick = getTickCount()
    self.active = true
end

function UI.banner:draw()
    if not self.active then return end
    if not self.text then return end

    local now = getTickCount()

    if now > self.startTick + self.duration then
        self.active = false
        return
    end

    local alpha = math.max(0, math.min(255, getAlpha()))

    local h = ui(150)

    local a = alpha
    local target_a = 150
    if alpha > target_a then a = target_a end
    
    local vertices = {
        {0, UI.safe.y * 4, tocolor(self.r, self.g, self.b, a)}, -- Bal felső
        {sw, UI.safe.y * 4 - 100/2, tocolor(self.r, self.g, self.b, a)}, -- Jobb felső (feljebb megy)
        {sw, UI.safe.y * 4 + h + 100/2, tocolor(self.r, self.g, self.b, a)}, -- Jobb alsó (lejjebb megy)
        {0, UI.safe.y * 4 + h, tocolor(self.r, self.g, self.b, a)}, -- Bal alsó
    }
    dxDrawPrimitive("trianglefan", true, unpack(vertices))
    --dxDrawRectangle(0, UI.safe.y*3, sw, h, tocolor(0,0,0,a), true)
    dxDrawText(
        self.title,
        sw/2, UI.safe.y*4+h/2+ui(10),
        _,_,
        tocolor(255,255,255,alpha),
        ui(4), "default-bold", "center", "bottom", false, false, true
    )
    dxDrawText(
        self.text,
        sw/2, UI.safe.y*4+h/2+ui(15),
        _,_,
        tocolor(255,255,255,alpha),
        ui(1.7), "default", "center", "top", false, false, true
    )
end

--UI.banner:set("Teszt", "Kapd be a faszt", 100, 100, 160)
