--[[
    v_socialpanel / c_controls.lua
    Immediate-mode UI keszlet (gomb, szovegmezo, gorgetes) + a panel be/ki kapcsolasa.

    A regi Button OOP osztaly es a "minden gombot vegigprobalo" klikk-kezeles helyett
    minden widget csak akkor letezik / kap kattintast, amikor tenylegesen kirajzoljuk.
    Ez megszunteti azt a hibat, hogy az atfedo, lathatatlan gombok is elsultek.
]]

UI = {}

local sw, sh = guiGetScreenSize()

-- Egy frame-re "elkapott" bal-kattintas.
local pendingClick = false
local wheelDelta = 0

UI._click = false
UI.fields = {}          -- fields[id] = { text = "" }
UI.activeField = nil

--------------------------------------------------------------------------------
-- Frame eleje: a render loop hivja
--------------------------------------------------------------------------------

function UI.beginFrame()
    UI._click = pendingClick
    pendingClick = false
    UI._wheel = wheelDelta
    wheelDelta = 0
    local cx, cy = getCursorPosition()
    UI.mx = (cx or 0) * sw
    UI.my = (cy or 0) * sh
    UI._clickConsumed = false
end

local function inside(x, y, w, h)
    return UI.mx >= x and UI.mx <= x + w and UI.my >= y and UI.my <= y + h
end
UI.inside = inside

-- Igaz, ha ebben a frame-ben ide kattintottak (es meg senki nem "ette meg").
local function clickedIn(x, y, w, h)
    if UI._click and not UI._clickConsumed and inside(x, y, w, h) then
        UI._clickConsumed = true
        return true
    end
    return false
end
UI.clickedIn = clickedIn

--------------------------------------------------------------------------------
-- Widgetek
--------------------------------------------------------------------------------

function UI.rect(x, y, w, h, color)
    dxDrawRectangle(x, y, w, h, color)
end

function UI.text(str, x, y, w, h, color, size, font, alignX, alignY)
    dxDrawText(tostring(str), x, y, x + (w or 0), y + (h or 0), color or tocolor(0, 0, 0, 255),
        size or 1, font or "default", alignX or "left", alignY or "top", false, false, false, true)
end

-- opts: size, font, bg, txt, hoverBg, hoverTxt, disabled, selected, selBg, selTxt, align
-- "selected": a betuszin selTxt (alapbol sarga); a hatter csak akkor valtozik,
-- ha kifejezetten megadsz selBg-t (pl. a fuggoleges menu feher jeloleset megtartva).
function UI.button(x, y, w, h, label, opts)
    opts = opts or {}
    local hover = inside(x, y, w, h) and not opts.disabled
    local bg  = opts.bg  or tocolor(255, 255, 255, 255)
    local txt = opts.txt or tocolor(0, 0, 0, 255)
    if opts.selected then
        if opts.selBg then bg = opts.selBg end
        txt = opts.selTxt or tocolor(255, 200, 0, 255)
    elseif hover then
        bg  = opts.hoverBg  or tocolor(255, 200, 0, 255)
        txt = opts.hoverTxt or tocolor(0, 0, 0, 255)
    end
    if opts.disabled then
        bg  = tocolor(210, 210, 210, 255)
        txt = tocolor(150, 150, 150, 255)
    end
    dxDrawRectangle(x, y, w, h, bg)
    dxDrawText(tostring(label), x + 6, y, x + w - 6, y + h, txt,
        opts.size or 1.4, opts.font or "default", opts.align or "center", "center", false, false, false, true)
    if opts.disabled then return false end
    return clickedIn(x, y, w, h)
end

--------------------------------------------------------------------------------
-- Szovegmezo
--------------------------------------------------------------------------------

-- opts: size, font, placeholder, max, numeric
-- Visszaad: text, enterPressed
function UI.input(id, x, y, w, h, opts)
    opts = opts or {}
    local field = UI.fields[id]
    if not field then
        field = { text = "" }
        UI.fields[id] = field
    end

    if clickedIn(x, y, w, h) then
        UI.activeField = id
    elseif UI._click and not UI._clickConsumed and UI.activeField == id and not inside(x, y, w, h) then
        UI.activeField = nil
    end

    local active = UI.activeField == id
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 255))
    dxDrawRectangle(x, y, w, h, active and tocolor(255, 200, 0, 40) or tocolor(0, 0, 0, 0))
    dxDrawRectangle(x, y + h - 2, w, 2, active and tocolor(255, 200, 0, 255) or tocolor(180, 180, 180, 255))

    local shown = field.text
    local color = tocolor(20, 20, 20, 255)
    if shown == "" and not active then
        shown = opts.placeholder or ""
        color = tocolor(150, 150, 150, 255)
    end
    if active and (getTickCount() % 1000) < 500 then
        shown = shown .. "|"
    end
    dxDrawText(shown, x + 6, y, x + w - 6, y + h, color, opts.size or 1.3, opts.font or "default",
        "left", "center", false, false, false, true)

    local entered = field._enter
    field._enter = false
    return field.text, entered
