-- End-of-match results screen, shown between the match end and the scoreboard
-- (core/client/scoreboard.lua owns the view state, camera and input routing).
-- Big headlines revealed step by step, bottom to top:
--   1. placement  2. payout (right)  3. XP (left)  4. level bar
-- The shown elements form one block that always sits at the vertical centre of
-- the screen: a new step lands on top of the block, coming down from above,
-- and pushes the earlier ones down so the block stays centred.
-- Steps advance on their own every STEP_MS; ENTER jumps to the next one.
-- Data is payload.reward from core/rewards.lua.

local screenW, screenH = guiGetScreenSize()
local uicore = exports.ui_core
local SCALE = (uicore:ui(1000) or 1000) / 1000
local FIT = 1            -- extra shrink when the full block would not fit the screen
local function P(v) return v * SCALE * FIT end

local C = {
    wash   = { 0, 0, 0, 160 },
    shadow = { 0, 0, 0, 180 },
    barBg  = { 0, 0, 0, 160 },
    txt    = { 240, 240, 240, 255 },
    cap    = { 176, 180, 185, 255 },
    small  = { 207, 207, 207, 255 },
    next   = { 138, 142, 147, 255 },
    gold   = { 242, 201, 76, 255 },
    dnf    = { 220, 90, 90, 255 },
    money  = { 114, 200, 107, 255 },
    xp     = { 127, 208, 255, 255 },
    barOld = { 0, 113, 184, 255 },
}

-- font sizes (pt, scaled by ui_core and FIT)
local F = { place = 120, suffix = 48, name = 33, big = 90, level = 72, levelUp = 36, cap = 18, small = 17 }
local BAR_H = 30
local GAP = 36           -- between elements in the block
local MAX_BLOCK = 0.9    -- of screen height

local STEP_MS = 1700     -- auto advance between steps
local FADE = 450         -- fade in
local MOVE = 550         -- slide to the new place
local DROP = 90          -- a new element starts this far above its place
local COUNT = 900        -- number count-up
local BAR_DELAY = 600    -- level step: wait before the bar starts filling
local BAR_STEP = 1200    -- bar fill per level crossed
local HOLD = 5000        -- after the last step, then on to the scoreboard
local SKIPPED = -100000  -- a step start this far back counts as fully played

local fonts = {}
local reward, info
local steps = {}         -- ordered step ids, bottom to top
local cur, stepStart = 0, {}
local pos = {}           -- step index -> { from, to, tick } (y of the element top)
local flashTick, lastLevelStep = 0, 1

local function font(name, size)
    local px = math.max(6, math.floor(P(size)))
    local key = name .. px
    if fonts[key] == nil then
        fonts[key] = dxCreateFont("assets/fonts/" .. name .. ".ttf", px) or false
    end
    return fonts[key] or "default-bold"
end

local function fh(name, size) return dxGetFontHeight(1, font(name, size)) end
local function fw(text, name, size) return dxGetTextWidth(text, 1, font(name, size)) end

local function easeOut(k) return 1 - (1 - k) * (1 - k) end
local function easeOutCubic(k) return 1 - (1 - k) ^ 3 end
local function clamp01(v) return math.max(0, math.min(1, v)) end

local function col(c, a) return tocolor(c[1], c[2], c[3], c[4] * clamp01(a)) end

-- text with a drop shadow; y is the top of the line
local function text(str, x, y, w, color, a, name, size, align)
    local h = fh(name, size)
    local f = font(name, size)
    local d = math.max(1, math.floor(P(3)))
    dxDrawText(str, x + d, y + d, x + w + d, y + h + d, col(C.shadow, a), 1, f, align or "left", "top", false, false, false, false, true)
    dxDrawText(str, x, y, x + w, y + h, col(color, a), 1, f, align or "left", "top", false, false, false, false, true)
    return h
end

