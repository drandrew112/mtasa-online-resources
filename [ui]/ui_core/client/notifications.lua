local sw, sh = UI.sw, UI.sh 

-- Notifications

UI.notifications = {}

UI.notification = {
    width    = nil,
    padding  = ui(10),
    spacing  = ui(10),
    minH     = ui(30),

    titleSize = ui(1.4),
    textSize  = ui(1.2),

    duration = 5000,
    fadeTime = 500
}

local function getNotificationAlpha(n)
    local now = getTickCount()
    local elapsed = now - n.startTick

    -- fade in
    if elapsed < n.fadeTime then
        return (elapsed / n.fadeTime) * 255
    end

    -- fade out
    if elapsed > n.duration - n.fadeTime then
        return math.max(
            (n.duration - elapsed) / n.fadeTime * 255,
            0
        )
    end

    return 255
end

function UI:addNotification(title, text)
    table.insert(self.notifications, {
        title = title,
        text = text,
        startTick = getTickCount(),
        duration  = self.notification.duration,
        fadeTime  = self.notification.fadeTime
    })
end

function UI:drawNotifications()
    local now = getTickCount()

    local x = UI.safe.x
    local baseY = sh - UI.safe.y - ui(230)

    local w = ui(340)
    local h = ui(50)
    local spacing = ui(5)

    -- lejárt értesítések törlése
    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        if now - n.startTick >= n.duration then
            table.remove(self.notifications, i)
        end
    end

    -- alulról felfelé rajzolás
    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        local alpha = getNotificationAlpha(n)

        if alpha > 0 then
            local offset = (#self.notifications - i) * (h + spacing)
            local y = baseY - offset - h

            -- háttér
            dxDrawRectangle(
                x,
                y,
                w,
                h,
                tocolor(20, 20, 20, alpha * 0.85)
            )

            -- cím (1.4)
            dxDrawText(
                n.title,
                x + ui(10),
                y + ui(6),
                x + w - ui(10),
                y + ui(24),
                tocolor(255, 255, 255, alpha),
                ui(1.4),
                "default-bold",
                "left",
                "top"
            )

            -- szöveg (1.2)
            dxDrawText(
                n.text,
                x + ui(10),
                y + ui(26),
                x + w - ui(10),
                y + h - ui(6),
                tocolor(220, 220, 220, alpha),
                ui(1.2),
                "default",
                "left",
                "top",
                true,
                true
            )
        end
    end
end


-- Loading text

local sx, sy = guiGetScreenSize()
local loadingTex = dxCreateTexture("client/images/loading.png")

local loadingStart = getTickCount()

function UI:drawLoading(text)
    local h = 25*ui(1.7)
    local w = dxGetTextWidth(text, ui(1.7), "default", true)+10+h
    -- background
    dxDrawRectangle(UI.slots.bottomRight.x-w, UI.slots.bottomRight.y-h, w, h, tocolor(0,0,0,160))
    -- icon
    if not loadingTex then return end

    speed = speed or 180 -- fok / másodperc

    local now = getTickCount()
    local elapsed = (now - loadingStart) / 1000
    local rotation = elapsed * speed

    dxDrawImage(
        UI.slots.bottomRight.x-h+2-5, UI.slots.bottomRight.y-h+2,
        h-2, h-2,
        loadingTex,
        rotation,
        0, 0,
        tocolor(255, 255, 255, 255)
    )
    -- text
    dxDrawText( text, UI.slots.bottomRight.x-w+5, UI.slots.bottomRight.y-(h/2), _,_, tocolor(255,255,255), ui(1.7), "default", "left", "center", false,false,false,true)    
end
