-- ============================================================
--  v_admin / client/report.lua
--  Report system UI (DGS).
--    /report   – player panel  (Report.*)
--    /reports  – admin panel   (Reports.*) : active reports + saved logs
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
local TAB_ON  = { tocolor( 58, 122, 150, 255), tocolor( 74, 146, 176, 255), tocolor( 46, 100, 126, 255) }
local TAB_OFF = { tocolor( 40,  44,  52, 255), tocolor( 56,  62,  72, 255), tocolor( 34,  38,  46, 255) }

local TITLE_H = u(28)

-- ------------------------------------------------------------
--  Shared helpers
-- ------------------------------------------------------------

Report  = { win = nil, report = nil }
Reports = { win = nil, mode = "active", list = {}, selected = nil }

local function panelWin(x) return isElement(x) and x or nil end

local function anyPanelVisible()
    return (panelWin(Report.win)  and DGS:dgsGetVisible(Report.win))
        or (panelWin(Reports.win) and DGS:dgsGetVisible(Reports.win))
        or false
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
    return colour .. tostring(name) .. "#FFFFFF: " .. tostring(text)
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
    if panelWin(Report.win)  then DGS:dgsSetVisible(Report.win, false)  end
    if panelWin(Reports.win) then DGS:dgsSetVisible(Reports.win, false) end
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

    local win = makeWindow(W, H, "REPORT")
    Report.win = win

    local bottomY = CH - pad - btnH
    local inputY  = bottomY - u(12) - rowH

    -- --- "no report yet" view ------------------------------------------
    Report.newHint = makeText(pad, top, iw, u(74), win, DIM, "top")
    DGS:dgsSetText(Report.newHint,
        "#CFCFCFDescribe your problem below and press #FFFFFFCall an admin#CFCFCF.\n" ..
        "An admin gets notified and can chat with you right here.")

    Report.newInput = DGS:dgsCreateMemo(pad, top + u(82), iw, bottomY - u(12) - (top + u(82)), "", false, win)
    DGS:dgsMemoSetWordWrapState(Report.newInput, true)
    DGS:dgsMemoSetMaxLength(Report.newInput, 300)

    Report.sendNew = DGS:dgsCreateButton(pad, bottomY, iw, btnH, "Call an admin", false, win, WHITE)

    -- --- "active report" view ----------------------------------------
    Report.status = makeText(pad, top, iw, u(20), win, WHITE)

    Report.chat, Report.chatBg = makeChatLog(pad, top + u(26), iw, inputY - u(10) - (top + u(26)), win)

    local sendW = u(84)
    Report.input = DGS:dgsCreateEdit(pad, inputY, iw - sendW - u(6), rowH, "", false, win, WHITE)
    DGS:dgsEditSetMaxLength(Report.input, 300)
    Report.send  = DGS:dgsCreateButton(pad + iw - sendW, inputY, sendW, rowH, "Send", false, win, WHITE)

    Report.close = DGS:dgsCreateButton(pad, bottomY, iw, btnH, "Close report", false, win, WHITE,
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

    resetPlayerClose = armButton(Report.close, "Close report", "Click again to confirm", function()
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
            DGS:dgsSetText(Report.status, "#66FF66Claimed by: #FFFFFF" .. tostring(report.claimedByName))
        else
            DGS:dgsSetText(Report.status, "#FFB040Waiting for an admin to respond...")
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
--  ADMIN PANEL  –  /reports
-- ============================================================

local applyActive           -- fwd
local resetAdminClose

local function selectedActive()
    return (Reports.mode == "active") and Reports.selected and Reports.list[Reports.selected] or nil
end

--- Three fixed columns; only their titles change between modes.
local function setColumnTitles(mode)
    if mode == "logs" then
        DGS:dgsGridListSetColumnTitle(Reports.grid, 1, "Date")
        DGS:dgsGridListSetColumnTitle(Reports.grid, 2, "Player")
        DGS:dgsGridListSetColumnTitle(Reports.grid, 3, "Admin")
    else
        DGS:dgsGridListSetColumnTitle(Reports.grid, 1, "#")
        DGS:dgsGridListSetColumnTitle(Reports.grid, 2, "Player")
        DGS:dgsGridListSetColumnTitle(Reports.grid, 3, "Status")
    end
end

--- Highlight the active tab.
local function updateTabs()
    DGS:dgsSetProperty(Reports.tabActive, "color", Reports.mode == "active" and TAB_ON or TAB_OFF)
    DGS:dgsSetProperty(Reports.tabLogs,   "color", Reports.mode == "logs"   and TAB_ON or TAB_OFF)
end

local function setMode(mode)
    Reports.mode     = mode
    Reports.selected = nil
    Reports._selRow  = nil
    updateTabs()
    DGS:dgsGridListClear(Reports.grid)
    setColumnTitles(mode)

    if mode == "logs" then
        DGS:dgsSetText(Reports.header, "#CFCFCFLoading saved logs...")
        triggerServerEvent(ADMIN.events.reportLogList, localPlayer)
    else
        triggerServerEvent(ADMIN.events.reportWantActive, localPlayer)
    end
    Reports.refreshDetail()
end

local function buildReportsPanel()
    local W, H  = u(880), u(500)
    local pad   = u(16)
    local gw    = u(300)
    local rx    = pad + gw + pad
    local rw    = W - rx - pad
    local CH    = H - TITLE_H          -- child coordinate space (below the title bar)
    local top   = pad
    local btnH  = u(34)
    local rowH  = u(32)
    local tabH  = u(28)

    local win = makeWindow(W, H, "REPORTS")
    Reports.win = win

    -- Tab switcher: two side-by-side buttons, the active one highlighted.
    local tabW = math.floor((gw - u(8)) / 2)
    Reports.tabActive = DGS:dgsCreateButton(pad, top, tabW, tabH, "Active cases", false, win, WHITE)
    Reports.tabLogs   = DGS:dgsCreateButton(pad + tabW + u(8), top, gw - tabW - u(8), tabH, "Logs", false, win, WHITE)

    local gridY = top + tabH + u(8)
    Reports.grid = DGS:dgsCreateGridList(pad, gridY, gw, CH - pad - gridY, false, win)
    colorCoded(Reports.grid)
    DGS:dgsGridListAddColumn(Reports.grid, "#",      0.28)
    DGS:dgsGridListAddColumn(Reports.grid, "Player", 0.40)
    DGS:dgsGridListAddColumn(Reports.grid, "Status", 0.30)

    Reports.header    = makeText(rx, top, rw, u(20), win, WHITE)
    Reports.claimInfo = makeText(rx, top + u(24), rw, u(18), win, DIM)

    local btnY   = CH - pad - btnH
    local inputY = btnY - u(8) - rowH
    local chatY  = top + u(48)
    Reports.chat, Reports.chatBg = makeChatLog(rx, chatY, rw, inputY - u(8) - chatY, win)

    -- chat heights: short in the Active tab (leaves room for the action row),
    -- full height in the Logs tab (read-only, no action row).
    Reports._chatW      = rw
    Reports._chatHSmall = inputY - u(8) - chatY
    Reports._chatHFull  = (btnY + btnH) - chatY

    local sendW = u(84)
    Reports.input = DGS:dgsCreateEdit(rx, inputY, rw - sendW - u(6), rowH, "", false, win, WHITE)
    DGS:dgsEditSetMaxLength(Reports.input, 300)
    Reports.send  = DGS:dgsCreateButton(rx + rw - sendW, inputY, sendW, rowH, "Send", false, win, WHITE)

    local bw = math.floor((rw - u(16)) / 3)
    Reports.claim = DGS:dgsCreateButton(rx, btnY, bw, btnH, "Claim", false, win, WHITE)
    Reports.tp    = DGS:dgsCreateButton(rx + bw + u(8), btnY, bw, btnH, "Teleport", false, win, WHITE)
    Reports.close = DGS:dgsCreateButton(rx + (bw + u(8)) * 2, btnY, bw, btnH, "Close", false, win, WHITE,
        1, 1, nil, nil, nil, RED[1], RED[2], RED[3])

    -- --- events -------------------------------------------------
    onClick(Reports.tabActive, function()
        if Reports.mode ~= "active" then setMode("active") end
    end)
    onClick(Reports.tabLogs, function()
        if Reports.mode ~= "logs" then setMode("logs") end
    end)

    -- Grid selection. A stray click on empty grid space fires this with
    -- row -1; we ignore that and restore the previous selection so a
    -- misclick can never lose the open report / log.
    local reselecting = false
    addEventHandler("onDgsGridListSelect", Reports.grid, function()
        if reselecting then return end
        local row = DGS:dgsGridListGetSelectedItem(Reports.grid)

        if not row or row == -1 then
            if Reports._selRow then
                reselecting = true
                DGS:dgsGridListSetSelectedItem(Reports.grid, Reports._selRow, 1)
                reselecting = false
            end
            return
        end

        Reports._selRow = row
        local key = DGS:dgsGridListGetItemData(Reports.grid, row, 1)
        if Reports.mode == "logs" then
            if Reports.selected == key then return end
            Reports.selected = key
            DGS:dgsSetText(Reports.header, "#CFCFCFOpening log...")
            DGS:dgsSetText(Reports.claimInfo, "")
            DGS:dgsSetText(Reports.chat, "")
            triggerServerEvent(ADMIN.events.reportLogOpen, localPlayer, key)
        else
            Reports.selected = tonumber(key) or nil
            Reports.refreshDetail()
        end
    end)

    local function submitMsg()
        local r = selectedActive()
        if not r then return end
        local text = DGS:dgsGetText(Reports.input)
        if not text or text:gsub("%s", "") == "" then return end
        triggerServerEvent(ADMIN.events.reportMsg, localPlayer, r.id, text)
        DGS:dgsSetText(Reports.input, "")
    end
    onClick(Reports.send, submitMsg)
    addEventHandler("onDgsEditAccepted", Reports.input, submitMsg)

    onClick(Reports.claim, function()
        local r = selectedActive()
        if r then triggerServerEvent(ADMIN.events.reportClaim, localPlayer, r.id) end
    end)

    onClick(Reports.tp, function()
        local r = selectedActive()
        if r then triggerServerEvent(ADMIN.events.reportTP, localPlayer, r.id) end
    end)

    resetAdminClose = armButton(Reports.close, "Close", "Confirm close?", function()
        local r = selectedActive()
        if r then triggerServerEvent(ADMIN.events.reportClose, localPlayer, r.id) end
    end)
end

--- Right-hand pane for the current selection.
function Reports.refreshDetail()
    local logs = (Reports.mode == "logs")
    local r    = selectedActive()
    local canAct = (not logs) and (r ~= nil)

    -- The action row (input/send + claim/teleport/close) only exists for live
    -- reports; in the Logs tab it is hidden and the chat fills the freed space.
    for _, e in ipairs({ Reports.input, Reports.send, Reports.claim, Reports.tp, Reports.close }) do
        DGS:dgsSetVisible(e, not logs)
        DGS:dgsSetEnabled(e, canAct)
    end
    if resetAdminClose then resetAdminClose() end

    local ch = logs and Reports._chatHFull or Reports._chatHSmall
    DGS:dgsSetSize(Reports.chatBg, Reports._chatW, ch, false)
    DGS:dgsSetSize(Reports.chat, Reports._chatW - u(12), ch - u(8), false)

    if logs then
        if not Reports.selected then
            DGS:dgsSetText(Reports.header, "#CFCFCFSelect a saved log on the left.")
            DGS:dgsSetText(Reports.claimInfo, "")
            DGS:dgsSetText(Reports.chat, "")
        end
        return
    end

    if not r then
        DGS:dgsSetText(Reports.header, "#CFCFCFSelect a report on the left.")
        DGS:dgsSetText(Reports.claimInfo, "")
        DGS:dgsSetText(Reports.chat, "")
        return
    end

    DGS:dgsSetText(Reports.header, "#FFD37FReport ##FFFFFF" .. r.id ..
        "  #999999|  #FFFFFF" .. r.playerName .. " #FFE066(ID " .. r.playerId .. ")" ..
        (r.online and "" or "  #FF6464(offline)"))

    if r.status == "claimed" then
        DGS:dgsSetText(Reports.claimInfo, "#66FF66Claimed by: #FFFFFF" .. tostring(r.claimedByName))
    else
        DGS:dgsSetText(Reports.claimInfo, "#FFB040Unclaimed")
    end

    DGS:dgsSetEnabled(Reports.tp, r.online)
    DGS:dgsSetText(Reports.chat, renderChat(r.messages, r.playerName))
end

--- Rebuild the grid from a fresh active-report list, keeping the selection.
function applyActive(list)
    if Reports.mode ~= "active" then return end
    local keep = Reports.selected
    Reports.list = {}
    Reports._selRow = nil
    DGS:dgsGridListClear(Reports.grid)

    for _, r in ipairs(list or {}) do
        Reports.list[r.id] = r
        local status = (r.status == "claimed")
            and ("#66FF66" .. (r.claimedByName or "claimed"))
            or  "#FFB040unclaimed"
        local row = DGS:dgsGridListAddRow(Reports.grid, nil, tostring(r.id), r.playerName, status)
        DGS:dgsGridListSetItemData(Reports.grid, row, 1, r.id)
        if keep and r.id == keep then
            Reports._selRow = row
            DGS:dgsGridListSetSelectedItem(Reports.grid, row, 1)
        end
    end

    if not (keep and Reports.list[keep]) then Reports.selected = nil end
    Reports.refreshDetail()
end

local function applyLogs(list)
    if Reports.mode ~= "logs" then return end
    local keep = Reports.selected
    Reports._selRow = nil
    DGS:dgsGridListClear(Reports.grid)
    for _, e in ipairs(list or {}) do
        local row = DGS:dgsGridListAddRow(Reports.grid, nil,
            e.date or "?", e.player or "?", (e.admin ~= "" and e.admin) or "-")
        DGS:dgsGridListSetItemData(Reports.grid, row, 1, e.file)
        if keep and e.file == keep then
            Reports._selRow = row
            DGS:dgsGridListSetSelectedItem(Reports.grid, row, 1)
        end
    end
    if not Reports.selected then
        DGS:dgsSetText(Reports.header, "#CFCFCFSelect a saved log on the left. (" .. #(list or {}) .. ")")
    end
end

local function openReportsPanel(list)
    if not panelWin(Reports.win) then buildReportsPanel() end
    DGS:dgsSetVisible(Reports.win, true)
    DGS:dgsBringToFront(Reports.win)
    Reports.mode = "active"
    Reports.selected = nil
    Reports._selRow = nil
    updateTabs()
    DGS:dgsGridListClear(Reports.grid)
    setColumnTitles("active")
    applyActive(list)
    updatePanelEnv()
end

addEvent(ADMIN.events.reportAdminOpen, true)
addEventHandler(ADMIN.events.reportAdminOpen, root, function(list)
    openReportsPanel(list or {})
end)

addEvent(ADMIN.events.reportAdminList, true)
addEventHandler(ADMIN.events.reportAdminList, root, function(list)
    if not panelWin(Reports.win) or not DGS:dgsGetVisible(Reports.win) then return end
    applyActive(list or {})
end)

addEvent(ADMIN.events.reportLogList, true)
addEventHandler(ADMIN.events.reportLogList, root, function(list)
    if not panelWin(Reports.win) or not DGS:dgsGetVisible(Reports.win) then return end
    applyLogs(list or {})
end)

addEvent(ADMIN.events.reportLogData, true)
addEventHandler(ADMIN.events.reportLogData, root, function(fileName, data)
    if Reports.mode ~= "logs" or Reports.selected ~= fileName then return end
    if type(data) ~= "table" then return end

    local info = data.info or {}
    DGS:dgsSetText(Reports.header, "#FFD37FLog  #FFFFFF" .. tostring(info.player or "?") ..
        "  #999999(" .. tostring(fileName) .. ")")
    if info.adminClaimed and info.adminClaimed ~= "" then
        DGS:dgsSetText(Reports.claimInfo, "#66FF66Claimed by: #FFFFFF" .. tostring(info.adminClaimed))
    else
        DGS:dgsSetText(Reports.claimInfo, "#FFB040Never claimed")
    end

    local lines = {}
    for _, m in ipairs(data.messages or {}) do
        local stamp = (m.time and m.time ~= "") and ("#8A8A8A[" .. m.time .. "] ") or ""
        lines[#lines + 1] = stamp .. chatLine(nil, m.sender, m.text, info.player)
    end
    DGS:dgsSetText(Reports.chat, table.concat(lines, "\n"))
end)

-- ============================================================
--  Sound ping (reuses pmalert.mp3)
-- ============================================================
addEvent(ADMIN.events.reportNotify, true)
addEventHandler(ADMIN.events.reportNotify, localPlayer, function()
    playSound("pmalert.mp3")
end)