local function group(v)
    return (tostring(math.floor(v + 0.5)):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

local function ordinal(n)
    if n % 100 < 11 or n % 100 > 13 then
        local s = ({ "ST", "ND", "RD" })[n % 10]
        if s then return tostring(n), s end
    end
    return tostring(n), "TH"
end

local function fmtTime(ms)
    if not ms then return "-" end
    local m = math.floor(ms / 60000)
    return string.format("%d:%05.2f", m, ms / 1000 - m * 60)
end

local function joinLines(lines)
    local parts = {}
    for _, l in ipairs(lines) do table.insert(parts, l[1] .. " " .. l[2]) end
    return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- element heights (fixed per step, used for the centred layout)
--------------------------------------------------------------------------------

local function heightOf(id)
    if id == "place" then return fh("RobotoB", F.place) end
    if id == "money" or id == "xp" then
        return fh("RobotoB", F.cap) + fh("RobotoB", F.big) + P(6) + fh("Roboto", F.small)
    end
    return fh("RobotoB", F.cap) * 2 + fh("RobotoB", F.level) + P(10) + P(BAR_H) + P(6)
end

-- Shrinks everything when the full block (all steps) is taller than MAX_BLOCK.
local function fitBlock()
    FIT = 1
    local total = 0
    for i, id in ipairs(steps) do total = total + heightOf(id) + (i > 1 and P(GAP) or 0) end
    local limit = screenH * MAX_BLOCK
    if total > limit then FIT = limit / total end
end

--------------------------------------------------------------------------------
-- steps + layout
--------------------------------------------------------------------------------

local function currentY(i)
    local p = pos[i]
    if not p then return 0 end
    local k = easeOutCubic(clamp01((getTickCount() - p.tick) / MOVE))
    return p.from + (p.to - p.from) * k
end

-- Recentres the shown block; element i is the newest (starts DROP above its place).
local function relayout(newest)
    local total = 0
    for i = 1, cur do total = total + heightOf(steps[i]) + (i > 1 and P(GAP) or 0) end
    local bottom = (screenH + total) / 2
    local now = getTickCount()
    for i = 1, cur do
        local top = bottom - heightOf(steps[i])
        local from = (i == newest) and (top - P(DROP)) or currentY(i)
        pos[i] = { from = from, to = top, tick = now }
        bottom = top - P(GAP)
    end
end

local function startStep(i)
    cur = i
    stepStart[i] = getTickCount()
    relayout(i)
end

local function since(id)
    for i, s in ipairs(steps) do
        if s == id then return i <= cur and (getTickCount() - stepStart[i]) or false, i end
    end
    return false
end

local function stepDuration(id)
    if id == "level" and reward.level then return BAR_DELAY + BAR_STEP * #reward.level.steps end
    if id == "money" or id == "xp" then return COUNT + FADE end
    return MOVE
end

-- ENTER: lets the shown steps (and their slides) jump to their end state
local function finishShown()
    for i = 1, cur do
        stepStart[i] = math.min(stepStart[i], getTickCount() + SKIPPED)
        if pos[i] then pos[i].tick = getTickCount() + SKIPPED end
    end
end

--------------------------------------------------------------------------------
-- API used by scoreboard.lua
--------------------------------------------------------------------------------

Results = {}

function Results.start(data)
    reward, info = data.reward, data
    steps = { "place", "money", "xp" }
    if reward.level then table.insert(steps, "level") end
    cur, stepStart, pos, flashTick, lastLevelStep = 0, {}, {}, 0, 1
    fitBlock()
    startStep(1)
end

-- ENTER: next step / finish the last one. false = nothing left, go on.
function Results.advance()
    if not reward then return false end
    local last = #steps
    if cur < last then
        finishShown()
        startStep(cur + 1)
        return true
    end
    if getTickCount() - stepStart[last] < stepDuration(steps[last]) then
        finishShown()
        return true
    end
    return false
end

-- true once every step played and was held long enough
function Results.isOver()
    if not reward or cur < #steps then return false end
    return getTickCount() - stepStart[cur] >= stepDuration(steps[cur]) + HOLD
end

function Results.stop()
    reward, info = nil, nil
end

local function autoAdvance()
    if cur < #steps and getTickCount() - stepStart[cur] >= STEP_MS then startStep(cur + 1) end
end

--------------------------------------------------------------------------------
-- drawing (y = element top, a = fade)
--------------------------------------------------------------------------------

local function drawPlace(x, y, w, a)
    local placeH = fh("RobotoB", F.place)
    local nx = x
    if reward.place then
        local num, suf = ordinal(reward.place)
        local numW = fw(num, "RobotoB", F.place)
        text(num, nx, y, numW + P(6), C.gold, a, "RobotoB", F.place)
        text(suf, nx + numW + P(4), y + placeH * 0.16, P(300), C.gold, a, "RobotoB", F.suffix)
        nx = nx + numW + fw(suf, "RobotoB", F.suffix) + P(44)
    else
        text("DNF", nx, y, P(800), C.dnf, a, "RobotoB", F.place)
        nx = nx + fw("DNF", "RobotoB", F.place) + P(44)
    end

    local sub
    if info.type == "race" then
        sub = (reward.place and ("PLACE " .. reward.place .. " OF " .. reward.players .. "  ·  " .. fmtTime(reward.timeMs)) or "NOT FINISHED") .. "  ·  RACE"
    else
        sub = "PLACE " .. reward.place .. " OF " .. reward.players .. "  ·  " .. reward.kills .. " KILLS  ·  " .. reward.deaths .. " DEATHS  ·  DEATHMATCH"
    end
    if reward.solo then sub = sub .. "  ·  SOLO" end

    local nameH, capH = fh("RobotoB", F.name), fh("RobotoB", F.cap)
    local ny = y + placeH - nameH - capH - P(24)
    text(string.upper(info.jobName or ""), nx, ny, x + w - nx, C.txt, a, "RobotoB", F.name)
    text(sub, nx, ny + nameH + P(4), x + w - nx, C.cap, a, "RobotoB", F.cap)
    text("ENTER", x, y + placeH - capH - P(26), w, C.cap, a, "RobotoB", F.cap, "right")
end

local function drawValue(x, y, w, a, t, caption, value, color, lines, align)
    local capH, bigH = fh("RobotoB", F.cap), fh("RobotoB", F.big)
    text(caption, x, y, w, C.cap, a, "RobotoB", F.cap, align)
    text(value(easeOut(clamp01(t / COUNT))), x, y + capH, w, color, a, "RobotoB", F.big, align)
    text(joinLines(lines), x, y + capH + bigH + P(6), w, C.small, a * clamp01((t - COUNT) / FADE), "Roboto", F.small, align)
end

local function drawLevel(x, y, w, a, t)
    local lv = reward.level
    local capH, numH, barH = fh("RobotoB", F.cap), fh("RobotoB", F.level), P(BAR_H)

    local k = easeOut(clamp01((t - BAR_DELAY) / (BAR_STEP * #lv.steps)))
    local xpNow = lv.xpFrom + (lv.xpTo - lv.xpFrom) * k
    local si = #lv.steps
    for i, st in ipairs(lv.steps) do
        if xpNow < st.max then si = i break end
    end
    if si ~= lastLevelStep then
        lastLevelStep, flashTick = si, getTickCount()
        playSound("assets/sounds/select.wav")
    end
    local st = lv.steps[si]

    text("LEVEL", x, y, w, C.cap, a, "RobotoB", F.cap)
    text("NEXT", x, y, w, C.cap, a, "RobotoB", F.cap, "right")
    text(tostring(st.level), x, y + capH, w, C.txt, a, "RobotoB", F.level)
    text(tostring(st.level + 1), x, y + capH, w, C.next, a, "RobotoB", F.level, "right")
    if si > 1 then
        local upH = fh("RobotoB", F.levelUp)
        text("LEVEL UP", x, y + capH + numH - upH, w, C.gold, a, "RobotoB", F.levelUp, "center")
    end

    local by = y + capH + numH + P(10)
    local span = math.max(1, st.max - st.min)
    local oldEnd = si == 1 and lv.xpFrom or st.min
    local oldW = w * clamp01((oldEnd - st.min) / span)
    local nowW = w * clamp01((xpNow - st.min) / span)
    dxDrawRectangle(x, by, w, barH, col(C.barBg, a))
    dxDrawRectangle(x, by, oldW, barH, col(C.barOld, a))
    if nowW > oldW then dxDrawRectangle(x + oldW, by, nowW - oldW, barH, col(C.xp, a)) end
    local flash = 1 - clamp01((getTickCount() - flashTick) / 900)
    if si > 1 and flash > 0 then dxDrawRectangle(x, by, w, barH, tocolor(255, 255, 255, 200 * flash)) end
    text(group(xpNow) .. " / " .. group(st.max) .. " XP", x, by + barH + P(6), w, C.cap, a, "RobotoB", F.cap, "right")
end

function Results.draw()
    if not reward then return end
    autoAdvance()
    dxDrawRectangle(0, 0, screenW, screenH, col(C.wash, 1))

    local cw = math.min(screenW * 0.86, P(1700))
    local cx = math.floor((screenW - cw) / 2)
    local half = cw * 0.6

    for i = 1, cur do
        local id = steps[i]
        local t = since(id)
        local a = easeOut(clamp01(t / FADE))
        local y = currentY(i)
        if id == "place" then
            drawPlace(cx, y, cw, a)
        elseif id == "money" then
            drawValue(cx + cw - half, y, half, a, t, "PAYOUT",
                function(k) return "+€" .. group(reward.money.total * k) end, C.money, reward.money.lines, "right")
        elseif id == "xp" then
            drawValue(cx, y, half, a, t, "EXPERIENCE",
                function(k) return "+" .. group(reward.xp.total * k) .. " XP" end, C.xp, reward.xp.lines, "left")
        elseif id == "level" then
            drawLevel(cx, y, cw, a, t)
        end
    end
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, f in pairs(fonts) do if isElement(f) then destroyElement(f) end end
end)
