-- The accept scene: rules.txt in a scrollable box. The player has to scroll to the end, tick
-- the box and press Accept. Mouse wheel / arrow keys scroll, the cursor is shown.

local rulesText

local function loadRules()
    if rulesText then return rulesText end
    local f = fileOpen("rules.txt", true)
    if not f then
        rulesText = "The rules could not be loaded."
        return rulesText
    end
    rulesText = fileRead(f, fileGetSize(f)):gsub("\r", "")
    fileClose(f)
    return rulesText
end

local st = {}

local function inside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function cursor()
    if not isCursorShowing() then return -1, -1 end
    local rx, ry = getCursorPosition()
    return rx * Draw.sw, ry * Draw.sh
end

local function scroll(delta)
    if not st.active then return end
    st.offset = math.max(0, math.min(st.maxOffset or 0, st.offset + delta))
end

local function onKey(key, press)
    if not st.active or not press then return end
    local step = Draw.s(60)
    if key == "mouse_wheel_down" or key == "arrow_d" then scroll(step)
    elseif key == "mouse_wheel_up" or key == "arrow_u" then scroll(-step)
    elseif key == "pgdn" then scroll(step * 5)
    elseif key == "pgup" then scroll(-step * 5)
    end
end

local function onClick(btn, state)
    if not st.active or btn ~= "left" or state ~= "down" then return end
    local cx, cy = cursor()
    if st.boxRect and st.reachedEnd and inside(st.boxRect[1], st.boxRect[2], st.boxRect[3], st.boxRect[4], cx, cy) then
        st.checked = not st.checked
        playSoundFrontEnd(41)
    elseif st.buttonRect and st.checked and inside(st.buttonRect[1], st.buttonRect[2], st.buttonRect[3], st.buttonRect[4], cx, cy) then
        st.accepted = true
        playSoundFrontEnd(41)
    end
end

Scenes.accept = {
    hud = false,
    start = function(sc)
        st = { active = true, offset = 0, checked = false, accepted = false, reachedEnd = false }
        Scenes.cameraStart(sc)
        showCursor(true, false)
        addEventHandler("onClientKey", root, onKey)
        addEventHandler("onClientClick", root, onClick)
    end,
    stop = function()
        st.active = false
        if isElement(st.rt) then destroyElement(st.rt) end
        st.rt = nil
        showCursor(false)
        removeEventHandler("onClientKey", root, onKey)
        removeEventHandler("onClientClick", root, onClick)
    end,
    render = function(sc, R)
        local s, f, C = Draw.s, Draw.fonts(), Draw.colors
        Draw.dimAll()
        local W, H = math.min(s(760), Draw.sw - s(40)), math.min(s(640), Draw.sh - s(160))
        local x, y = (Draw.sw - W) / 2, (Draw.sh - H) / 2 + s(20)
        local PAD = s(26)
        dxDrawRectangle(x, y, W, H, C.panel, true)
        dxDrawRectangle(x, y, W, s(4), C.accent, true)
        dxDrawText(Scenes.resolve(sc.title) or "Server rules", x + PAD, y + PAD, x + W - PAD, y + PAD + s(32),
            C.text, 1, f.title, "left", "top", true, false, true)

        -- text box
        local bx, by = x + PAD, y + PAD + s(44)
        local bw, bh = W - PAD * 2, H - PAD * 2 - s(44) - s(100)
        local text = loadRules()
        local th = Draw.textHeight(text, bw - s(16), f.body)
        st.maxOffset = math.max(0, th - bh)
        if st.offset >= st.maxOffset - 2 then st.reachedEnd = true end
        dxDrawRectangle(bx, by, bw, bh, C.row, true)
        -- the scrolled text is drawn into a render target of the box size, so it is clipped to it
        local rw, rh = math.floor(bw), math.floor(bh)
        if not st.rt or st.rtW ~= rw or st.rtH ~= rh then
            if isElement(st.rt) then destroyElement(st.rt) end
            st.rt, st.rtW, st.rtH = dxCreateRenderTarget(rw, rh, true), rw, rh
        end
        if st.rt then
            dxSetRenderTarget(st.rt, true)
            dxSetBlendMode("modulate_add")
            dxDrawText(text, s(8), s(6) - st.offset, rw - s(16), s(6) - st.offset + th, C.text, 1, f.body,
                "left", "top", false, true)
            dxSetBlendMode("blend")
            dxSetRenderTarget()
            dxSetBlendMode("add")
            dxDrawImage(bx, by, rw, rh, st.rt, 0, 0, 0, tocolor(255, 255, 255), true)
            dxSetBlendMode("blend")
        else
            st.reachedEnd = true   -- no render target (video memory): show what fits, do not lock
            dxDrawText(text, bx + s(8), by + s(6), bx + bw - s(8), by + bh, C.text, 1, f.body, "left", "top", true, true, true)
        end
        -- scrollbar
        if st.maxOffset > 0 then
            local trackH = bh
            local thumbH = math.max(s(30), trackH * bh / th)
            local thumbY = by + (trackH - thumbH) * (st.offset / st.maxOffset)
            dxDrawRectangle(bx + bw - s(4), thumbY, s(4), thumbH, C.accent, true)
        end

        -- hint / checkbox / button
        local fy = by + bh + s(16)
        if not st.reachedEnd then
            dxDrawText("Scroll to the end of the rules (mouse wheel or arrow keys)", bx, fy, bx + bw, fy + s(24),
                C.accent, 1, f.bold, "left", "top", true, false, true)
        end
        local box = s(22)
        local cy = fy + s(34)
        st.boxRect = { bx, cy, box + s(12) + dxGetTextWidth("I have read and accept the rules", 1, f.bold), box }
        local boxColor = st.reachedEnd and C.accent or C.edge
        if st.checked then
            dxDrawRectangle(bx, cy, box, box, C.good, true)
        else
            dxDrawRectangle(bx, cy, box, box, boxColor, true)
            dxDrawRectangle(bx + s(2), cy + s(2), box - s(4), box - s(4), C.panel, true)
        end
        dxDrawText("I have read and accept the rules", bx + box + s(12), cy, bx + bw, cy + box,
            st.reachedEnd and C.text or C.faint, 1, f.bold, "left", "center", true, false, true)

        local btnW, btnH = s(170), s(42)
        local btnX, btnY = bx + bw - btnW, cy - s(10)
        st.buttonRect = { btnX, btnY, btnW, btnH }
        local cx, cyy = cursor()
        local hover = st.checked and inside(btnX, btnY, btnW, btnH, cx, cyy)
        dxDrawRectangle(btnX, btnY, btnW, btnH, st.checked and (hover and tocolor(255, 190, 80) or C.accent) or C.row, true)
        dxDrawText("ACCEPT", btnX, btnY, btnX + btnW, btnY + btnH,
            st.checked and tocolor(27, 19, 5) or C.faint, 1, f.bold, "center", "center", true, false, true)
    end,
    complete = function() return st.accepted == true end,
    autoNext = true,
    message = function() return "Accept the rules to finish this chapter" end,
}
