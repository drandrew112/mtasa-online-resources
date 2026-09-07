local screenW, screenH = guiGetScreenSize()
local uicore = exports.ui_core
local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v) return v * SCALE end
local MENU_FRACTION = 0.8
local HEAD_H = S(22)
local INFO_H = S(26)

-- Jobs can only be browsed / joined through the pause menu (ui_pause). This
-- resource owns the waiting-lobby panel (GTA V mission-lobby style) and the
-- client<->server plumbing.
local panel, lobby, selected = nil, nil, 1
-- When open, an "Invite Player" sub-panel over the lobby:
--   { rows = { { name =, player =, sent = bool }, ... }, sel = 1 }
local inviteMenu = nil
local cachedJobs = {}
local cachedLobbies = {}
local nearbyJob = nil

local FONT = { row = "default", rowB = "default-bold", head = "default-bold", title = "default-bold" }

local C = {
    wash    = tocolor(0, 0, 0, 120),
    band    = tocolor(0, 0, 0, 210),
    colHead = tocolor(0, 113, 184, 255),
    row     = tocolor(0, 0, 0, 140),
    rowSep  = tocolor(255, 255, 255, 18),
    rowSel  = tocolor(243, 243, 243, 245),
    rowSelT = tocolor(12, 12, 12, 255),
    txt     = tocolor(235, 235, 235, 255),
    txtDim  = tocolor(152, 156, 161, 255),
    accent  = tocolor(0, 130, 205, 255),
    infobar = tocolor(0, 0, 0, 200),
    startBg = tocolor(70, 150, 220, 170),
}

local function click(name) playSound("assets/sounds/" .. name .. ".wav") end
local function close()
    panel, lobby, inviteMenu = nil, nil, nil
    -- Ha a lobby-belepes fekete fade-je meg tart, ne ragadjon benne a jatekos.
    fadeCamera(true, 0.4)
    showCursor(false)
    uicore:toggleMoveControls(true)
    -- A varo-lobby elrejti a teljes HUD-ot (radar/minimap is); visszakapcsoljuk.
    setElementData(localPlayer, "hideHUD", false)
end

addEvent("jobmanager:jobs", true)
addEventHandler("jobmanager:jobs", resourceRoot, function(data)
    cachedJobs = type(data) == "table" and data or {}
end)

addEvent("jobmanager:lobbies", true)
addEventHandler("jobmanager:lobbies", resourceRoot, function(data)
    cachedLobbies = type(data) == "table" and data or {}
end)

addEvent("jobmanager:lobby", true)
addEventHandler("jobmanager:lobby", resourceRoot, function(data)
    -- A "jobmanager:lobby" minden lobby-valtozaskor ujra megjon (pl. ha masik
    -- jatekos csatlakozik), ezert csak akkor fade-elunk, amikor tenyleg most
    -- lepunk be a lobbyba.
    local justEntered = panel ~= "lobby"
    lobby, selected, inviteMenu = data, 1, nil
    showCursor(false)
    uicore:toggleMoveControls(false)
    -- Lobbyban ne latszodjon a HUD / radar minimap.
    setElementData(localPlayer, "hideHUD", true)

    if not justEntered then
        panel = "lobby"
        return
    end

    -- Belepeskor eloszor feketere fade-elunk, es csak a fekete kepernyo utan
    -- jelenik meg a lobby UI, majd visszafade-elunk.
    local FADE_OUT = 0.4
    fadeCamera(false, FADE_OUT)
    setTimer(function()
        if not lobby then return end
        panel = "lobby"
        fadeCamera(true, 0.6)
    end, FADE_OUT * 1000, 1)
end)

