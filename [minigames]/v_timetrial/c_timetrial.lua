uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local trial = Timetrials[ACTIVE_TIMETRIAL]
local timeLeft = 0
local active = false
local timer

-- admin test mode (/tttest): private trial + markers, no reward
local test -- { trial, start, finish }

local function currentTrial()
    return test and test.trial or trial
end

local function endMarkerElement()
    if test then return isElement(test.finish) and test.finish or nil end
    local m = getElementByID("tt:end")
    return isElement(m) and m or nil
end

local objectiveId

local function clearObjective()
    if objectiveId then
        exports.v_radar:removeObjective(objectiveId)
        objectiveId = nil
    end
end

local function resetRun()
    clearObjective()
    if timer and isTimer(timer) then killTimer(timer) end
    active = false
    timeLeft = 0
    setElementData(localPlayer, "tt:active", false)
end

addEvent("tt:notice", true)
addEventHandler("tt:notice", resourceRoot, function(text)
    uicore:setBanner("TIME TRIAL TEST", text)
end)

addEvent("tt:test", true)
addEventHandler("tt:test", resourceRoot, function(index, startM, finishM)
    resetRun()
    if index and Timetrials[index] then
        test = { trial = Timetrials[index], start = startM, finish = finishM }
        if isElement(finishM) then setElementAlpha(finishM, 0) end
    else
        test = nil
    end
end)

-- the server switches the active trial (weekly schedule)
addEvent("tt:setActive", true)
addEventHandler("tt:setActive", resourceRoot, function(index)
    if not Timetrials[index] then return end
    resetRun()
    trial = Timetrials[index]
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("tt:requestActive", localPlayer)
end)

-- === 3D LABEL (same card style as the job / medical markers) ===
local sh = select(2, guiGetScreenSize())
local function sc(v) return v * sh / 1080 end

local LABEL_HEIGHT, LABEL_DISTANCE, LABEL_FULL, LABEL_MIN_SCALE = 1.8, 40, 12, 0.55
local ACCENT = { 170, 70, 255 }

local function round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 12)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 12)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 12)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 12)
end

local function drawLabel(sx, sy, k, alpha, tr, inside, isTest)
    local a = alpha / 255
    local fTitle, fSub, fHint = "default-bold", "default-bold", "default"
    local ts, ss = 1.25 * k * sh / 1080 * 1.2, 0.95 * k * sh / 1080 * 1.2

    local sub = (isTest and "TIME TRIAL  -  TEST" or "TIME TRIAL")
    local stats = tr.time .. " sec   -   " .. (isTest and "no reward" or ("EUR " .. tr.reward))
    local hint = not inside and "Step into the marker to start"
        or (isLandDriver(localPlayer) and "Press  E  to start" or "Land vehicle required")
    local pad, icon, gap = sc(10) * k, sc(34) * k, sc(10) * k
    local textW = math.max(dxGetTextWidth(tr.name, ts, fTitle), dxGetTextWidth(sub, ss, fSub),
        dxGetTextWidth(stats, ss, fSub), dxGetTextWidth(hint, ss, fHint))
    local w = pad + icon + gap + textW + pad * 1.4
    local headH, hintH = sc(66) * k, sc(22) * k
    local h = headH + hintH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, sc(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - sc(3) * k, w, sc(3) * k, sc(1.5) * k, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 235 * a))

    local ix, iy = x + pad, y + (headH - icon) / 2 + sc(2) * k
    round(ix, iy, icon, icon, sc(5) * k, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 240 * a))
    dxDrawText("TT", ix, iy, ix + icon, iy + icon, tocolor(255, 255, 255, 255 * a), ss * 1.2, fTitle, "center", "center")

    local tx = ix + icon + gap
    dxDrawText(sub, tx, y + sc(6) * k, tx + textW, y + headH * 0.3, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 255 * a), ss, fSub, "left", "center")
    dxDrawText(tr.name, tx, y + headH * 0.28, tx + textW, y + headH * 0.62, tocolor(255, 255, 255, 255 * a), ts, fTitle, "left", "center")
    dxDrawText(stats, tx, y + headH * 0.6, tx + textW, y + headH, tocolor(200, 205, 212, 230 * a), ss, fSub, "left", "center")

    dxDrawText(hint, x + pad, y + headH, x + w - pad, y + h,
        inside and tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 255 * a) or tocolor(200, 205, 212, 220 * a),
        ss, inside and fSub or fHint, "left", "center")

    dxDrawRectangle(sx - sc(1) * k, y + h, sc(2) * k, sc(10) * k, tocolor(14, 17, 21, 220 * a))
end

local function labelAt(tr, isTest)
    if active then return end
    local p = tr.start
    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(px, py, pz, p.x, p.y, p.z)
    if dist > LABEL_DISTANCE then return end
    local sx, sy = getScreenFromWorldPosition(p.x, p.y, p.z + LABEL_HEIGHT, 0.1)
    if not sx then return end
    local k = 1
    if dist > LABEL_FULL then
        k = 1 - (dist - LABEL_FULL) / (LABEL_DISTANCE - LABEL_FULL) * (1 - LABEL_MIN_SCALE)
    end
    local alpha = dist > LABEL_DISTANCE * 0.8 and 255 * (LABEL_DISTANCE - dist) / (LABEL_DISTANCE * 0.2) or 255
    drawLabel(sx, sy, k, alpha, tr, getElementData(localPlayer, "tt:canStart") == true, isTest)
end

addEventHandler("onClientRender", root, function()
    if isPlayerMapVisible() or getElementData(localPlayer, "paused") then return end
    if test then
        labelAt(test.trial, true)
    else
        labelAt(trial, false)
    end
    if active then
        uicore:drawTimer(timeLeft)
    end
end)

-- === INDÍTÁS ===
bindKey("e", "down", function()
    if not getElementData(localPlayer, "tt:canStart") then return end
    if active then return end
    if not isLandDriver(localPlayer) then return end

    active = true
    local tr = currentTrial()
    timeLeft = tr.time

    local endM = endMarkerElement()
    if endM then setElementAlpha(endM, 160) end
    clearObjective()
    objectiveId = exports.v_radar:addObjective(tr.finish.x, tr.finish.y, tr.finish.z, tr.name) or nil
    setElementData(localPlayer, "tt:active", true)
    uicore:setBanner("TIME TRIAL STARTED", "Good luck!")

    timer = setTimer(function()
        timeLeft = timeLeft - 1
        if timeLeft <= 0 then
            triggerEvent("tt:finish", localPlayer, false)
        end
    end, 1000, tr.time)
end)

-- === BEFEJEZÉS ===
addEvent("tt:finish", true)
addEventHandler("tt:finish", root, function(success)
    if timer and isTimer(timer) then killTimer(timer) end

    active = false
    clearObjective()
    local endM = endMarkerElement()
    if endM then setElementAlpha(endM, 0) end
    setElementData(localPlayer, "tt:active", false)

    if success then
        uicore:setBanner("TIME TRIAL COMPLETED", test and "Test run - no reward" or ("Reward: €" .. trial.reward))
    else
        uicore:setBanner("TIME TRIAL FAILED", "Out of time")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, clearObjective)