end

function UI.setInput(id, value)
    UI.fields[id] = UI.fields[id] or { text = "" }
    UI.fields[id].text = tostring(value or "")
end

function UI.clearInput(id)
    if UI.fields[id] then UI.fields[id].text = "" end
end

--------------------------------------------------------------------------------
-- Egyszeru fuggoleges gorgetes
--------------------------------------------------------------------------------

UI.scroll = {}

-- Kirajzolas elott hivd: beallitja a gorgetes offszetet a tartalom magassaga szerint.
-- Visszaad: offset (px, >= 0)
function UI.beginScroll(id, x, y, w, h, contentHeight)
    local s = UI.scroll[id] or 0
    local maxScroll = math.max(0, contentHeight - h)
    if inside(x, y, w, h) and UI._wheel ~= 0 then
        s = s - UI._wheel * 40
    end
    s = math.max(0, math.min(maxScroll, s))
    UI.scroll[id] = s
    if maxScroll > 0 then
        local barH = math.max(24, h * (h / contentHeight))
        local barY = y + (h - barH) * (s / maxScroll)
        dxDrawRectangle(x + w - 4, y, 4, h, tocolor(0, 0, 0, 30))
        dxDrawRectangle(x + w - 4, barY, 4, barH, tocolor(0, 0, 0, 120))
    end
    return s
end

--------------------------------------------------------------------------------
-- Input esemenyek
--------------------------------------------------------------------------------

addEventHandler("onClientClick", root, function(button, state)
    if button == "left" and state == "down" and show_socialpanel then
        pendingClick = true
    end
end)

addEventHandler("onClientCharacter", root, function(char)
    if not show_socialpanel or not UI.activeField then return end
    local field = UI.fields[UI.activeField]
    if not field then return end
    local max = 32
    if #field.text >= max then return end
    if char:byte() >= 32 then
        field.text = field.text .. char
    end
end)

-- Tartja szinkronban a globalis flaget es az element datat (mas resource-ok,
-- pl. az ui_pause, ebbol tudjak, hogy a social panel aktiv).
local function setSocialPanel(open)
    show_socialpanel = open
    setElementData(localPlayer, "socialPanelOpen", open, false)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setElementData(localPlayer, "socialPanelOpen", false, false)
end)

-- Panelek kozotti osszeferhetetlenseg: a social panel nem nyilhat meg, ha mar
-- egy masik panel (INAC menu, telefon) vagy a chat input aktiv, illetve ha a
-- jatekos a pause menuben van. (Zarni mindig lehet.)
local function otherPanelOpen()
    return getElementData(localPlayer, "interactionMenuOpen")
        or getElementData(localPlayer, "phoneOpen")
        or getElementData(localPlayer, "showChatInput")
        or getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "reportPanelOpen")
end

addEventHandler("onClientKey", root, function(key, press)
    -- Panel nyitas / zaras
    if press and (key == "home" or key == "num_7") then
        if not show_socialpanel and otherPanelOpen() then return end
        cancelEvent()
        setSocialPanel(not show_socialpanel)
        showCursor(show_socialpanel)
        if show_socialpanel then
            content_id = 1
            triggerServerEvent("sp:pull", localPlayer)
        else
            UI.activeField = nil
        end
        return
    end
    if press and key == "escape" and show_socialpanel then
        cancelEvent()
        setSocialPanel(false)
        showCursor(false)
        UI.activeField = nil
        return
    end

    if not show_socialpanel then return end

    -- Gorgetes
    if press and key == "mouse_wheel_up" then wheelDelta = wheelDelta + 1 end
    if press and key == "mouse_wheel_down" then wheelDelta = wheelDelta - 1 end

    -- Szovegmezo szerkesztes: elnyeljuk a billentyut, hogy ne sussenek el a jatek-binds-ek.
    if UI.activeField then
        local field = UI.fields[UI.activeField]
        if field and press then
            if key == "backspace" then
                field.text = field.text:sub(1, -2)
                cancelEvent()
            elseif key == "enter" then
                field._enter = true
                cancelEvent()
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if show_socialpanel then showCursor(false) end
    setElementData(localPlayer, "socialPanelOpen", false, false)
end)