addEvent("jobmanager:invitablePlayers", true)
addEventHandler("jobmanager:invitablePlayers", resourceRoot, function(list)
    if panel ~= "lobby" then return end
    local rows = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        rows[#rows + 1] = { name = e.name, player = e.player, sent = false }
    end
    inviteMenu = { rows = rows, sel = 1 }
end)

addEvent("jobmanager:closeUi", true)
addEventHandler("jobmanager:closeUi", resourceRoot, close)

addEvent("jobmanager:matchStarted", true)
addEventHandler("jobmanager:matchStarted", resourceRoot, close)

addEvent("jobmanager:showJoinHint", true)
addEventHandler("jobmanager:showJoinHint", resourceRoot, function(_, name)
    nearbyJob = name or "this job"
end)

addEvent("jobmanager:hideJoinHint", true)
addEventHandler("jobmanager:hideJoinHint", resourceRoot, function()
    nearbyJob = nil
end)

--------------------------------------------------------------------------------
-- race countdown (3, 2, 1, GO)
--------------------------------------------------------------------------------

local countdownText, countdownUntil = nil, 0

addEvent("jobmanager:raceCountdown", true)
addEventHandler("jobmanager:raceCountdown", resourceRoot, function(value)
    countdownText = tostring(value)
    countdownUntil = getTickCount() + 900
end)

-- setPedCanBeKnockedOffBike only exists client-side, so the server asks us
-- to flip it on/off for ourselves while we're locked into a race vehicle.
addEvent("jobmanager:setKnockOffBike", true)
addEventHandler("jobmanager:setKnockOffBike", resourceRoot, function(canBeKnockedOff)
    setPedCanBeKnockedOffBike(localPlayer, canBeKnockedOff)
end)

--------------------------------------------------------------------------------
-- Public client API used by ui_pause
--------------------------------------------------------------------------------

function jobmanagerRequestJobs()
    triggerServerEvent("jobmanager:requestJobs", resourceRoot)
end

function jobmanagerGetJobs()
    return cachedJobs
end

function jobmanagerRequestLobbies()
    triggerServerEvent("jobmanager:requestLobbies", resourceRoot)
end

function jobmanagerGetLobbies()
    return cachedLobbies
end

function jobmanagerJoinJob(jobId)
    if type(jobId) ~= "string" then return false end
    triggerServerEvent("jobmanager:joinJob", resourceRoot, jobId)
    return true
end

function jobmanagerQuickJob()
    triggerServerEvent("jobmanager:quickJob", resourceRoot)
    return true
end

function jobmanagerJoinLobby(lobbyId)
    if type(lobbyId) ~= "number" then return false end
    triggerServerEvent("jobmanager:joinLobby", resourceRoot, lobbyId)
    return true
end

function jobmanagerInLobby()
    return panel == "lobby"
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStart", resourceRoot, function()
    local function mk(file, px, fallback)
        local f = dxCreateFont(file, px)
        return isElement(f) and f or fallback
    end
    FONT.row   = mk("assets/fonts/Roboto.ttf", 11, "default")
    FONT.rowB  = mk("assets/fonts/RobotoB.ttf", 11, "default-bold")
    FONT.head  = mk("assets/fonts/RobotoB.ttf", 13, "default-bold")
    FONT.title = mk("assets/fonts/RobotoB.ttf", 16, "default-bold")

    jobmanagerRequestJobs()
end)

--------------------------------------------------------------------------------
-- lobby actions (arrows / enter / backspace only)
--------------------------------------------------------------------------------

-- BACKSPACE leaves the lobby, so there is no "Leave Lobby" row. "Start Game"
-- sits at the bottom (host only).
local function lobbyActions()
    if lobby and lobby.isHost then
        return { "Invite Player", "Start Game" }
    end
    return { "Invite Player" }
end

