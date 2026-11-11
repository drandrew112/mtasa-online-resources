if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
local sw, sh = UI.sw, UI.sh 

-- Notifications
--
-- Two kinds, one column in the bottom-left corner:
--   * normal notifications (UI:addNotification): title + text, NOTIFY_DURATION ms, stacked above the pinned ones
--   * pinned notifications (UI:addPinned): title / subtitle / description / hint, they stay PINNED_FACTOR times
--     longer (at least) or forever (infinite) until the owner removes them by export. Always at the bottom of the
--     column; every normal notification appears above them. Several can be active at once.
-- ui_core only draws: the keys / buttons a pinned notification talks about (hint) are handled by the caller.
--
-- Colours: every text may contain inline #RRGGBB codes (also kept across wrapped lines); the base colour of each text
-- and the background can be given as "#RRGGBB" / "#RRGGBBAA" (or { r, g, b [, a] }).

UI.notifications = {}
UI.pinned = {}          -- ordered list (oldest first)
local pinnedById = {}

UI.notification = {
    width    = ui(340),
    padding  = ui(10),
    spacing  = ui(10),
    gap      = ui(4),
    minH     = ui(30),

    titleSize = ui(1.4),
    textSize  = ui(1.2),

    duration = 10000,   -- 2x the old 5000 (2026-11-11)
    fadeTime = 500,

    bg        = { 20, 20, 20, 217 },
    titleColor = { 255, 255, 255, 255 },
    textColor  = { 220, 220, 220, 255 },
}

UI.pinnedCfg = {
    factor       = 5,       -- pinned duration = factor x notification duration (also the minimum)
    subtitleSize = ui(1.25),
    hintSize     = ui(1.1),
    accentW      = ui(4),
    barH         = ui(3),

    bg            = { 14, 18, 26, 235 },
    accent        = { 70, 140, 255, 255 },
    titleColor    = { 255, 255, 255, 255 },
    subtitleColor = { 200, 210, 225, 255 },
    descColor     = { 220, 220, 220, 255 },
    hintColor     = { 150, 160, 175, 255 },
    barColor      = { 240, 200, 60, 255 },
    lineColor     = { 255, 255, 255, 40 },
}

function UI:getPinnedDuration()
    return self.notification.duration * self.pinnedCfg.factor
end

------------------------------------------------------------------------ helpers

-- "#RRGGBB", "#RRGGBBAA", "RRGGBB" or { r, g, b [, a] } -> { r, g, b, a } (nil when not a colour)
local function parseColor(c)
    if type(c) == "table" then
        local r, g, b = tonumber(c[1] or c.r), tonumber(c[2] or c.g), tonumber(c[3] or c.b)
        if not (r and g and b) then return nil end
        return { r, g, b, tonumber(c[4] or c.a) or 255 }
    end
    if type(c) ~= "string" then return nil end
    local hex = c:gsub("^#", "")
    if not hex:match("^%x+$") or (#hex ~= 6 and #hex ~= 8) then return nil end
    return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16),
             #hex == 8 and tonumber(hex:sub(7, 8), 16) or 255 }
end
UI.parseColor = parseColor

local function col(c, alpha)
    return tocolor(c[1], c[2], c[3], (c[4] or 255) * alpha / 255)
end

local function fadeAlpha(n, now)
    local elapsed = now - n.startTick
    local a = 255
    if not n.noFadeIn and elapsed < n.fadeTime then a = elapsed / n.fadeTime * 255 end
    local endTick = n.removeTick or (n.duration and n.startTick + n.duration)
    if endTick then
        local left = endTick - now
        if left < n.fadeTime then a = math.min(a, math.max(left, 0) / n.fadeTime * 255) end
    end
    return a
end

