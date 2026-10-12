if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/report.lua
--  Report system UI (DGS) – player side.
--    /report   – player panel  (Report.*)
--  The admin side (/reports) is the admin panel's Reports tab
--  (client/panel/reports.lua).
--  The server drives every state change via ADMIN.events.report*.
--
--  While a panel is open:
--    * element data "reportPanelOpen" = true  – other resources
--      (pause menu, INAC menu, phone, social panel, chat) stay closed.
--    * right mouse button toggles the cursor: hidden -> the player can
--      walk around, visible again -> back to the panel.
--    * closing a report needs a confirmation click (no accidental close).
-- ============================================================

local DGS    = exports.dgs
local uicore = exports.ui_core

local sw, sh = guiGetScreenSize()

-- Scale from ui_core, clamped so the panels keep a usable minimum size.
local SCALE = math.max(tonumber(uicore:ui(1)) or (sw / 1920), 0.62)
local function u(px) return math.floor(px * SCALE + 0.5) end

local WHITE  = tocolor(255, 255, 255, 255)
local DIM    = tocolor(206, 206, 206, 255)
local RED    = { tocolor(170, 45, 45, 255), tocolor(210, 62, 62, 255), tocolor(140, 35, 35, 255) }
local CLOSEC = { tocolor(200, 40, 40, 255), tocolor(242, 76, 76, 255), tocolor(160, 25, 25, 255) }

local TITLE_H = u(28)

-- ------------------------------------------------------------
--  Shared helpers
-- ------------------------------------------------------------

Report  = { win = nil, report = nil }

local function panelWin(x) return isElement(x) and x or nil end

local function anyPanelVisible()
    return (panelWin(Report.win) and DGS:dgsGetVisible(Report.win)) or false
end

--- One chat line, colour-coded by author.
local function chatLine(who, name, text, playerName)
    if who == "system" or name == "SYSTEM" then
        return "#B0B0B0" .. tostring(text)
    end
    local colour = "#FFC050"                                   -- admin
    if who == "player" or (playerName and name == playerName) then
        colour = "#66C8FF"                                     -- the reporter
    end
    return L("v_admin.report.text", { colour = colour, name = tostring(name), text = tostring(text) })
end

