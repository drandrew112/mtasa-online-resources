-- End-of-match scoreboard: cinematic camera + stats, then a "pick next game"
-- tile grid (6 wide x 2 tall) plus a shorter Replay / Free Mode row below it.
-- Opens on jobmanager:matchEnded, entirely separate from the pause menu.

local screenW, screenH = guiGetScreenSize()
local uicore = exports.ui_core
local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v) return v * SCALE end

local FONT = { row = "default", rowB = "default-bold", head = "default-bold", title = "default-bold" }

local C = {
    wash     = tocolor(0, 0, 0, 150),
    band     = tocolor(0, 0, 0, 210),
    colHead  = tocolor(0, 113, 184, 255),
    row      = tocolor(0, 0, 0, 140),
    rowAlt   = tocolor(255, 255, 255, 12),
    txt      = tocolor(235, 235, 235, 255),
    txtDim   = tocolor(152, 156, 161, 255),
    accent   = tocolor(0, 130, 205, 255),
    infobar  = tocolor(0, 0, 0, 200),
    tile     = tocolor(0, 0, 0, 170),
    tileSel  = tocolor(243, 243, 243, 245),
    tileSelT = tocolor(12, 12, 12, 255),
    replay   = tocolor(70, 150, 220, 170),
    free     = tocolor(120, 120, 120, 170),
}

local COLS, MAIN_ROWS = 6, 2

local view = nil       -- nil | "stats" | "picker"
local payload = nil     -- last jobmanager:matchEnded payload
local mainIndex, bottomIndex, activeRow = 1, 1, 1

local function fmtTime(ms)
    if not ms then return "-" end
    local totalSeconds = ms / 1000
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds - minutes * 60
    return string.format("%d:%05.2f", minutes, seconds)
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function openScoreboard(data)
    payload = data
    view = "stats"
    mainIndex, bottomIndex, activeRow = 1, 1, 1

    showCursor(false)
    uicore:toggleMoveControls(false)
    setElementFrozen(localPlayer, true)
    setElementData(localPlayer, "hideHUD", true)
    setElementData(localPlayer, "scoreboardOpen", true)

    local cam = data.camera
    if cam and cam.pos and cam.lookAt then
        setCameraMatrix(cam.pos[1], cam.pos[2], cam.pos[3],
            cam.lookAt[1], cam.lookAt[2], cam.lookAt[3], cam.roll or 0, cam.fov or 90)
    end
end

local function closeScoreboard()
    view, payload = nil, nil
    setCameraTarget(localPlayer)
    if isElement(localPlayer) then setElementFrozen(localPlayer, false) end
    setElementData(localPlayer, "hideHUD", false)
    setElementData(localPlayer, "scoreboardOpen", false)
    uicore:toggleMoveControls(true)
end

addEvent("jobmanager:matchEnded", true)
addEventHandler("jobmanager:matchEnded", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    openScoreboard(data)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if view then closeScoreboard() end
end)

--------------------------------------------------------------------------------
-- input (arrows / enter / backspace only)
--------------------------------------------------------------------------------