-- Word wrap to maxWidth; \n = new paragraph. The last inline #RRGGBB code of a line is carried to the next line so
-- a coloured sentence keeps its colour when it wraps.
local function wrapText(text, font, scale, maxWidth)
    local lines = {}
    if not text or text == "" then return lines end

    local carry = ""
    local function push(line)
        lines[#lines + 1] = carry .. line
        local last
        for code in line:gmatch("#%x%x%x%x%x%x") do last = code end
        if last then carry = last end
    end

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
                if L.width(candidate, scale, font, true) <= maxWidth then
                    current = candidate
                else
                    push(current)
                    current = words[i]
                end
            end
            push(current)
        end
    end

    return lines
end

local function drawLines(lines, x, y, w, lineH, color, size, font)
    for _, line in ipairs(lines) do
        dxDrawText(line, x, y, x + w, y + lineH, color, size, font, "left", "top", true, false, false, true)
        y = y + lineH
    end
    return y
end

local function playNotify()
    local s = playSound("client/sounds/notify.wav")
    if s then setSoundVolume(s, 0.4) end
end

------------------------------------------------------------------------ normal notifications

-- silent = true skips the notify sound (the caller plays its own).
-- opts (optional): { bg = colour, titleColor = colour, textColor = colour }
function UI:addNotification(title, text, silent, opts)
    opts = type(opts) == "table" and opts or {}
    if not silent then playNotify() end

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
        bg         = parseColor(opts.bg) or cfg.bg,
        titleColor = parseColor(opts.titleColor) or cfg.titleColor,
        textColor  = parseColor(opts.textColor) or cfg.textColor,
        startTick = getTickCount(),
        duration  = cfg.duration,
        fadeTime  = cfg.fadeTime
    })
end

------------------------------------------------------------------------ pinned notifications

local pinnedSeq = 0
local FIELDS = { "title", "subtitle", "description", "hint" }
local STYLE = { "bg", "accent", "titleColor", "subtitleColor", "descColor", "hintColor", "barColor" }