addEventHandler("onClientKey", root, function(key, down)
    if not down or panel ~= "lobby" then return end

    -- "Invite Player" sub-panel swallows navigation while it is open.
    if inviteMenu then
        local rows = inviteMenu.rows
        if key == "backspace" then
            cancelEvent()
            inviteMenu = nil; click("select")
        elseif key == "arrow_u" then
            inviteMenu.sel = math.max(1, inviteMenu.sel - 1); click("select")
        elseif key == "arrow_d" then
            inviteMenu.sel = math.min(math.max(#rows, 1), inviteMenu.sel + 1); click("select")
        elseif key == "enter" then
            cancelEvent()
            local row = rows[inviteMenu.sel]
            if row and not row.sent and isElement(row.player) then
                row.sent = true
                click("click")
                triggerServerEvent("jobmanager:invitePlayer", resourceRoot, row.player)
            end
        end
        return
    end

    if key == "backspace" then
        cancelEvent()
        triggerServerEvent("jobmanager:leaveJob", resourceRoot)
        return
    end

    local actions = lobbyActions()
    if key == "arrow_u" then
        selected = math.max(1, selected - 1); click("select")
    elseif key == "arrow_d" then
        selected = math.min(#actions, selected + 1); click("select")
    elseif key == "enter" then
        click("click")
        local action = actions[selected]
        if action == "Start Game" then
            triggerServerEvent("jobmanager:startJob", resourceRoot)
        elseif action == "Invite Player" then
            triggerServerEvent("jobmanager:requestInvitablePlayers", resourceRoot)
        end
    end
end)

--------------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------------

local function drawColHeader(x, y, w, text, right)
    dxDrawRectangle(x, y, w, HEAD_H, C.colHead)
    dxDrawText(text, x + S(12), y, x + w - S(12), y + HEAD_H, tocolor(255, 255, 255), S(1.05), FONT.head, "left", "center")
    if right and right ~= "" then
        dxDrawText(right, x + S(12), y, x + w - S(12), y + HEAD_H, tocolor(255, 255, 255), S(1.0), FONT.row, "right", "center")
    end
end

-- rows: { {label=, value=, badge=, bg=, crewTag=, crewColor=} }. `bg` overrides
-- the resting-state (not selected) background, e.g. the light-blue "Start Game"
-- row. `crewTag`/`crewColor` (when the tag is a non-empty string) draw a crew
-- tag box right after the label.
local function drawRows(x, y, w, rowH, rows, sel, active)
    for i, r in ipairs(rows) do
        local ry = y + (i - 1) * rowH
        local isSel = active and i == sel
        dxDrawRectangle(x, ry, w, rowH, isSel and C.rowSel or (r.bg or C.row))
        dxDrawRectangle(x, ry + rowH - 1, w, 1, C.rowSep)
        local labelFont = isSel and FONT.rowB or FONT.row
        dxDrawText(r.label, x + S(12), ry, x + w - S(12), ry + rowH,
            isSel and C.rowSelT or (r.dim and C.txtDim or C.txt), S(1.05),
            labelFont, "left", "center")
        if r.crewTag and r.crewTag ~= "" then
            local lw = dxGetTextWidth(r.label, S(1.05), labelFont)
            uicore:drawCrewTagBox(x + S(12) + lw + S(6), ry + rowH / 2, S(1.05),
                r.crewTag, r.crewColor, 255, "left", "center")
        end
        if r.badge then
            local bw = dxGetTextWidth(r.badge, S(0.8), FONT.rowB) + S(14)
            dxDrawRectangle(x + w - S(12) - bw, ry + rowH / 2 - S(9), bw, S(18), C.accent)
            dxDrawText(r.badge, x + w - S(12) - bw, ry + rowH / 2 - S(9), x + w - S(12), ry + rowH / 2 + S(9),
                tocolor(255, 255, 255), S(0.8), FONT.rowB, "center", "center")
        elseif r.value then
            dxDrawText(r.value, x + S(12), ry, x + w - S(12), ry + rowH,
                isSel and C.rowSelT or C.txtDim, S(1.0), FONT.row, "right", "center")
        end
    end
end

addEventHandler("onClientRender", root, function()
    if countdownText and getTickCount() < countdownUntil then
        dxDrawText(countdownText, 0, screenH * 0.32, screenW, screenH * 0.32 + S(140),
            tocolor(255, 255, 255, 235), S(6), "pricedown", "center", "center")
    end

    if nearbyJob and not panel and not getElementData(localPlayer, "paused") then
        dxDrawText("Press BACKSPACE to open the pause menu and join " .. nearbyJob,
            0, screenH - S(70), screenW, screenH - S(40), tocolor(255, 255, 255), S(1.1), FONT.rowB, "center", "center")
    end

    if panel ~= "lobby" or not lobby then return end

    dxDrawRectangle(0, 0, screenW, screenH, C.wash)

    local fw, fh = screenW * MENU_FRACTION, screenH * MENU_FRACTION
    local fx, fy = math.floor((screenW - fw) / 2), math.floor((screenH - fh) / 2)
    local rowH = S(26)

    -- title / briefing band
    local bandH = S(60)
    dxDrawRectangle(fx, fy, fw, bandH, C.band)
    dxDrawText(string.upper(lobby.name or "JOB"), fx + S(16), fy + S(6), fx + fw - S(16), fy + S(28),
        tocolor(255, 255, 255), S(1.15), FONT.title, "left", "top")
    dxDrawText(lobby.description or "Waiting for the host to start the job.",
        fx + S(16), fy + S(28), fx + fw - S(16), fy + bandH - S(4),
        C.txtDim, S(0.95), FONT.row, "left", "top", false, true)

    -- three columns
    local gap = S(6)
    local colW = math.floor((fw - gap * 2) / 3)
    local colY = fy + bandH + S(6)
    local colH = fy + fh - colY - INFO_H - S(4)
    local c1 = fx
    local c2 = fx + colW + gap
    local c3 = fx + (colW + gap) * 2

    -- column 1: lobby actions
    drawColHeader(c1, colY, colW, "LOBBY")
    local actions = lobbyActions()
    if selected > #actions then selected = #actions end
    local actionRows = {}
    for i, a in ipairs(actions) do
        actionRows[i] = { label = a, bg = (a == "Start Game") and C.startBg or nil }
    end
    drawRows(c1, colY + HEAD_H, colW, rowH, actionRows, selected, true)

    -- column 2: players
    drawColHeader(c2, colY, colW, "PLAYERS", #lobby.players .. " of " .. lobby.min .. "-" .. lobby.max)
    local playerRows = {}
    for i, p in ipairs(lobby.players) do
        playerRows[i] = { label = p.name, badge = p.host and "HOST" or nil, crewTag = p.crewTag, crewColor = p.crewColor }
    end
    drawRows(c2, colY + HEAD_H, colW, rowH, playerRows, 0, false)

    -- column 3: details
    drawColHeader(c3, colY, colW, "DETAILS")
    local dY = colY + HEAD_H
    dxDrawRectangle(c3, dY, colW, colH, C.row)
    local imgH = math.min(colW * 9 / 16, colH * 0.55)
    local imgPath = lobby.image or "assets/jobs/default.jpg"
    if not fileExists(imgPath) then imgPath = "assets/jobs/default.jpg" end
    dxDrawRectangle(c3, dY, colW, imgH, tocolor(0, 0, 0, 220))
    dxDrawImage(c3, dY, colW, imgH, imgPath)
    dxDrawText(lobby.name or "", c3 + S(10), dY + imgH - S(28), c3 + colW - S(10), dY + imgH - S(6),
        tocolor(255, 255, 255), S(1.1), FONT.title, "right", "bottom")

    local details = {
        { "Type", (lobby.type == "race" and "Race") or (lobby.type == "deathmatch" and "Deathmatch") or "Job" },
        { "Players", tostring(lobby.min) .. "-" .. tostring(lobby.max) },
        { "In lobby", tostring(#lobby.players) },
    }
    for i, d in ipairs(details) do
        local ry = dY + imgH + (i - 1) * rowH
        dxDrawRectangle(c3, ry, colW, rowH, i % 2 == 0 and tocolor(255, 255, 255, 10) or tocolor(0, 0, 0, 0))
        dxDrawText(d[1], c3 + S(12), ry, c3 + colW - S(12), ry + rowH, C.txtDim, S(1.0), FONT.row, "left", "center")
        dxDrawText(d[2], c3 + S(12), ry, c3 + colW - S(12), ry + rowH, C.txt, S(1.0), FONT.rowB, "right", "center")
    end

    -- info bar
    local infoY = fy + fh - INFO_H
    dxDrawRectangle(fx, infoY, fw, INFO_H, C.infobar)
    local help = (actions[selected] == "Start Game")
        and "Start the job for everyone in the lobby."
        or "Invite another player to this lobby through their phone."
    dxDrawText(help, fx + S(14), infoY, fx + fw * 0.55, infoY + INFO_H, C.txtDim, S(0.92), FONT.row, "left", "center", true)
    dxDrawText("ARROWS  Navigate      ENTER  Select      BACKSPACE  Leave",
        fx + fw * 0.55, infoY, fx + fw - S(14), infoY + INFO_H, C.txt, S(0.92), FONT.rowB, "right", "center")

    -- "Invite Player" sub-panel
    if inviteMenu then
        local rows = inviteMenu.rows
        if inviteMenu.sel > math.max(#rows, 1) then inviteMenu.sel = math.max(#rows, 1) end

        local mw, mh = math.floor(fw * 0.42), math.floor(fh * 0.72)
        local mx, my = math.floor(fx + (fw - mw) / 2), math.floor(fy + (fh - mh) / 2)
        dxDrawRectangle(0, 0, screenW, screenH, C.wash)
        dxDrawRectangle(mx, my, mw, mh, C.band)
        dxDrawText("INVITE PLAYER", mx + S(14), my + S(8), mx + mw - S(14), my + S(30),
            tocolor(255, 255, 255), S(1.15), FONT.title, "left", "top")

        local listY = my + S(38)
        local listBottom = my + mh - INFO_H - S(6)
        local maxRows = math.max(1, math.floor((listBottom - listY) / rowH))

        if #rows == 0 then
            dxDrawText("No players available to invite.", mx + S(14), listY, mx + mw - S(14), listY + rowH,
                C.txtDim, S(1.0), FONT.row, "left", "center")
        else
            local first = math.max(1, math.min(inviteMenu.sel - math.floor(maxRows / 2), #rows - maxRows + 1))
            for i = first, math.min(#rows, first + maxRows - 1) do
                local r = rows[i]
                local ry = listY + (i - first) * rowH
                local isSel = i == inviteMenu.sel
                dxDrawRectangle(mx, ry, mw, rowH, isSel and C.rowSel or C.row)
                dxDrawRectangle(mx, ry + rowH - 1, mw, 1, C.rowSep)
                dxDrawText(r.name, mx + S(12), ry, mx + mw - S(12), ry + rowH,
                    isSel and C.rowSelT or C.txt, S(1.05), isSel and FONT.rowB or FONT.row, "left", "center")
                if r.sent then
                    dxDrawText("INVITED", mx + S(12), ry, mx + mw - S(12), ry + rowH,
                        isSel and C.rowSelT or C.txtDim, S(0.85), FONT.rowB, "right", "center")
                end
            end
        end

        local mInfoY = my + mh - INFO_H
        dxDrawRectangle(mx, mInfoY, mw, INFO_H, C.infobar)
        dxDrawText("ARROWS  Navigate      ENTER  Invite      BACKSPACE  Back",
            mx + S(12), mInfoY, mx + mw - S(12), mInfoY + INFO_H, C.txt, S(0.9), FONT.rowB, "center", "center")
    end
end)