addEventHandler("onClientKey", root, function(key, down)
    if not down or not view then return end

    if view == "stats" then
        if key == "backspace" then
            cancelEvent()
            closeScoreboard()
        elseif key == "enter" then
            cancelEvent()
            view = "picker"
        end
        return
    end

    -- picker view
    local jobsList = jobmanagerGetJobs()
    local mainCount = math.min(#jobsList, COLS * MAIN_ROWS)

    if key == "backspace" then
        cancelEvent()
        view = "stats"
    elseif key == "arrow_u" then
        cancelEvent()
        if activeRow == 2 then activeRow = 1 end
    elseif key == "arrow_d" then
        cancelEvent()
        if activeRow == 1 and mainCount > 0 then activeRow = 2 end
    elseif key == "arrow_l" then
        cancelEvent()
        if activeRow == 1 then
            mainIndex = math.max(1, mainIndex - 1)
        else
            bottomIndex = math.max(1, bottomIndex - 1)
        end
    elseif key == "arrow_r" then
        cancelEvent()
        if activeRow == 1 then
            mainIndex = math.min(math.max(mainCount, 1), mainIndex + 1)
        else
            bottomIndex = math.min(2, bottomIndex + 1)
        end
    elseif key == "enter" then
        cancelEvent()
        if activeRow == 1 then
            local job = jobsList[mainIndex]
            if job then
                jobmanagerJoinJob(job.id)
                closeScoreboard()
            end
        else
            if bottomIndex == 1 and payload and payload.jobId then
                jobmanagerJoinJob(payload.jobId)
            end
            closeScoreboard()
        end
    end
end)

--------------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------------

local function drawStats()
    dxDrawRectangle(0, 0, screenW, screenH, C.wash)

    local fw, fh = screenW * 0.55, screenH * 0.6
    local fx, fy = math.floor((screenW - fw) / 2), math.floor(screenH * 0.14)
    local headerH, colHeadH, rowH, footerH = S(50), S(22), S(26), S(26)

    dxDrawRectangle(fx, fy, fw, headerH, C.band)
    dxDrawText(string.upper(payload.jobName or "MATCH"), fx + S(16), fy + S(4), fx + fw - S(16), fy + S(30),
        tocolor(255, 255, 255), S(1.3), FONT.title, "left", "top")
    dxDrawText(payload.reason or "", fx + S(16), fy + S(28), fx + fw - S(16), fy + headerH - S(4),
        C.txtDim, S(0.95), FONT.row, "left", "top")

    local isRace = payload.type == "race"
    local stats = payload.stats or {}

    local y = fy + headerH + S(6)
    dxDrawRectangle(fx, y, fw, colHeadH, C.colHead)
    if isRace then
        dxDrawText("PLACE", fx + S(12), y, fx + fw * 0.2, y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "left", "center")
        dxDrawText("NAME", fx + fw * 0.2, y, fx + fw * 0.7, y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "left", "center")
        dxDrawText("TIME", fx + fw * 0.7, y, fx + fw - S(12), y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "right", "center")
    else
        dxDrawText("NAME", fx + S(12), y, fx + fw * 0.6, y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "left", "center")
        dxDrawText("KILLS", fx + fw * 0.6, y, fx + fw * 0.8, y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "right", "center")
        dxDrawText("DEATHS", fx + fw * 0.8, y, fx + fw - S(12), y + colHeadH, tocolor(255, 255, 255), S(1.0), FONT.head, "right", "center")
    end
    y = y + colHeadH

    for i, row in ipairs(stats) do
        local ry = y + (i - 1) * rowH
        dxDrawRectangle(fx, ry, fw, rowH, i % 2 == 0 and C.rowAlt or C.row)
        local nameX = isRace and (fx + fw * 0.2) or (fx + S(12))
        if isRace then
            local placeText = row.place and ("#" .. row.place) or "DNF"
            dxDrawText(placeText, fx + S(12), ry, fx + fw * 0.2, ry + rowH, C.accent, S(1.0), FONT.rowB, "left", "center")
            dxDrawText(row.name, nameX, ry, fx + fw * 0.7, ry + rowH, C.txt, S(1.0), FONT.row, "left", "center")
            dxDrawText(fmtTime(row.timeMs), fx + fw * 0.7, ry, fx + fw - S(12), ry + rowH, C.txt, S(1.0), FONT.rowB, "right", "center")
        else
            dxDrawText(row.name, nameX, ry, fx + fw * 0.6, ry + rowH, C.txt, S(1.0), FONT.row, "left", "center")
            dxDrawText(tostring(row.kills), fx + fw * 0.6, ry, fx + fw * 0.8, ry + rowH, C.txt, S(1.0), FONT.rowB, "right", "center")
            dxDrawText(tostring(row.deaths), fx + fw * 0.8, ry, fx + fw - S(12), ry + rowH, C.txt, S(1.0), FONT.rowB, "right", "center")
        end
        if row.crewTag and row.crewTag ~= "" then
            local nw = dxGetTextWidth(row.name, S(1.0), FONT.row)
            uicore:drawCrewTagBox(nameX + nw + S(6), ry + rowH / 2, S(1.0),
                row.crewTag, row.crewColor, 255, "left", "center")
        end
    end

    local infoY = y + #stats * rowH + S(10)
    dxDrawRectangle(fx, infoY, fw, footerH, C.infobar)
    dxDrawText("Match results", fx + S(14), infoY, fx + fw * 0.4, infoY + footerH, C.txtDim, S(0.92), FONT.row, "left", "center")
    dxDrawText("ENTER  Continue      BACKSPACE  Free Mode", fx + fw * 0.35, infoY, fx + fw - S(14), infoY + footerH,
        C.txt, S(0.92), FONT.rowB, "right", "center")
end

local function drawPicker()
    dxDrawRectangle(0, 0, screenW, screenH, C.wash)

    local jobsList = jobmanagerGetJobs()

    local gw = screenW * 0.7
    local gx = math.floor((screenW - gw) / 2)
    local gap = S(8)
    local tileW = (gw - gap * (COLS - 1)) / COLS
    local tileH = tileW * 0.65
    local gy = math.floor(screenH * 0.5 - (tileH * MAIN_ROWS + gap) / 2)

    dxDrawText("PICK THE NEXT GAME", gx, gy - S(34), gx + gw, gy - S(6),
        tocolor(255, 255, 255), S(1.3), FONT.title, "left", "bottom")

    for i = 1, COLS * MAIN_ROWS do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local tx = gx + col * (tileW + gap)
        local ty = gy + row * (tileH + gap)
        local job = jobsList[i]
        local isSel = activeRow == 1 and mainIndex == i

        dxDrawRectangle(tx, ty, tileW, tileH, isSel and C.tileSel or C.tile)
        if job then
            local imgPath = job.image or "assets/jobs/default.jpg"
            if not fileExists(imgPath) then imgPath = "assets/jobs/default.jpg" end
            dxDrawImage(tx, ty, tileW, tileH, imgPath)
            dxDrawRectangle(tx, ty + tileH - S(20), tileW, S(20), tocolor(0, 0, 0, 190))
            dxDrawText(job.name or "", tx + S(4), ty + tileH - S(20), tx + tileW - S(4), ty + tileH,
                tocolor(255, 255, 255), S(0.8), FONT.rowB, "left", "center", true)
        end
        if isSel then
            dxDrawRectangle(tx, ty, tileW, S(3), C.accent)
        end
    end

    -- Replay / Free Mode row: shorter tiles, same total width as the grid above.
    local by = gy + MAIN_ROWS * (tileH + gap)
    local bh = tileH * 0.5
    local bw = (gw - gap) / 2
    local replaySel = activeRow == 2 and bottomIndex == 1
    local freeSel = activeRow == 2 and bottomIndex == 2

    dxDrawRectangle(gx, by, bw, bh, replaySel and C.tileSel or C.replay)
    dxDrawText("REPLAY", gx, by, gx + bw, by + bh,
        replaySel and C.tileSelT or tocolor(255, 255, 255), S(1.0), FONT.head, "center", "center")

    dxDrawRectangle(gx + bw + gap, by, bw, bh, freeSel and C.tileSel or C.free)
    dxDrawText("FREE MODE", gx + bw + gap, by, gx + bw + gap + bw, by + bh,
        freeSel and C.tileSelT or tocolor(255, 255, 255), S(1.0), FONT.head, "center", "center")

    local infoY = by + bh + S(10)
    dxDrawRectangle(gx, infoY, gw, S(26), C.infobar)
    dxDrawText("ARROWS  Navigate", gx + S(14), infoY, gx + gw * 0.6, infoY + S(26), C.txtDim, S(0.92), FONT.row, "left", "center")
    dxDrawText("ENTER  Select      BACKSPACE  Back", gx + gw * 0.4, infoY, gx + gw - S(14), infoY + S(26),
        C.txt, S(0.92), FONT.rowB, "right", "center")
end

addEventHandler("onClientRender", root, function()
    if view == "stats" then
        drawStats()
    elseif view == "picker" then
        drawPicker()
    end
end)