-- the lines + height of a pinned notification (after any text / style change)
local function layoutPinned(n)
    local cfg, pc = UI.notification, UI.pinnedCfg
    local accentW = n.style.accent and pc.accentW or 0
    local inner = cfg.width - cfg.padding * 2 - accentW
    n.inner = inner

    n.titleLines = wrapText(n.title or "", "default-bold", cfg.titleSize, inner)
    n.subLines   = wrapText(n.subtitle or "", "default-bold", pc.subtitleSize, inner)
    n.descLines  = wrapText(n.description or "", "default", cfg.textSize, inner)
    n.hintLines  = wrapText(n.hint or "", "default", pc.hintSize, inner)

    n.titleH = dxGetFontHeight(cfg.titleSize, "default-bold")
    n.subH   = dxGetFontHeight(pc.subtitleSize, "default-bold")
    n.descH  = dxGetFontHeight(cfg.textSize, "default")
    n.hintH  = dxGetFontHeight(pc.hintSize, "default")

    local h, blocks = 0, 0
    local function block(count, lineH, extraGap)
        if count == 0 then return end
        if blocks > 0 then h = h + cfg.gap + (extraGap or 0) end
        h = h + count * lineH
        blocks = blocks + 1
    end
    block(#n.titleLines, n.titleH)
    block(#n.subLines, n.subH)
    block(#n.descLines, n.descH, cfg.gap)
    block(#n.hintLines, n.hintH, cfg.gap * 2)   -- separator line above the hint

    n.height = math.max(cfg.minH, cfg.padding * 2 + h + (n.countdown and pc.barH or 0))
end

local function applyOpts(n, opts, isNew)
    for _, f in ipairs(FIELDS) do
        if opts[f] ~= nil then n[f] = opts[f] ~= false and tostring(opts[f]) or nil end
    end
    n.style = n.style or {}
    local pc = UI.pinnedCfg
    for _, k in ipairs(STYLE) do
        if opts[k] ~= nil then
            if k == "accent" and opts[k] == false then
                n.style.accent = false
            else
                n.style[k] = parseColor(opts[k]) or (isNew and pc[k]) or n.style[k]
            end
        elseif isNew then
            n.style[k] = pc[k]
        end
    end
    -- lifetime: infinite (only removed by export) or at least factor x notification duration
    local now = getTickCount()
    if isNew or opts.duration ~= nil or opts.infinite ~= nil then
        local infinite = opts.infinite == true or opts.duration == false or tonumber(opts.duration) == -1
        if infinite then
            n.duration = nil
        else
            local minimum = UI:getPinnedDuration()
            n.duration = math.max(minimum, tonumber(opts.duration) or minimum)
            if not isNew then n.duration = n.duration + (now - n.startTick) end -- restart from now
        end
    end
    -- countdown bar: ms from now (shrinks to 0); false removes it
    if opts.countdown ~= nil then
        local ms = tonumber(opts.countdown)
        n.countdown = (ms and ms > 0) and { from = now, total = tonumber(opts.countdownTotal) or ms, left = ms } or nil
    end
    layoutPinned(n)
end

-- opts: see exports.lua. Returns the id.
function UI:addPinned(opts, owner)
    opts = type(opts) == "table" and opts or {}
    local id = opts.id and tostring(opts.id)
    if not id then
        pinnedSeq = pinnedSeq + 1
        id = "pinned" .. pinnedSeq
    end
    local n = pinnedById[id]
    if n and not n.removeTick then
        -- replace in place: keeps its slot, no fade-in again, timer restarts
        n.startTick, n.noFadeIn = getTickCount(), true
        for _, f in ipairs(FIELDS) do n[f] = nil end
        n.style = nil
        applyOpts(n, opts, true)
    else
        if n then self:removePinned(id, true) end
        n = { id = id, owner = owner, startTick = getTickCount(), fadeTime = self.notification.fadeTime }
        applyOpts(n, opts, true)
        table.insert(self.pinned, n)
        pinnedById[id] = n
    end
    n.owner = owner or n.owner
    if not opts.silent then playNotify() end
    return id
end

function UI:updatePinned(id, opts)
    local n = pinnedById[tostring(id)]
    if not n or n.removeTick or type(opts) ~= "table" then return false end
    applyOpts(n, opts, false)
    return true
end

-- instant = true drops it without the fade-out
function UI:removePinned(id, instant)
    id = tostring(id)
    local n = pinnedById[id]
    if not n then return false end
    pinnedById[id] = nil
    if instant then
        for i = #self.pinned, 1, -1 do
            if self.pinned[i] == n then table.remove(self.pinned, i) end
        end
    else
        local now = getTickCount()
        n.removeTick = now + math.min(n.fadeTime, math.max(0, now - n.startTick))
    end
    return true
end

function UI:isPinned(id)
    local n = pinnedById[tostring(id)]
    return n ~= nil and not n.removeTick
end

function UI:getPinnedIds(owner)
    local out = {}
    for _, n in ipairs(self.pinned) do
        if not n.removeTick and (not owner or n.owner == owner) then out[#out + 1] = n.id end
    end
    return out
end

-- every pinned notification of a resource (owner = resource name); nil = all
function UI:clearPinned(owner, instant)
    local count = 0
    for _, id in ipairs(self:getPinnedIds(owner)) do
        if self:removePinned(id, instant) then count = count + 1 end
    end
    return count
end

-- a stopping resource takes its pinned notifications with it
addEventHandler("onClientResourceStop", root, function(res)
    if res ~= resource then UI:clearPinned(getResourceName(res), true) end
end)

local function drawPinned(n, x, y, w, alpha, now)
    local cfg, pc, st = UI.notification, UI.pinnedCfg, n.style
    local h = n.height
    dxDrawRectangle(x, y, w, h, col(st.bg, alpha))
    local tx = x + cfg.padding
    if st.accent then
        dxDrawRectangle(x, y, pc.accentW, h, col(st.accent, alpha))
        tx = tx + pc.accentW
    end
    local iw = n.inner
    local ty = y + cfg.padding
    local blocks = 0
    local function gap(extra)
        if blocks > 0 then ty = ty + cfg.gap + (extra or 0) end
        blocks = blocks + 1
    end
    if #n.titleLines > 0 then
        gap(); ty = drawLines(n.titleLines, tx, ty, iw, n.titleH, col(st.titleColor, alpha), cfg.titleSize, "default-bold")
    end
    if #n.subLines > 0 then
        gap(); ty = drawLines(n.subLines, tx, ty, iw, n.subH, col(st.subtitleColor, alpha), pc.subtitleSize, "default-bold")
    end
    if #n.descLines > 0 then
        gap(cfg.gap); ty = drawLines(n.descLines, tx, ty, iw, n.descH, col(st.descColor, alpha), cfg.textSize, "default")
    end
    if #n.hintLines > 0 then
        if blocks > 0 then
            ty = ty + cfg.gap
            dxDrawRectangle(tx, ty, iw, 1, col(pc.lineColor, alpha))
            ty = ty + cfg.gap
        end
        gap(); ty = drawLines(n.hintLines, tx, ty, iw, n.hintH, col(st.hintColor, alpha), pc.hintSize, "default")
    end
    if n.countdown then
        local c = n.countdown
        local left = math.max(0, c.left - (now - c.from))
        local bx = x + (st.accent and pc.accentW or 0)
        local bw = (w - (bx - x)) * math.min(1, left / math.max(1, c.total))
        dxDrawRectangle(bx, y + h - pc.barH, bw, pc.barH, col(st.barColor, alpha))
    end
end

------------------------------------------------------------------------ drawing

function UI:drawNotifications()
    local now = getTickCount()
    local cfg = self.notification

    local x = UI.safe.x
    local baseY = sh - UI.safe.y - ui(230)
    local w = cfg.width

    -- expired ones out
    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        if now - n.startTick >= n.duration then
            table.remove(self.notifications, i)
        end
    end
    for i = #self.pinned, 1, -1 do
        local n = self.pinned[i]
        local endTick = n.removeTick or (n.duration and n.startTick + n.duration)
        if endTick and now >= endTick then
            table.remove(self.pinned, i)
            if pinnedById[n.id] == n then pinnedById[n.id] = nil end
        end
    end

    -- the pinned ones at the bottom (newest lowest), the normal ones above them (newest lowest)
    local offset = 0
    for i = #self.pinned, 1, -1 do
        local n = self.pinned[i]
        local alpha = fadeAlpha(n, now)
        local y = baseY - offset - n.height
        if alpha > 0 then drawPinned(n, x, y, w, alpha, now) end
        offset = offset + n.height + cfg.spacing
    end

    for i = #self.notifications, 1, -1 do
        local n = self.notifications[i]
        local alpha = fadeAlpha(n, now)
        local h = n.height
        local y = baseY - offset - h

        if alpha > 0 then
            dxDrawRectangle(x, y, w, h, col(n.bg, alpha))

            local textY = y + cfg.padding
            textY = drawLines(n.titleLines, x + cfg.padding, textY, w - cfg.padding * 2, n.titleLineH,
                col(n.titleColor, alpha), cfg.titleSize, "default-bold")
            if #n.textLines > 0 then
                drawLines(n.textLines, x + cfg.padding, textY + cfg.gap, w - cfg.padding * 2, n.textLineH,
                    col(n.textColor, alpha), cfg.textSize, "default")
            end
        end

        -- the height counts even while invisible (fade edge) so the ones above do not jump
        offset = offset + h + cfg.spacing
    end
end


-- Loading text

local sx, sy = guiGetScreenSize()
local loadingTex = dxCreateTexture("client/images/loading.png")

local loadingStart = getTickCount()

function UI:drawLoading(text)
    local h = 25*ui(1.7)
    local w = L.width(text, ui(1.7), "default", true)+10+h
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
