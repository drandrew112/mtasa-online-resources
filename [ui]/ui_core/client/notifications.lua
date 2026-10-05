local sw, sh = UI.sw, UI.sh 

-- Notifications

UI.notifications = {}

UI.notification = {
    width    = ui(340),
    padding  = ui(10),
    spacing  = ui(10),
    gap      = ui(4),
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

-- Sortörés: szavanként próbálja összerakni a sorokat úgy, hogy beférjenek
-- maxWidth-be. A \n-eket a szöveg külön bekezdéseiként kezeli.
local function wrapText(text, font, scale, maxWidth)
    local lines = {}
    if not text or text == "" then return lines end

    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local words = {}
        for word in paragraph:gmatch("%S+") do
            words[#words + 1] = word
        end

        if #words == 0 then
            lines[#lines + 1] = ""
        else
            local current = words[1]
            for i = 2, #words do
                local candidate = current .. " " .. words[i]
                if dxGetTextWidth(candidate, scale, font, true) <= maxWidth then
                    current = candidate
                else
                    lines[#lines + 1] = current
                    current = words[i]
                end
            end
            lines[#lines + 1] = current
        end
    end

    return lines
end

-- silent = true skips the notify sound (the caller plays its own).
function UI:addNotification(title, text, silent)
    if not silent then
        local s = playSound("client/sounds/notify.wav")
        if s then setSoundVolume(s, 0.4) end
    end

    local cfg = self.notification
    local innerWidth = cfg.width - cfg.padding * 2

    local titleLines = wrapText(title or "", "default-bold", cfg.titleSize, innerWidth)
    local textLines  = wrapText(text or "", "default", cfg.textSize, innerWidth)

    local titleLineH = dxGetFontHeight(cfg.titleSize, "default-bold")
    local textLineH  = dxGetFontHeight(cfg.textSize, "default")

    local contentH = #titleLines * titleLineH
    if #textLines > 0 then
        contentH = contentH + cfg.gap + #textLines * textLineH
    end

    local height = math.max(cfg.minH, cfg.padding * 2 + contentH)

    table.insert(self.notifications, {
        titleLines = titleLines,
        textLines  = textLines,
        titleLineH = titleLineH,
        textLineH  = textLineH,
        height     = height,
        startTick = getTickCount(),
        duration  = self.notification.duration,
        fadeTime  = self.notification.fadeTime
    })
end

function UI:drawNotifications()
    local now = getTickCount()
    local cfg = self.notification

    local x = UI.safe.x
    local baseY = sh - UI.safe.y - ui(230)
    local w = cfg.width

    -- lejárt értesítések törlése
    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        if now - n.startTick >= n.duration then
            table.remove(self.notifications, i)
        end
    end

    -- alulról felfelé rajzolás, mindegyik a saját (szöveg alapján eltérő) magasságával
    local offset = 0
    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        local alpha = getNotificationAlpha(n)
        local h = n.height
        local y = baseY - offset - h

        if alpha > 0 then
            -- háttér
            dxDrawRectangle(
                x,
                y,
                w,
                h,
                tocolor(20, 20, 20, alpha * 0.85)
            )

            local textY = y + cfg.padding

            -- cím (1.4), soronként
            for _, line in ipairs(n.titleLines) do
                dxDrawText(
                    line,
                    x + cfg.padding,
                    textY,
                    x + w - cfg.padding,
                    textY + n.titleLineH,
                    tocolor(255, 255, 255, alpha),
                    cfg.titleSize,
                    "default-bold",
                    "left",
                    "top",
                    true, false, false, true
                )
                textY = textY + n.titleLineH
            end

            -- szöveg (1.2), soronként
            if #n.textLines > 0 then
                textY = textY + cfg.gap
                for _, line in ipairs(n.textLines) do
                    dxDrawText(
                        line,
                        x + cfg.padding,
                        textY,
                        x + w - cfg.padding,
                        textY + n.textLineH,
                        tocolor(220, 220, 220, alpha),
                        cfg.textSize,
                        "default",
                        "left",
                        "top",
                        true, false, false, true
                    )
                    textY = textY + n.textLineH
                end
            end
        end

        -- a magasságot akkor is számoljuk, ha épp nem látható (fade szélén),
        -- hogy a felette lévő értesítések ne ugorjanak
        offset = offset + h + cfg.spacing
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
