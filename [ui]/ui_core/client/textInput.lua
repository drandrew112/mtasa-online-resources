if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Reusable modal text-input overlay (fully DX drawn).
--
-- Other resources open it through the exports below and get the result back as
-- an event (MTA cannot pass functions across a resource boundary):
--
--   local token = exports.ui_core:openTextInput("License plate", 8, "OLD PLATE")
--   addEvent("ui_core:textInputResult")
--   addEventHandler("ui_core:textInputResult", root, function(t, text)
--       if t ~= token then return end
--       -- text == false  -> cancelled
--   end)
--
-- Layout follows the character limit: when maxLength would not fit on one line
-- the field becomes a multi-line box (word wrapped, up to MAX_ROWS visible rows,
-- scrolls with the caret). The text itself never contains newlines.
--
-- While it is open every bind of every resource is off:
--   * guiSetInputMode("no_binds")       -> no bindKey / command bind fires
--   * every keyboard onClientKey is cancelled at "high+100" priority, so GTA
--     controls, the MTA menu (Esc) and well-behaved onClientKey handlers
--     (wasEventCancelled) do not react; characters still arrive through
--     onClientCharacter / onClientPaste
--   * "textInputOpen" element data is set for panels that gate on flags.

local MAX_ROWS   = 6
local FONT       = "default"
local FONT_BOLD  = "default-bold"
local REPEAT_DELAY, REPEAT_RATE = 400, 35

local COL = {
    dim      = { 0, 0, 0, 160 },
    shadow   = { 0, 0, 0, 70 },
    card     = { 17, 19, 24, 245 },
    field    = { 27, 30, 37, 255 },
    border   = { 52, 57, 68, 255 },
    accent   = { 0, 170, 220, 255 },
    text     = { 236, 239, 244, 255 },
    muted    = { 128, 136, 150, 255 },
    warn     = { 235, 165, 50, 255 },
    full     = { 230, 75, 75, 255 },
    sel      = { 0, 170, 220, 90 },
    btn      = { 36, 40, 49, 255 },
    btnHover = { 48, 53, 64, 255 },
    chip     = { 0, 0, 0, 90 },
}

local function col(c, a)
    return tocolor(c[1], c[2], c[3], c[4] * (a or 1))
end

UI.textInput = {
    active      = false,
    title       = "",
    placeholder = "",
    token       = nil,
    maxLen      = 32,
    chars       = {},     -- utf8 characters
    caret       = 0,      -- 0..#chars (caret sits after chars[caret])
    selAll      = false,
    first       = 0,      -- single line: chars before this index are scrolled off
    top         = 1,      -- multi line: first visible row
    lines       = nil,    -- multi line: { { s, e }, ... }
    L           = nil,    -- layout (sizes), built on open
    openTick    = 0,
    rep         = nil,    -- held key auto-repeat { key, next }
    prevMode    = "allow_binds",
    hits        = {},
}

addEvent("ui_core:textInputResult")

local charW = {}
local function cw(ch, scale)
    local key = ch .. "|" .. scale
    local w = charW[key]
    if not w then
        w = L.width(ch, scale, FONT)
        charW[key] = w
    end
    return w
end

local function sub(chars, i, j)
    if j < i then return "" end
    return table.concat(chars, "", i, j)
end

local function width(ti, i, j)
    if j < i then return 0 end
    return L.width(sub(ti.chars, i, j), ti.L.fs, FONT)
end

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------

local function buildLayout(maxLen)
    local lay = {}
    lay.fs     = ui(1.25)
    lay.ts     = ui(1.35)
    lay.ss     = ui(1.0)
    lay.w      = math.min(ui(640), UI.sw - ui(40))
    lay.pad    = ui(22)
    lay.fpad   = ui(12)
    lay.lineH  = dxGetFontHeight(lay.fs, FONT) + ui(4)
    lay.titleH = dxGetFontHeight(lay.ts, FONT_BOLD)
    lay.innerW = lay.w - lay.pad * 2 - lay.fpad * 2

    local sample = "the quick brown fox jumps over THE LAZY DOG 0123456789"
    local avg = L.width(sample, lay.fs, FONT) / #sample
    local est = maxLen * avg / lay.innerW
    lay.multi = est > 1
    lay.rows  = lay.multi and math.max(2, math.min(MAX_ROWS, math.ceil(est))) or 1

    lay.fieldH  = lay.rows * lay.lineH + lay.fpad * 2
    lay.btnH    = ui(38)
    lay.h       = lay.pad + lay.titleH + ui(14) + lay.fieldH + ui(16) + lay.btnH + lay.pad
    return lay