--- Live report messages -> colour-coded text (newest 40 lines).
local function renderChat(messages, playerName)
    messages = messages or {}
    local first = math.max(1, #messages - 40 + 1)
    local out = {}
    for i = first, #messages do
        local m = messages[i]
        out[#out + 1] = "#8A8A8A[" .. (m.time or "--:--") .. "] " ..
            chatLine(m.who, m.name, m.text, playerName)
    end
    return table.concat(out, "\n")
end

--- Enable "#RRGGBB" colour parsing on any DGS text element.
local function colorCoded(el)
    DGS:dgsSetProperty(el, "colorcoded", true)
    return el
end

--- A left-aligned, word-wrapped, clipped, colour-coded label.
local function makeText(x, y, w, h, parent, color, valign)
    local lbl = DGS:dgsCreateLabel(x, y, w, h, "", false, parent, color or WHITE, 1, 1)
    DGS:dgsLabelSetHorizontalAlign(lbl, "left")
    DGS:dgsLabelSetVerticalAlign(lbl, valign or "center")
    DGS:dgsSetProperty(lbl, "colorcoded", true)
    DGS:dgsSetProperty(lbl, "wordbreak", true)
    DGS:dgsSetProperty(lbl, "clip", true)
    return lbl
end

--- The chat log: a bottom-anchored wrapped label over a dark panel.
--- (A DGS memo does NOT colour-code its body text, hence a label.)
local function makeChatLog(x, y, w, h, parent)
    local bg  = DGS:dgsCreateImage(x, y, w, h, nil, false, parent, tocolor(0, 0, 0, 75))
    local lbl = makeText(x + u(6), y + u(4), w - u(12), h - u(8), parent, tocolor(233, 233, 233, 255), "bottom")
    return lbl, bg
end

--- Movable, non-sizable window; the close button only *hides* the panel.
local function makeWindow(w, h, title)
    local x = math.max(u(8), math.floor((sw - w) / 2))
    local y = math.max(u(8), math.floor((sh - h) / 2))

    local win = DGS:dgsCreateWindow(x, y, w, h, title, false, WHITE, TITLE_H)
    DGS:dgsWindowSetSizable(win, false)
    DGS:dgsWindowSetMovable(win, true)
    colorCoded(win)

    local cb = DGS:dgsWindowGetCloseButton(win)
    if isElement(cb) then
        DGS:dgsSetProperty(cb, "color", { CLOSEC[1], CLOSEC[2], CLOSEC[3] })
        DGS:dgsSetProperty(cb, "textColor", WHITE)
        DGS:dgsSetProperty(cb, "font", "default-bold")
        DGS:dgsSetText(cb, "X")
    end

    addEventHandler("onDgsWindowClose", win, function()
        cancelEvent()                 -- never destroy, just hide
        DGS:dgsSetVisible(win, false)
        updatePanelEnv()
    end)

    return win
end

-- DGS's own click events (onDgsMouseClick / ...Up) turned out to fire on the
-- wrong element after fast mouse moves and on title-bar clicks, causing buttons
-- to trigger each other. So we do our own hit-testing on onClientClick instead:
-- a button fires only when the press AND the release land inside its current
-- screen rectangle, and it is visible + enabled.
local clickTargets = {}          -- { { el = <dgs button>, fn = <function> }, ... }
local armedClick   = nil

local function onClick(btn, fn)
    clickTargets[#clickTargets + 1] = { el = btn, fn = fn }
end

local function hitClickTarget(sx, sy)
    for _, t in ipairs(clickTargets) do
        local el  = t.el
        local win = isElement(el) and DGS:dgsGetParent(el) or nil
        if win and DGS:dgsGetVisible(win) and DGS:dgsGetVisible(el) and DGS:dgsGetEnabled(el) then
            local lx, ly = DGS:dgsGetPosition(el, false)   -- local coords inside the window
            local w,  h  = DGS:dgsGetSize(el, false)
            local wx, wy = DGS:dgsGetPosition(win, false)  -- window's screen position
            if lx and w and wx then
                local x = wx + lx
                local y = wy + TITLE_H + ly                -- children sit below the title bar
                if sx >= x and sx < x + w and sy >= y and sy < y + h then
                    return t
                end
            end
        end
    end
    return nil
end

addEventHandler("onClientClick", root, function(button, state, sx, sy)
    if button ~= "left" then return end
    if not anyPanelVisible() then armedClick = nil return end

    local hit = hitClickTarget(sx, sy)
    if state == "down" then
        armedClick = hit
    elseif state == "up" then
        if hit and hit == armedClick then hit.fn() end
        armedClick = nil
    end
end)

--- Wire a button as a two-step "confirm" action so a stray click can't fire it.
local function armButton(btn, label, armedLabel, onConfirm)
    local armed, timer
    local function disarm()
        armed = false
        if isTimer(timer) then killTimer(timer) end
        if isElement(btn) then DGS:dgsSetText(btn, label) end
    end
    onClick(btn, function()
        if not armed then
            armed = true
            DGS:dgsSetText(btn, armedLabel)
            if isTimer(timer) then killTimer(timer) end
            timer = setTimer(disarm, 3000, 1)
            return
        end
        disarm()
        onConfirm()
    end)
    return disarm
end

-- ------------------------------------------------------------
--  Cursor / input environment
-- ------------------------------------------------------------

local mouse2Bound  = false
local cursorHidden = false

--- Right mouse button: hide the cursor so the player can move; press
--- again to bring it back. Only while a panel is on screen.
local function toggleReportCursor()
    if not anyPanelVisible() then return end
    cursorHidden = not cursorHidden
    showCursor(not cursorHidden)
    uicore:toggleMoveControls(cursorHidden)
end

function updatePanelEnv()
    local open = anyPanelVisible()
    setElementData(localPlayer, "reportPanelOpen", open, false)

    if open then
        cursorHidden = false
        showCursor(true)
        uicore:toggleMoveControls(false)
        guiSetInputMode("no_binds_when_editing")
        if not mouse2Bound then
            bindKey("mouse2", "down", toggleReportCursor)
            mouse2Bound = true
        end
    else
        cursorHidden = false
        showCursor(false)
        uicore:toggleMoveControls(true)
        guiSetInputMode("allow_binds")
        if mouse2Bound then
            unbindKey("mouse2", "down", toggleReportCursor)
            mouse2Bound = false
        end
    end
end

local function hideAllPanels()
    if panelWin(Report.win) then DGS:dgsSetVisible(Report.win, false) end
    updatePanelEnv()
end

addEventHandler("onClientKey", root, function(key, press)
    if not press or key ~= "escape" then return end
    if anyPanelVisible() then
        cancelEvent()
        hideAllPanels()
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setElementData(localPlayer, "reportPanelOpen", false, false)
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    setElementData(localPlayer, "reportPanelOpen", false, false)
end)

-- ============================================================
--  PLAYER PANEL  –  /report
-- ============================================================

local resetPlayerClose

local function buildReportPanel()
    local W, H  = u(500), u(470)
    local pad   = u(16)
    local iw    = W - pad * 2
    local CH    = H - TITLE_H          -- child coordinate space (below the title bar)
    local top   = pad
    local btnH  = u(36)
    local rowH  = u(32)

    local win = makeWindow(W, H, L("v_admin.report.title"))
    Report.win = win

    local bottomY = CH - pad - btnH
    local inputY  = bottomY - u(12) - rowH

    -- --- "no report yet" view ------------------------------------------
    Report.newHint = makeText(pad, top, iw, u(74), win, DIM, "top")
    DGS:dgsSetText(Report.newHint,
        L("v_admin.report.describe_your_problem_below_and_press"))

    Report.newInput = DGS:dgsCreateMemo(pad, top + u(82), iw, bottomY - u(12) - (top + u(82)), "", false, win)
    DGS:dgsMemoSetWordWrapState(Report.newInput, true)
    DGS:dgsMemoSetMaxLength(Report.newInput, 300)

    Report.sendNew = DGS:dgsCreateButton(pad, bottomY, iw, btnH, L("v_admin.report.call_admin"), false, win, WHITE)

    -- --- "active report" view ----------------------------------------
    Report.status = makeText(pad, top, iw, u(20), win, WHITE)

    Report.chat, Report.chatBg = makeChatLog(pad, top + u(26), iw, inputY - u(10) - (top + u(26)), win)

    local sendW = u(84)
    Report.input = DGS:dgsCreateEdit(pad, inputY, iw - sendW - u(6), rowH, "", false, win, WHITE)
    DGS:dgsEditSetMaxLength(Report.input, 300)
    Report.send  = DGS:dgsCreateButton(pad + iw - sendW, inputY, sendW, rowH, L("common.send"), false, win, WHITE)

    Report.close = DGS:dgsCreateButton(pad, bottomY, iw, btnH, L("v_admin.reports.close_report"), false, win, WHITE,
        1, 1, nil, nil, nil, RED[1], RED[2], RED[3])

    -- --- events -----------------------------------------------------
    local function submitNew()
        local text = DGS:dgsGetText(Report.newInput)
        if not text or text:gsub("%s", "") == "" then return end
        triggerServerEvent(ADMIN.events.reportCreate, localPlayer, text)
    end
    onClick(Report.sendNew, submitNew)

    local function submitMsg()
        if not Report.report then return end
        local text = DGS:dgsGetText(Report.input)
        if not text or text:gsub("%s", "") == "" then return end
        triggerServerEvent(ADMIN.events.reportMsg, localPlayer, Report.report.id, text)
        DGS:dgsSetText(Report.input, "")
    end
    onClick(Report.send, submitMsg)
    addEventHandler("onDgsEditAccepted", Report.input, submitMsg)

    resetPlayerClose = armButton(Report.close, L("v_admin.reports.close_report"), L("v_admin.report.click_again_to_confirm"), function()
        if Report.report then
            triggerServerEvent(ADMIN.events.reportClose, localPlayer, Report.report.id)
        end
    end)
end

--- Toggle between the "new report" and "active report" widgets.
local function setReportState(report)
    Report.report = report or nil
    local active = report ~= nil

    for _, e in ipairs({ Report.newHint, Report.newInput, Report.sendNew }) do
        DGS:dgsSetVisible(e, not active)
    end
    for _, e in ipairs({ Report.status, Report.chat, Report.chatBg, Report.input, Report.send, Report.close }) do
        DGS:dgsSetVisible(e, active)
    end

    if resetPlayerClose then resetPlayerClose() end

    if active then
        if report.status == "claimed" then
            DGS:dgsSetText(Report.status, L("v_admin.report.claimed_by", { claimed_by_name = tostring(report.claimedByName) }))
        else
            DGS:dgsSetText(Report.status, L("v_admin.report.waiting_for_admin_to_respond"))
        end
        DGS:dgsSetText(Report.chat, renderChat(report.messages, report.playerName))
    else
        DGS:dgsSetText(Report.newInput, "")
    end
end

local function openReportPanel(report)
    if not panelWin(Report.win) then buildReportPanel() end
    setReportState(report or nil)
    DGS:dgsSetVisible(Report.win, true)
    DGS:dgsBringToFront(Report.win)
    updatePanelEnv()
end

addEvent(ADMIN.events.reportOpen, true)
addEventHandler(ADMIN.events.reportOpen, root, function(report)
    openReportPanel(report or nil)
end)

addEvent(ADMIN.events.reportSync, true)
addEventHandler(ADMIN.events.reportSync, root, function(report)
    if not panelWin(Report.win) then return end
    setReportState(report or nil)
end)

-- ============================================================
--  Sound ping (reuses pmalert.mp3)
-- ============================================================
addEvent(ADMIN.events.reportNotify, true)
addEventHandler(ADMIN.events.reportNotify, localPlayer, function()
    playSound("pmalert.mp3")
end)
