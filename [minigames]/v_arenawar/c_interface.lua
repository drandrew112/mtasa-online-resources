if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
local isArenaPanelVisible = false
local arenaPlayerCount = 0

uicore = exports.ui_core
local sw, sh = guiGetScreenSize()
local w,h = 540,400

local arenaDescription = ""   -- set once the player is loaded (loadTexts below)

--------------------------------------------------------------------------------
-- theme / drawing helpers
--------------------------------------------------------------------------------

local function rgba(r,g,b,a) return {r=r,g=g,b=b,a=a} end
local function col(c) return tocolor(c.r, c.g, c.b, c.a) end
local function lerp(a,b,t) return a + (b - a) * t end
local function lerpCol(c1, c2, t)
    return tocolor(lerp(c1.r,c2.r,t), lerp(c1.g,c2.g,t), lerp(c1.b,c2.b,t), lerp(c1.a,c2.a,t))
end

local THEME = {
    bg        = rgba(14, 14, 19, 235),
    shadow    = rgba(0, 0, 0, 130),
    border    = rgba(255, 255, 255, 22),
    accent    = rgba(204, 0, 255, 255),
    accentDim = rgba(204, 0, 255, 55),
    accent2   = rgba(0, 170, 255, 255),
    good      = rgba(40, 200, 130, 255),
    goodDim   = rgba(25, 110, 80, 255),
    bad       = rgba(230, 70, 70, 255),
    badDim    = rgba(140, 45, 45, 255),
    text      = rgba(240, 240, 245, 255),
    textDim   = rgba(165, 168, 178, 255),
}

-- card container: soft shadow + hairline border + coloured top accent strip
local function drawCard(x, y, cw, ch, accentColor)
    dxDrawRectangle(x + 4, y + 6, cw, ch, col(THEME.shadow))
    dxDrawRectangle(x - 1, y - 1, cw + 2, ch + 2, col(THEME.border))
    dxDrawRectangle(x, y, cw, ch, col(THEME.bg))
    dxDrawRectangle(x, y, cw, 3, accentColor or col(THEME.accent))
end

local function drawButton(x, y, bw, bh, label, hovered, kind)
    local base, dim = THEME.accent, THEME.accentDim
    if kind == "good" then base, dim = THEME.good, THEME.goodDim
    elseif kind == "bad" then base, dim = THEME.bad, THEME.badDim end

    dxDrawRectangle(x + 2, y + 3, bw, bh, col(THEME.shadow))
    dxDrawRectangle(x, y, bw, bh, hovered and col(base) or lerpCol(dim, base, 0.35))
    dxDrawRectangle(x, y, bw, hovered and 3 or 2, tocolor(255, 255, 255, hovered and 90 or 40))
    dxDrawText(label, x, y, x + bw, y + bh, tocolor(255, 255, 255, 255), 1.05, "default-bold", "center", "center")
end

--------------------------------------------------------------------------------
-- arena entry panel
--------------------------------------------------------------------------------

local fx, fy = sw/2 - w/2, sh/2 - h/2
local margin, gap, btnH = 18, 16, 46
local btnW = (w - margin*2 - gap) / 2

local buttons = {}
local function build_buttons()
buttons = {
    {label = L("v_arenawar.interface.play"), x = fx+margin, y = fy+h-margin-btnH, width = btnW, height = btnH, kind = "good", action = function() triggerServerEvent("enterArena", localPlayer, localPlayer) toggleArenaPanel() end},
    {label = L("v_arenawar.interface.close"), x = fx+margin+btnW+gap, y = fy+h-margin-btnH, width = btnW, height = btnH, kind = "bad", action = function () toggleArenaPanel() end}
}
end

function toggleArenaPanel()
    if isArenaPanelVisible then
        removeEventHandler("onClientRender", root, renderArenaPanel)
        showCursor(false)
    else
        addEventHandler("onClientRender", root, renderArenaPanel)
        showCursor(true)
    end
    isArenaPanelVisible = not isArenaPanelVisible
end

function renderArenaPanel()
    drawCard(fx, fy, w, h, col(THEME.accent))

    dxDrawText(L("v_arenawar.interface.welcome_to_arenawar"), fx+20, fy+16, fx+w-20, fy+46, col(THEME.text), 1.5, "default-bold", "left", "top")

    local badge = L("v_arenawar.interface.players_in_arena", { arena_player_count = arenaPlayerCount })
    local bw = L.width(badge, 0.95, "default-bold") + 24
    local bx, by, bh = fx+w-20-bw, fy+18, 24
    dxDrawRectangle(bx, by, bw, bh, col(THEME.accentDim))
    dxDrawRectangle(bx, by, bw, 2, col(THEME.accent))
    dxDrawText(badge, bx, by, bx+bw, by+bh, col(THEME.text), 0.95, "default-bold", "center", "center")

    dxDrawRectangle(fx+20, fy+56, w-40, 1, col(THEME.border))

    dxDrawText(arenaDescription, fx+20, fy+70, fx+w-20, fy+h-margin-btnH-14, col(THEME.textDim), 1.3, "default", "left", "top", true, true)

    for _, button in ipairs(buttons) do
        local hovered = isMouseInPosition(button.x, button.y, button.width, button.height)
        drawButton(button.x, button.y, button.width, button.height, button.label, hovered, button.kind)
    end
end

function isMouseInPosition(x, y, width, height)
    if not isCursorShowing() then return false end
    local mx, my = getCursorPosition()
    mx, my = mx * sw, my * sh
    return mx >= x and mx <= x + width and my >= y and my <= y + height
end