end

-- Word wrap into { s, e } char ranges. Spaces may overhang the right edge so a
-- row never starts with the space that broke it.
local function wrap(ti)
    local chars, maxW, fs = ti.chars, ti.L.innerW, ti.L.fs
    local n, lines, s = #chars, {}, 1
    if n == 0 then return { { s = 1, e = 0 } } end

    while s <= n do
        local w, e, lastSpace, i = 0, s - 1, nil, s
        while i <= n do
            local ch = chars[i]
            if ch == " " then
                lastSpace = i
            else
                local chw = cw(ch, fs)
                if w + chw > maxW and i > s then break end
                w = w + chw
            end
            e = i
            i = i + 1
        end
        if e < n and lastSpace and lastSpace < e then e = lastSpace end
        lines[#lines + 1] = { s = s, e = e }
        s = e + 1
    end
    -- caret after a trailing wrap-space lands on a fresh empty row
    local last = lines[#lines]
    if chars[n] == " " and width(ti, last.s, last.e) > maxW then
        lines[#lines + 1] = { s = n + 1, e = n }
    end
    return lines
end

local function caretLine(ti)
    local p, lines = ti.caret, ti.lines
    for i, ln in ipairs(lines) do
        if (p >= ln.s - 1 and p < ln.e) or i == #lines then return i, ln end
    end
    return #lines, lines[#lines]
end

local function refresh(ti)
    if ti.L.multi then
        ti.lines = wrap(ti)
        local li = caretLine(ti)
        if li < ti.top then ti.top = li end
        if li > ti.top + ti.L.rows - 1 then ti.top = li - ti.L.rows + 1 end
        ti.top = math.max(1, math.min(ti.top, math.max(1, #ti.lines - ti.L.rows + 1)))
    else
        if ti.caret < ti.first then ti.first = ti.caret end
        while ti.first < ti.caret and width(ti, ti.first + 1, ti.caret) > ti.L.innerW do
            ti.first = ti.first + 1
        end
    end
end

-- char position (0..#chars) closest to x inside the range s..e
local function posInRange(ti, s, e, x)
    local best, bestD = s - 1, math.abs(x)
    for p = s, e do
        local d = math.abs(width(ti, s, p) - x)
        if d < bestD then best, bestD = p, d end
    end
    return best
end

--------------------------------------------------------------------------------
-- editing
--------------------------------------------------------------------------------

local function clearAll(ti)
    ti.chars, ti.caret, ti.first, ti.top, ti.selAll = {}, 0, 0, 1, false
end

local function insert(ti, str)
    if ti.selAll then clearAll(ti) end
    str = tostring(str or ""):gsub("[%c]", " ")
    for i = 1, utf8.len(str) or 0 do
        if #ti.chars >= ti.maxLen then break end
        table.insert(ti.chars, ti.caret + 1, utf8.sub(str, i, i))
        ti.caret = ti.caret + 1
    end
    refresh(ti)
end

local function verticalMove(ti, dir)
    local li, ln = caretLine(ti)
    local target = ti.lines[li + dir]
    if not target then
        ti.caret = (dir < 0) and 0 or #ti.chars
        return
    end
    local x = width(ti, ln.s, ti.caret)
    local e = (li + dir < #ti.lines) and target.e - 1 or target.e
    ti.caret = posInRange(ti, target.s, math.max(target.s - 1, e), x)
end

local ACTIONS = {
    backspace = function(ti)
        if ti.selAll then return clearAll(ti) end
        if ti.caret > 0 then
            table.remove(ti.chars, ti.caret)
            ti.caret = ti.caret - 1
        end
    end,
    delete = function(ti)
        if ti.selAll then return clearAll(ti) end
        if ti.caret < #ti.chars then table.remove(ti.chars, ti.caret + 1) end
    end,
    arrow_l = function(ti) ti.caret = math.max(0, ti.caret - 1) end,
    arrow_r = function(ti) ti.caret = math.min(#ti.chars, ti.caret + 1) end,
    arrow_u = function(ti) if ti.L.multi then verticalMove(ti, -1) else ti.caret = 0 end end,
    arrow_d = function(ti) if ti.L.multi then verticalMove(ti, 1) else ti.caret = #ti.chars end end,
    home    = function(ti)
        if ti.L.multi then local _, ln = caretLine(ti); ti.caret = ln.s - 1 else ti.caret = 0 end
    end,
    ["end"] = function(ti)
        if ti.L.multi then
            local li, ln = caretLine(ti)
            ti.caret = (li < #ti.lines and ti.chars[ln.e] == " ") and ln.e - 1 or ln.e
        else
            ti.caret = #ti.chars
        end
    end,
}
local REPEATS = { backspace = true, delete = true, arrow_l = true, arrow_r = true, arrow_u = true, arrow_d = true }

local function runAction(ti, key)
    ACTIONS[key](ti)
    if key ~= "backspace" and key ~= "delete" then ti.selAll = false end
    refresh(ti)
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

-- Enter that confirmed the input must not reach GTA as enter_exit once we stop
-- swallowing keys (same trick as toggleMoveControls in exports.lua).
local function guardEnterExit()
    if not isControlEnabled("enter_exit") then return end
    toggleControl("enter_exit", false)
    local function check()
        if getKeyState("enter") or getKeyState("num_enter") then return end
        removeEventHandler("onClientRender", root, check)
        toggleControl("enter_exit", true)
    end
    addEventHandler("onClientRender", root, check)
end

local function finish(text)
    local ti = UI.textInput
    if not ti.active then return end

    local token = ti.token
    ti.active = false
    ti.token  = nil
    ti.rep    = nil

    guiSetInputMode(ti.prevMode or "allow_binds")
    showCursor(false)
    setElementData(localPlayer, "textInputOpen", false, false)

    triggerEvent("ui_core:textInputResult", root, token, text ~= nil and text or false)
end

local function confirm()
    local ti = UI.textInput
    if not ti.active then return end
    guardEnterExit()
    finish(table.concat(ti.chars))
end

-- exports.ui_core:openTextInput(title, maxLength, defaultText, placeholder)
--   -> token (string) on success, false if one is already open
function openTextInput(title, maxLength, defaultText, placeholder)
    local ti = UI.textInput
    if ti.active then return false end

    ti.maxLen      = math.max(1, math.min(1024, math.floor(tonumber(maxLength) or 32)))
    ti.title       = tostring(title or "")
    ti.placeholder = tostring(placeholder or "")
    ti.token       = "ti_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1000, 9999))
    ti.L           = buildLayout(ti.maxLen)
    ti.openTick    = getTickCount()
    ti.rep         = nil
    clearAll(ti)
    ti.active      = true
    insert(ti, defaultText or "")

    ti.prevMode = guiGetInputMode()
    guiSetInputMode("no_binds")
    setElementData(localPlayer, "textInputOpen", true, false)
    showCursor(true)

    return ti.token
end

-- exports.ui_core:closeTextInput()  - cancels (fires the result event with false)
function closeTextInput()
    if not UI.textInput.active then return false end
    finish(false)
    return true
end

-- exports.ui_core:isTextInputOpen()
function isTextInputOpen()
    return UI.textInput.active == true
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function ctrlDown()
    return getKeyState("lctrl") or getKeyState("rctrl")
end

addEventHandler("onClientKey", root, function(key, press)
    local ti = UI.textInput
    if not ti.active then return end
    if key:find("^mouse%d") then return end   -- clicks go to onClientClick
    if key == "v" and press and ctrlDown() then
        -- MTA only fires onClientPaste for a "v" stroke that onClientKey did not cancel;
        -- keep GTA's V (camera) quiet for that one press instead
        if isControlEnabled("change_camera") then
            toggleControl("change_camera", false)
            setTimer(toggleControl, 250, 1, "change_camera", true)
        end
        return
    end
    cancelEvent()
    if not press then return end

    if key == "escape" then
        finish(false)
    elseif key == "enter" or key == "num_enter" then
        confirm()
    elseif ACTIONS[key] then
        runAction(ti, key)
        ti.rep = REPEATS[key] and { key = key, next = getTickCount() + REPEAT_DELAY } or nil
    elseif ctrlDown() then
        if key == "a" then
            ti.selAll = #ti.chars > 0
        elseif key == "c" or key == "x" then
            if #ti.chars > 0 then setClipboard(table.concat(ti.chars)) end
            if key == "x" then clearAll(ti); refresh(ti) end
        end
    end
end, true, "high+100")

addEventHandler("onClientCharacter", root, function(ch)
    local ti = UI.textInput
    if not ti.active or ctrlDown() then return end
    local b = ch:byte()
    if not b or b < 32 or b == 127 then return end
    insert(ti, ch)
end)

addEventHandler("onClientPaste", root, function(text)
    local ti = UI.textInput
    if not ti.active then return end
    insert(ti, (tostring(text):gsub("[\r\n\t]+", " ")))
end)

local function cursorXY()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * UI.sw, cy * UI.sh
end

local function inRect(px, py, r)
    return r and px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

addEventHandler("onClientClick", root, function(button, state)
    local ti = UI.textInput
    if not ti.active or button ~= "left" or state ~= "down" then return end
    local mx, my = cursorXY()
    local h = ti.hits

    if inRect(mx, my, h.confirm) then return confirm() end
    if inRect(mx, my, h.cancel) then return finish(false) end
    if not inRect(mx, my, h.text) then return end

    ti.selAll = false
    local rx, ry = mx - h.text.x, my - h.text.y
    if ti.L.multi then
        local li = math.min(#ti.lines, ti.top + math.floor(ry / ti.L.lineH))
        local ln = ti.lines[li]
        local e = (li < #ti.lines) and ln.e - 1 or ln.e
        ti.caret = posInRange(ti, ln.s, math.max(ln.s - 1, e), rx)
    else
        ti.caret = posInRange(ti, ti.first + 1, #ti.chars, rx)
    end
    refresh(ti)
end)

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function rect(x, y, w, h, c, a)
    dxDrawRectangle(x, y, w, h, col(c, a), true)
end

local function text(str, x, y, w, h, c, a, scale, font, ax, ay, clip)
    dxDrawText(str, x, y, x + w, y + h, col(c, a), scale, font or FONT, ax or "left", ay or "center", clip or false, false, true)
end

local function drawButton(ti, id, label, keyLabel, x, y, w, h, primary, a, mx, my)
    local r = { x = x, y = y, w = w, h = h }
    ti.hits[id] = r
    local hover = inRect(mx, my, r)
    local bg = primary and COL.accent or (hover and COL.btnHover or COL.btn)
    rect(x, y, w, h, bg, a * ((primary and hover) and 0.85 or 1))

    local lay = ti.L
    local kw = L.width(keyLabel, lay.ss * 0.9, FONT_BOLD) + ui(12)
    local kh = h - ui(14)
    local kx = x + w - ui(8) - kw
    rect(kx, y + ui(7), kw, kh, COL.chip, a)
    text(keyLabel, kx, y + ui(7), kw, kh, COL.text, a * 0.85, lay.ss * 0.9, FONT_BOLD, "center")
    text(label, x + ui(12), y, kx - x - ui(16), h, COL.text, a, lay.ss * 1.1, FONT_BOLD, "left")
end

local function buttonWidth(ti, label, keyLabel)
    local lay = ti.L
    return L.width(label, lay.ss * 1.1, FONT_BOLD) + L.width(keyLabel, lay.ss * 0.9, FONT_BOLD) + ui(48)
end

function UI.textInput:draw()
    if not self.active then return end
    local lay, now = self.L, getTickCount()

    -- held key auto-repeat
    local rep = self.rep
    if rep then
        if not getKeyState(rep.key) then
            self.rep = nil
        elseif now >= rep.next then
            rep.next = now + REPEAT_RATE
            runAction(self, rep.key)
        end
    end

    local t = math.min(1, (now - self.openTick) / 180)
    local ease = 1 - (1 - t) ^ 3
    local a = ease
    local mx, my = cursorXY()

    local x = (UI.sw - lay.w) / 2
    local y = (UI.sh - lay.h) / 2 + (1 - ease) * ui(16)

    -- backdrop + card
    rect(0, 0, UI.sw, UI.sh, COL.dim, a)
    for i = 1, 3 do
        local o = ui(i * 3)
        rect(x - o + ui(4), y - o + ui(8), lay.w + o * 2, lay.h + o * 2, COL.shadow, a * (0.5 / i))
    end
    rect(x, y, lay.w, lay.h, COL.card, a)
    rect(x, y, lay.w, ui(3), COL.accent, a)

    -- title
    local cy = y + lay.pad
    text(self.title, x + lay.pad, cy, lay.w - lay.pad * 2, lay.titleH, COL.text, a, lay.ts, FONT_BOLD, "left", "center", true)
    cy = cy + lay.titleH + ui(14)

    -- field
    local fx, fw = x + lay.pad, lay.w - lay.pad * 2
    rect(fx, cy, fw, lay.fieldH, COL.accent, a)
    rect(fx + ui(2), cy + ui(2), fw - ui(4), lay.fieldH - ui(4), COL.field, a)
    local tx, ty = fx + lay.fpad, cy + lay.fpad
    self.hits.text = { x = fx, y = cy, w = fw, h = lay.fieldH }

    local n = #self.chars
    local blink = (now - self.openTick) % 1000 < 530
    local caretX, caretY

    if n == 0 and self.placeholder ~= "" then
        text(self.placeholder, tx, ty, lay.innerW, lay.lineH, COL.muted, a, lay.fs, FONT, "left", "center", true)
    end

    if lay.multi then
        local lines = self.lines
        local cli = caretLine(self)
        for row = 0, lay.rows - 1 do
            local ln = lines[self.top + row]
            if not ln then break end
            local ly = ty + row * lay.lineH
            local str = sub(self.chars, ln.s, ln.e)
            if self.selAll and ln.e >= ln.s then
                rect(tx, ly + ui(1), L.width(str, lay.fs, FONT), lay.lineH - ui(2), COL.sel, a)
            end
            text(str, tx, ly, lay.innerW + ui(8), lay.lineH, COL.text, a, lay.fs, FONT, "left", "center", true)
            if self.top + row == cli then
                caretX, caretY = tx + width(self, ln.s, self.caret), ly
            end
        end
        -- scroll indicator
        if #lines > lay.rows then
            local trackH = lay.fieldH - ui(12)
            local barH = math.max(ui(16), trackH * lay.rows / #lines)
            local barY = cy + ui(6) + (trackH - barH) * (self.top - 1) / (#lines - lay.rows)
            rect(fx + fw - ui(7), barY, ui(3), barH, COL.muted, a * 0.8)
        end
    else
        local str = sub(self.chars, self.first + 1, n)
        if self.selAll and n > 0 then
            rect(tx, ty + ui(1), math.min(lay.innerW, L.width(str, lay.fs, FONT)), lay.lineH - ui(2), COL.sel, a)
        end
        text(str, tx, ty, lay.innerW, lay.lineH, COL.text, a, lay.fs, FONT, "left", "center", true)
        caretX, caretY = tx + width(self, self.first + 1, self.caret), ty
    end

    if caretX and blink and not self.selAll then
        rect(caretX, caretY + lay.lineH * 0.15, ui(2), lay.lineH * 0.7, COL.accent, a)
    end
    cy = cy + lay.fieldH + ui(16)

    -- footer: counter + buttons
    local ratio = n / self.maxLen
    local cc = (n >= self.maxLen) and COL.full or (ratio >= 0.9 and COL.warn or COL.muted)
    text(n .. " / " .. self.maxLen, fx, cy, fw / 2, lay.btnH, cc, a, lay.ss * 1.05, FONT_BOLD, "left")

    local okW = buttonWidth(self, L("common.confirm"), L("ui_core.textinput.enter"))
    local noW = buttonWidth(self, L("common.cancel"), L("ui_core.textinput.esc"))
    local bx = fx + fw - okW
    drawButton(self, "confirm", L("common.confirm"), L("ui_core.textinput.enter"), bx, cy, okW, lay.btnH, true, a, mx, my)
    drawButton(self, "cancel", L("common.cancel"), L("ui_core.textinput.esc"), bx - ui(10) - noW, cy, noW, lay.btnH, false, a, mx, my)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if UI.textInput.active then finish(false) end
end)
