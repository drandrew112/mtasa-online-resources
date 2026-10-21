-- DX text field without ui_core: single or multi line, caret, word wrap,
-- scrolling. Keyboard input is fed by the owner (editor.lua):
--   onClientCharacter -> field:insert(ch), onClientPaste -> field:insert(text),
--   onClientKey       -> field:key(key, shift) (backspace, delete, arrows, home, end, enter;
--                        shift extends the selection)
--
--   local f = TextField.new{ max = 120, multiline = false, filter = fn(ch) -> bool }
--   f:setText(s) / f:getText()
--   f:draw(x, y, w, h, focused, style)  style = { font, scale, color, caret, sel, lineH }
--   f:clickAt(px, py, shift)            puts the caret under the cursor (shift: extend selection)
--   f:dragTo(px, py)                    moves the caret, keeps the anchor (mouse drag selection)
--   f:selectWordAt(px, py) / f:selectAll()
--   f:getSelected() -> text or nil, f:deleteSelection()
--
-- Selection = the chars between `anchor` and `caret` (0-based positions); none when nil or equal.

TextField = {}
TextField.__index = TextField

local ulen, usub = utf8.len, utf8.sub

local function len(s) return ulen(s) or #s end

function TextField.new(opts)
    opts = opts or {}
    return setmetatable({
        text = "", caret = 0, max = opts.max or 64, multiline = opts.multiline == true,
        filter = opts.filter, layout = nil, layoutKey = nil, scroll = 0, desiredX = nil, anchor = nil,
    }, TextField)
end

function TextField:getText() return self.text end

function TextField:setText(s)
    s = tostring(s or "")
    if not self.multiline then s = s:gsub("[\r\n]", " ") end
    if len(s) > self.max then s = usub(s, 1, self.max) end
    self.text, self.caret, self.scroll, self.layout, self.anchor = s, len(s), 0, nil, nil
end

-- selection as 0-based positions a < b, or nil
function TextField:selRange()
    local a, b = self.anchor, self.caret
    if not a or a == b then return nil end
    if a > b then a, b = b, a end
    return a, b
end

function TextField:getSelected()
    local a, b = self:selRange()
    if not a then return nil end
    return usub(self.text, a + 1, b)
end

function TextField:deleteSelection()
    local a, b = self:selRange()
    self.anchor = nil
    if not a then return false end
    self.text = usub(self.text, 1, a) .. usub(self.text, b + 1)
    self.caret, self.layout, self.desiredX = a, nil, nil
    return true
end

function TextField:selectAll()
    self.anchor, self.caret, self.desiredX = 0, len(self.text), nil
end