function renderMarkerInfo()
    if not isArenaPanelVisible then
        local text = L("v_arenawar.interface.press_e_to_open_arenawar_panel")
        local tw = L.width(text, 1.05, "default-bold")
        local pad = 14
        local pw, ph = tw + pad*2, 30
        local px, py = sw/2 - pw/2, 22

        dxDrawRectangle(px+2, py+3, pw, ph, col(THEME.shadow))
        dxDrawRectangle(px-1, py-1, pw+2, ph+2, col(THEME.border))
        dxDrawRectangle(px, py, pw, ph, col(THEME.bg))
        dxDrawRectangle(px, py, 3, ph, col(THEME.accent))
        dxDrawText(text, px, py, px+pw, py+ph, col(THEME.text), 1.05, "default-bold", "center", "center")
    end
end

function onArenaMarkerHit(hitPlayer)
    if hitPlayer == localPlayer and getElementData(source, "arenawar_marker")==true and getElementData(source, "func") == "entermarker" then
        bindKey("E", "down", toggleArenaPanel)
        addEventHandler("onClientClick", root, onClientClickArenaPanel)
        addEventHandler("onClientRender", root, renderMarkerInfo)
    end
end
function onArenaMarkerLeave(leavePlayer)
    if leavePlayer == localPlayer and getElementData(source, "arenawar_marker")==true and getElementData(source, "func") == "entermarker" then
        unbindKey("E", "down", toggleArenaPanel)
        removeEventHandler("onClientClick", root, onClientClickArenaPanel)
        removeEventHandler("onClientRender", root, renderMarkerInfo)
        if isArenaPanelVisible then
            toggleArenaPanel()
        end
    end
end

function onClientClickArenaPanel(button, state)
    if isArenaPanelVisible then
        if button == "left" and state == "up" then
            for _, button in ipairs(buttons) do
                local btnX, btnY, btnW, btnH = button.x, button.y, button.width, button.height
                if isMouseInPosition(btnX, btnY, btnW, btnH) then
                    button.action()
                    break
                end
            end
        end
    end
end

addEvent("updateArenaPlayerCount", true)
addEventHandler("updateArenaPlayerCount", root, function(count)
    arenaPlayerCount = count
end)

addEventHandler("onClientMarkerHit", root, onArenaMarkerHit)
addEventHandler("onClientMarkerLeave", root, onArenaMarkerLeave)

-- -- --

local isEliminationPanelVisible = false
local ew,eh = 400,150

local efx, efy = sw/2 - ew/2, sh/4 - eh/2
local emargin, egap, ebtnH = 18, 16, 46
local ebtnW = (ew - emargin*2 - egap) / 2

local eliminationButtons = {
    {label = "1  CONTINUE", key = "1", x = efx+emargin, y = efy+eh-emargin-ebtnH, width = ebtnW, height = ebtnH, kind = "good", action = function() toggleEliminationPanel() triggerServerEvent("continueGame", localPlayer, localPlayer) end},
    {label = "2  EXIT", key = "2", x = efx+emargin+ebtnW+egap, y = efy+eh-emargin-ebtnH, width = ebtnW, height = ebtnH, kind = "bad", action = function() toggleEliminationPanel() triggerServerEvent("exitArena", localPlayer, localPlayer, 2) end}
}

function toggleEliminationPanel()
    if isEliminationPanelVisible then
        showCursor(false)
    else
        showCursor(true)
    end
    isEliminationPanelVisible = not isEliminationPanelVisible
end

function renderEliminationPanel()
    if isEliminationPanelVisible then
        drawCard(efx, efy, ew, eh, col(THEME.accent))
        dxDrawText(L("v_arenawar.interface.do_you_want_to_continue"), efx+20, efy+20, efx+ew-20, efy+56, col(THEME.text), 1.3, "default-bold", "center", "top")

        for _, button in ipairs(eliminationButtons) do
            local hovered = isMouseInPosition(button.x, button.y, button.width, button.height)
            drawButton(button.x, button.y, button.width, button.height, button.label, hovered, button.kind)
        end
    elseif getElementData(localPlayer, "arenawar_died") then
        local timeleft = getElementData(localPlayer, "arenawar_died_timeleft") or "?"
        local text = L("v_arenawar.interface.time_to_revive", { timeleft = timeleft })
        local tw, th = 240, 52
        local tx, ty = sw/2 - tw/2, sh/4 - th/2
        drawCard(tx, ty, tw, th, col(THEME.accent2))
        dxDrawText(text, tx, ty, tx+tw, ty+th, col(THEME.text), 1.2, "default-bold", "center", "center")
    end
end
addEventHandler("onClientRender", root, renderEliminationPanel)

function onClientClickEliminationPanel(button, state)
    if isEliminationPanelVisible then
        if button == "left" and state == "up" then
            for _, button in ipairs(eliminationButtons) do
                local btnX, btnY, btnW, btnH = button.x, button.y, button.width, button.height
                if isMouseInPosition(btnX, btnY, btnW, btnH) then
                    button.action()
                    break
                end
            end
        end
    end
end

-- Event handler to show elimination panel when player is eliminated
addEvent("playerEliminated", true)
addEventHandler("playerEliminated", root, function()
    toggleEliminationPanel()
end)

-- Add event handler for clicking on the elimination panel buttons
addEventHandler("onClientClick", root, onClientClickEliminationPanel)

-- Allow choosing with the number keys: 1 = CONTINUE, 2 = EXIT
addEventHandler("onClientKey", root, function(button, press)
    if not press or not isEliminationPanelVisible then return end
    for _, b in ipairs(eliminationButtons) do
        if button == b.key or button == ("num_"..b.key) then
            b.action()
            return
        end
    end
end)

-- Texts load only once the player is loaded (v_accounts loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    arenaDescription = L("v_arenawar.interface.arenawar_is_vehicle_deathmatch_fought_inside")
    build_buttons()
    exports.v_accounts:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
