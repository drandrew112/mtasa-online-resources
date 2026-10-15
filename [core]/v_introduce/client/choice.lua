if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The choice scene: a centred panel with options the player picks with the mouse (or the keys
-- 1-9). kind = "language" lists the enabled languages of v_locals and switches the language at
-- once (the texts follow, they are resolved every frame); kind = "tour" decides how much of the
-- rest of the introduction is shown (R.autoSkip, see client/runner.lua).

local st = {}

local function inside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function cursor()
    if not isCursorShowing() then return -1, -1 end
    local rx, ry = getCursorPosition()
    return rx * Draw.sw, ry * Draw.sh
end

local function loadOptions(sc)
    if sc.kind == "language" then
        local ok, list = pcall(function() return exports.v_locals:getLanguages() end)
        local options = {}
        for _, l in ipairs(ok and list or {}) do options[#options + 1] = { id = l.value, label = l.label } end
        return options
    end
    return sc.options or {}
end

local function pick(i)
    local option = st.options[i]
    if not option then return end
    st.picked = i
    playSoundFrontEnd(41)
    if st.kind == "language" then
        exports.v_locals:setLanguage(option.id)
    else
        st.R.autoSkip = (option.id == "essential" and "nonessential") or (option.id == "none" and "all") or nil
    end
end

local function onClick(btn, state)
    if not st.active or btn ~= "left" or state ~= "down" then return end
    local cx, cy = cursor()
    for i, r in ipairs(st.rects or {}) do
        if inside(r[1], r[2], r[3], r[4], cx, cy) then return pick(i) end
    end
end

local function onKey(key, press)
    if not st.active or not press then return end
    local n = tonumber(key:match("^num_(%d)$") or key:match("^(%d)$"))
    if n then pick(n) end
end

Scenes.choice = {
    hud = false,
    start = function(sc, R)
        st = { active = true, R = R, kind = sc.kind, options = loadOptions(sc), picked = nil }
        if sc.kind == "language" then
            local current = exports.v_locals:getLanguage()
            for i, o in ipairs(st.options) do if o.id == current then st.picked = i end end
        end
        Scenes.cameraStart(sc)
        showCursor(true, false)
        addEventHandler("onClientKey", root, onKey)
        addEventHandler("onClientClick", root, onClick)
    end,
    stop = function()
        st.active = false
        showCursor(false)
        removeEventHandler("onClientKey", root, onKey)
        removeEventHandler("onClientClick", root, onClick)
    end,
    render = function(sc, R)
        local s, f, C = Draw.s, Draw.fonts(), Draw.colors
        Draw.dimAll()
        local W, PAD, ROW = math.min(s(560), Draw.sw - s(40)), s(26), s(52)
        local text = Scenes.resolve(sc.text) or ""
        local th = Draw.textHeight(text, W - PAD * 2, f.body)
        local H = PAD * 2 + s(44) + th + s(14) + #st.options * (ROW + s(8))
        local x, y = (Draw.sw - W) / 2, (Draw.sh - H) / 2
        dxDrawRectangle(x, y, W, H, C.panel, true)
        dxDrawRectangle(x, y, W, s(4), C.accent, true)
        dxDrawText(Scenes.resolve(sc.title) or R.module.title, x + PAD, y + PAD, x + W - PAD, y + PAD + s(32),
            C.text, 1, f.title, "left", "top", true, false, true)
        dxDrawText(text, x + PAD, y + PAD + s(44), x + W - PAD, y + PAD + s(44) + th, C.text, 1, f.body,
            "left", "top", false, true, true)
        local cx, cy = cursor()
        st.rects = {}
        local ry = y + PAD + s(44) + th + s(14)
        for i, o in ipairs(st.options) do
            local chosen = st.picked == i
            local hover = inside(x + PAD, ry, W - PAD * 2, ROW, cx, cy)
            st.rects[i] = { x + PAD, ry, W - PAD * 2, ROW }
            dxDrawRectangle(x + PAD, ry, W - PAD * 2, ROW, hover and tocolor(255, 255, 255, 30) or C.row, true)
            if chosen then dxDrawRectangle(x + PAD, ry, s(4), ROW, C.accent, true) end
            dxDrawText(tostring(i), x + PAD + s(16), ry, x + PAD + s(44), ry + ROW, chosen and C.accent or C.faint,
                1, f.bold, "left", "center", true, false, true)
            dxDrawText(Scenes.resolve(o.label) or "", x + PAD + s(50), ry, x + W - PAD - s(10), ry + ROW,
                chosen and C.text or C.muted, 1, f.bold, "left", "center", true, false, true)
            ry = ry + ROW + s(8)
        end
    end,
    complete = function() return st.picked ~= nil end,
    message = function() return L("v_introduce.choice.pick_an_option_to_continue") end,
}
