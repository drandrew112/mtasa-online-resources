-- Letoltes kozbeni minijatekok: kozos mag (menu, bemenet, rajzolo segedek).
-- A jatekok az MG.register-rel jelentkeznek be (pacman.lua, snake.lua, g2048.lua).
-- Csak akkor futnak, ha az MG.allowed() igaz (letoltes folyik, vagy /downloadtest).
if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

MG = {
    games = {},
    current = nil,      -- a futo jatek
    allowed = function() return false end, -- a client.lua felulirja
}

local uicore = exports["ui_core"]
local sw, sh = uicore:getScreenWH()
local u1 = uicore:ui(1)

function MG.U(n) return n * u1 end
MG.sw, MG.sh = sw, sh

local U = MG.U

-- ---------------------------------------------------------------- szoveg
-- Parameteres forditasok memoizalva (nem kepkockankent epitjuk ujra); nyelvvaltaskor torlodik.
local textCache, textCount = {}, 0
function MG.T(key, params)
    if not params then return L(key) end
    local ck = key
    for k, v in pairs(params) do ck = ck .. "|" .. k .. "=" .. tostring(v) end
    local s = textCache[ck]
    if not s then
        if textCount > 300 then textCache, textCount = {}, 0 end
        s = L(key, params)
        textCache[ck] = s
        textCount = textCount + 1
    end
    return s
end
if L.onChange then L.onChange(function() textCache, textCount = {}, 0 end) end

-- ---------------------------------------------------------------- rajzolo segedek
local rect, text = dxDrawRectangle, dxDrawText
local prim = dxDrawPrimitive

function MG.rect(x, y, w, h, c) rect(x, y, w, h, c) end

function MG.text(str, x, y, w, h, color, scale, font, ax, ay)
    text(str, x, y, x + w, y + h, color or tocolor(255, 255, 255), scale or 1, font or "default",
        ax or "center", ay or "center", true, false, false, false)
end

-- Kitoltott kor / korivszelet (trianglefan).
function MG.pie(cx, cy, r, color, a0, a1, segs)
    segs = segs or 20
    local v = { { cx, cy, color } }
    if not a0 then a0, a1 = 0, math.pi * 2 end
    for i = 0, segs do
        local a = a0 + (a1 - a0) * i / segs
        v[#v + 1] = { cx + math.cos(a) * r, cy + math.sin(a) * r, color }
    end
    prim("trianglefan", false, unpack(v))
end

-- Lekerekitett jellegu doboz: kozepso teglalap + csik + 4 sarok.
function MG.roundRect(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    rect(x + r, y, w - 2 * r, h, color)
    rect(x, y + r, r, h - 2 * r, color)
    rect(x + w - r, y + r, r, h - 2 * r, color)
    local pi = math.pi
    MG.pie(x + r, y + r, r, color, pi, pi * 1.5, 6)
    MG.pie(x + w - r, y + r, r, color, pi * 1.5, pi * 2, 6)
    MG.pie(x + w - r, y + h - r, r, color, 0, pi * 0.5, 6)
    MG.pie(x + r, y + h - r, r, color, pi * 0.5, pi, 6)
end

-- ---------------------------------------------------------------- bejelentkezes
function MG.register(def) MG.games[#MG.games + 1] = def end

function MG.isPlaying() return MG.current ~= nil end

function MG.stop()
    MG.current = nil
end

function MG.start(def)
    MG.current = def
    def.reset()
end

-- ---------------------------------------------------------------- menu
local cardW, cardH, gap = U(250), U(250), U(30)
local hover

local function cardRect(i)
    local n = #MG.games
    local total = n * cardW + (n - 1) * gap
    return sw / 2 - total / 2 + (i - 1) * (cardW + gap), MG.menuY or sh * 0.45
end

local function inRect(mx, my, x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end

local function cursorPx()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * sw, cy * sh
end

local backRect = { U(30), U(30), U(130), U(42) }

function MG.drawMenu(y)
    MG.menuY = y
    local mx, my = cursorPx()
    hover = nil
    local titleY = y - U(70)
    MG.text(MG.T("ui_download.mg.title"), 0, titleY, sw, U(34), tocolor(255, 255, 255), U(1.6), "default-bold")
    MG.text(MG.T("ui_download.mg.subtitle"), 0, titleY + U(32), sw, U(24), tocolor(200, 200, 200, 220), U(1.0), "default")

    for i, g in ipairs(MG.games) do
        local x, cy = cardRect(i)
        local over = inRect(mx, my, x, cy, cardW, cardH)
        if over then hover = g end
        MG.roundRect(x, cy, cardW, cardH, U(14), over and tocolor(40, 40, 60, 235) or tocolor(10, 10, 20, 205))
        -- ikon-teruelet
        local ix, iy, is = x + cardW / 2, cy + U(78), U(46)
        g.icon(ix, iy, is)
        MG.text(L(g.nameKey), x, cy + U(135), cardW, U(30), g.color, U(1.5), "default-bold")
        MG.text(L(g.descKey), x + U(14), cy + U(168), cardW - U(28), U(70), tocolor(215, 215, 215), U(1.0), "default")
        if over then
            MG.rect(x + U(14), cy + cardH - U(5), cardW - U(28), U(3), g.color)
        end
    end
end

function MG.drawBackButton()
    local mx, my = cursorPx()
    local x, y, w, h = unpack(backRect)
    local over = inRect(mx, my, x, y, w, h)
    MG.roundRect(x, y, w, h, U(8), over and tocolor(60, 60, 90, 240) or tocolor(10, 10, 20, 210))
    MG.text("< " .. L("ui_download.mg.back"), x, y, w, h, tocolor(255, 255, 255), U(1.1), "default-bold")
end

-- ---------------------------------------------------------------- fo rajzolas
local lastTick

-- y: ahol a menu kartyak kezdodnek, bottom: a jatekterulet also hatara
function MG.draw(menuY, bottom)
    if not MG.allowed() then
        if MG.current then MG.stop() end
        return false
    end
    local now = getTickCount()
    local dt = lastTick and math.min((now - lastTick) / 1000, 0.1) or 0
    lastTick = now

    local g = MG.current
    if g then
        g.update(dt)
        g.draw(sw / 2, U(40), sw, bottom - U(40))
        MG.drawBackButton()
    else
        MG.drawMenu(menuY)
    end
    return g ~= nil
end

-- ---------------------------------------------------------------- bemenet
addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not MG.allowed() then return end
    local mx, my = cursorPx()
    if MG.current then
        local x, y, w, h = unpack(backRect)
        if inRect(mx, my, x, y, w, h) then
            MG.stop()
        elseif MG.current.click then
            MG.current.click(mx, my)
        end
        return
    end
    for i, g in ipairs(MG.games) do
        local x, cy = cardRect(i)
        if inRect(mx, my, x, cy, cardW, cardH) then
            MG.start(g)
            return
        end
    end
end)

local KEYMAP = {
    arrow_u = "up", w = "up", arrow_d = "down", s = "down",
    arrow_l = "left", a = "left", arrow_r = "right", d = "right",
}

addEventHandler("onClientKey", root, function(key, press)
    if not press or not MG.current or not MG.allowed() then return end
    if key == "backspace" then
        MG.stop()
        cancelEvent()
        return
    end
    local act = KEYMAP[key]
    if key == "enter" or key == "space" then act = "action" end
    if act and MG.current.key then
        MG.current.key(act)
        cancelEvent()
    end
end)