function TextField:insert(str)
    str = tostring(str or ""):gsub("\r\n?", "\n")
    if not self.multiline then str = str:gsub("\n", " ") end
    str = str:gsub("\t", "    ")
    self:deleteSelection()
    local out, room = {}, self.max - len(self.text)
    for i = 1, len(str) do
        if room <= 0 then break end
        local ch = usub(str, i, i)
        local b = ch:byte()
        if (ch == "\n" or (b and b >= 32)) and (not self.filter or self.filter(ch)) then
            out[#out + 1] = ch
            room = room - 1
        end
    end
    if #out == 0 then return end
    local add = table.concat(out)
    self.text = usub(self.text, 1, self.caret) .. add .. usub(self.text, self.caret + 1)
    self.caret = self.caret + #out
    self.layout, self.desiredX = nil, nil
end

-- visual lines: { { first = char index (1-based), count = chars, text } }
function TextField:buildLayout(w, font, scale)
    local key = self.text .. "\0" .. w .. "\0" .. tostring(font) .. "\0" .. scale
    if self.layout and self.layoutKey == key then return self.layout end
    local lines, text = {}, self.text
    local total = len(text)

    if not self.multiline then
        lines[1] = { first = 1, count = total, text = text }
    else
        local i = 1
        while true do
            -- one hard line: chars i .. j-1 (j = position of "\n" or total + 1)
            local j = i
            while j <= total and usub(text, j, j) ~= "\n" do j = j + 1 end
            local start = i
            if start == j then lines[#lines + 1] = { first = start, count = 0, text = "" } end
            while start < j do
                local stop = start          -- last char that fits
                local lastSpace = nil
                local k = start
                while k < j do
                    local piece = usub(text, start, k)
                    if dxGetTextWidth(piece, scale, font) > w and k > start then break end
                    if usub(text, k, k) == " " then lastSpace = k end
                    stop = k
                    k = k + 1
                end
                if k < j and lastSpace and lastSpace >= start then stop = lastSpace end
                lines[#lines + 1] = { first = start, count = stop - start + 1, text = usub(text, start, stop) }
                start = stop + 1
            end
            if j > total then break end
            i = j + 1
            if i > total then lines[#lines + 1] = { first = i, count = 0, text = "" } break end
        end
        if #lines == 0 then lines[1] = { first = 1, count = 0, text = "" } end
    end

    self.layout, self.layoutKey = lines, key
    self.font, self.scale = font, scale
    return lines
end

-- caret -> line index, column (chars before the caret on that line)
function TextField:caretLine()
    local lines = self.layout
    if not lines then return 1, self.caret end
    local found = 1
    for i, l in ipairs(lines) do
        if l.first - 1 <= self.caret then found = i else break end
    end
    local l = lines[found]
    return found, math.min(self.caret - (l.first - 1), l.count)
end

local function colAtX(line, x, font, scale)
    local best, bestD = 0, math.abs(x)
    for c = 1, line.count do
        local d = math.abs(dxGetTextWidth(usub(line.text, 1, c), scale, font) - x)
        if d < bestD then best, bestD = c, d end
    end
    return best
end

local MOVES = { arrow_l = true, arrow_r = true, arrow_u = true, arrow_d = true, home = true, ["end"] = true }

function TextField:key(key, shift)
    if MOVES[key] then
        local a, b = self:selRange()
        if shift then
            self.anchor = self.anchor or self.caret
        else
            self.anchor = nil
            -- plain left/right on a selection: caret to its edge
            if a and key == "arrow_l" then self.caret, self.desiredX = a, nil return end
            if a and key == "arrow_r" then self.caret, self.desiredX = b, nil return end
        end
    elseif (key == "backspace" or key == "delete") and self:deleteSelection() then
        return
    end

    local total = len(self.text)
    if key == "backspace" then
        if self.caret > 0 then
            self.text = usub(self.text, 1, self.caret - 1) .. usub(self.text, self.caret + 1)
            self.caret = self.caret - 1
            self.layout, self.desiredX = nil, nil
        end
    elseif key == "delete" then
        if self.caret < total then
            self.text = usub(self.text, 1, self.caret) .. usub(self.text, self.caret + 2)
            self.layout, self.desiredX = nil, nil
        end
    elseif key == "arrow_l" then
        self.caret, self.desiredX = math.max(0, self.caret - 1), nil
    elseif key == "arrow_r" then
        self.caret, self.desiredX = math.min(total, self.caret + 1), nil
    elseif key == "home" or key == "end" then
        if self.multiline and self.layout then
            local li = self:caretLine()
            local l = self.layout[li]
            self.caret = key == "home" and l.first - 1 or l.first - 1 + l.count
        else
            self.caret = key == "home" and 0 or total
        end
        self.desiredX = nil
    elseif (key == "arrow_u" or key == "arrow_d") and self.multiline and self.layout then
        local li, col = self:caretLine()
        local l = self.layout[li]
        local x = self.desiredX or dxGetTextWidth(usub(l.text, 1, col), self.scale, self.font)
        local target = self.layout[li + (key == "arrow_u" and -1 or 1)]
        if target then
            self.caret = target.first - 1 + colAtX(target, x, self.font, self.scale)
            self.desiredX = x
        end
    elseif (key == "enter" or key == "num_enter") and self.multiline then
        self:insert("\n")
    end
end

function TextField:draw(x, y, w, h, focused, style)
    local font, scale = style.font or "default", style.scale or 1
    local lineH = style.lineH or dxGetFontHeight(scale, font)
    local lines = self:buildLayout(w, font, scale)
    local visible = math.max(1, math.floor(h / lineH))
    local li, col = self:caretLine()

    if self.multiline then
        if li - 1 < self.scroll then self.scroll = li - 1 end
        if li > self.scroll + visible then self.scroll = li - visible end
        self.scroll = math.max(0, math.min(self.scroll, math.max(0, #lines - visible)))
    end
    self.drawRect = { x = x, y = y, w = w, h = h, lineH = lineH, visible = visible }
    local sa, sb = self:selRange()
    local selColor = style.sel or tocolor(64, 156, 180, 110)

    if not self.multiline then
        -- single line: shift left so the caret stays inside
        local before = usub(self.text, 1, self.caret)
        local shift = math.max(0, dxGetTextWidth(before, scale, font) - w + 2)
        self.shift = shift
        if sa then
            local x1 = math.max(x, x + dxGetTextWidth(usub(self.text, 1, sa), scale, font) - shift)
            local x2 = math.min(x + w, x + dxGetTextWidth(usub(self.text, 1, sb), scale, font) - shift)
            if x2 > x1 then dxDrawRectangle(x1, y + h * 0.15, x2 - x1, h * 0.7, selColor) end
        end
        dxDrawText(self.text, x - shift, y, x + w, y + h, style.color, scale, font, "left", "center", true)
        if focused and getTickCount() % 1000 < 520 then
            local cx = x + dxGetTextWidth(before, scale, font) - shift
            dxDrawRectangle(cx, y + h * 0.2, 2, h * 0.6, style.caret or style.color)
        end
        return
    end

    for i = self.scroll + 1, math.min(#lines, self.scroll + visible) do
        local ly = y + (i - self.scroll - 1) * lineH
        local l = lines[i]
        if sa then
            local base, stop = l.first - 1, l.first - 1 + l.count
            local s0, e0 = math.max(sa, base), math.min(sb, stop)
            if sb > base and sa <= stop and e0 >= s0 then
                local x1 = x + dxGetTextWidth(usub(l.text, 1, s0 - base), scale, font)
                local x2 = x + dxGetTextWidth(usub(l.text, 1, e0 - base), scale, font)
                if sb > stop then x2 = x2 + 4 end -- selection goes on past the line end
                if x2 > x1 then dxDrawRectangle(x1, ly + 1, x2 - x1, lineH - 2, selColor) end
            end
        end
        dxDrawText(lines[i].text, x, ly, x + w, ly + lineH, style.color, scale, font, "left", "top", true)
    end
    if focused and getTickCount() % 1000 < 520 and li > self.scroll and li <= self.scroll + visible then
        local cx = x + dxGetTextWidth(usub(lines[li].text, 1, col), scale, font)
        local cy = y + (li - self.scroll - 1) * lineH
        dxDrawRectangle(cx, cy + 1, 2, lineH - 2, style.caret or style.color)
    end
    if #lines > visible then
        local trackH = h
        local thumbH = math.max(12, trackH * visible / #lines)
        local thumbY = y + (trackH - thumbH) * (self.scroll / (#lines - visible))
        dxDrawRectangle(x + w + 4, thumbY, 3, thumbH, style.caret or style.color)
    end
end

function TextField:scrollBy(n)
    if not self.layout or not self.drawRect then return end
    local maxScroll = math.max(0, #self.layout - self.drawRect.visible)
    self.scroll = math.max(0, math.min(maxScroll, self.scroll + n))
end

-- text position under a screen point (nil before the first draw)
function TextField:posAt(px, py)
    local r = self.drawRect
    if not r or not self.layout then return nil end
    if not self.multiline then
        return colAtX(self.layout[1], px - r.x + (self.shift or 0), self.font, self.scale)
    end
    local li = math.floor((py - r.y) / r.lineH) + 1 + self.scroll
    li = math.max(1, math.min(#self.layout, li))
    local l = self.layout[li]
    return l.first - 1 + colAtX(l, px - r.x, self.font, self.scale)
end

function TextField:clickAt(px, py, shift)
    local pos = self:posAt(px, py) or len(self.text)
    if shift then
        self.anchor = self.anchor or self.caret
    else
        self.anchor = pos
    end
    self.caret, self.desiredX = pos, nil
end

function TextField:dragTo(px, py)
    local pos = self:posAt(px, py)
    if not pos then return end
    self.anchor = self.anchor or self.caret
    self.caret, self.desiredX = pos, nil
end

function TextField:selectWordAt(px, py)
    local pos = self:posAt(px, py)
    if not pos then return end
    local total = len(self.text)
    local function isWord(i)
        return i >= 1 and i <= total and not usub(self.text, i, i):match("[%s%p]")
    end
    if not isWord(pos) and not isWord(pos + 1) then return end
    local a, b = pos, pos
    while isWord(a) do a = a - 1 end
    while isWord(b + 1) do b = b + 1 end
    self.anchor, self.caret, self.desiredX = a, b, nil
end
