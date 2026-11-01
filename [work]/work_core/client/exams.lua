if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Exam centre panel (server/exams.lua). Opened with the interact key in an exam marker.
--   select view: Exams / Minigames tabs; exam cards in two rows (competency exams, additional exams),
--                a hint to the F1 help
--   question view: one question, optional image, 4 answers. Click = select, double click = confirm,
--                or the Send button; 1-4 select, Enter sends
--   result view: percent, passed or not, back to the exams
-- Closing the panel or leaving the marker during an exam fails the attempt (the server is told).

local sw, sh = guiGetScreenSize()
local function s(v) return v * sh / 1080 end

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", s(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local textures = {}
local function texture(path)
    if not path then return nil end
    if textures[path] == nil then textures[path] = dxCreateTexture(path, "argb", true, "clamp") or false end
    return textures[path] or nil
end

local C = {
    bg = { 11, 15, 42, 240 }, card = { 21, 26, 61, 255 }, card2 = { 28, 34, 80, 255 }, line = { 44, 51, 102, 255 },
    ink = { 238, 240, 255 }, muted = { 154, 160, 200 }, gold = { 255, 210, 26 }, ok = { 53, 208, 127 },
    bad = { 255, 92, 92 }, sel = { 45, 107, 255 }, selBg = { 26, 43, 110, 255 },
}
local function rgb(c, a) return tocolor(c[1], c[2], c[3], a or c[4] or 255) end

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

local function outline(x, y, w, h, color, t)
    t = t or 2
    dxDrawRectangle(x, y, w, t, color)
    dxDrawRectangle(x, y + h - t, w, t, color)
    dxDrawRectangle(x, y, t, h, color)
    dxDrawRectangle(x + w - t, y, t, h, color)
end

local function text(str, x, y, w, h, color, size, bold, ax, ay, wrap)
    dxDrawText(str, x, y, x + w, y + h, color, 1, font(size, bold), ax or "left", ay or "top", true, wrap == true)
end

---------------------------------------------------------------- state

local panel = nil       -- { marker, view = "select" | "question" | "result", tab, overview, question, pick, result, abortArmed }
local buttons = {}      -- rebuilt every frame: { x, y, w, h, fn, dbl }
local render

local function isInside(b, cx, cy) return cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h end
local function hovered(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    cx, cy = cx * sw, cy * sh
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function button(x, y, w, h, fn, dbl) buttons[#buttons + 1] = { x = x, y = y, w = w, h = h, fn = fn, dbl = dbl } end

function isExamPanelOpen()
    return panel ~= nil
end

local onKey, onClick, onDoubleClick

local function close(silent)
    if not panel then return end
    if panel.view == "question" then triggerServerEvent("work:examAbort", resourceRoot) end
    panel = nil
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    removeEventHandler("onClientClick", root, onClick)
    removeEventHandler("onClientDoubleClick", root, onDoubleClick)
    showCursor(false)
    if not silent then playSoundFrontEnd(42) end
end

local function open(marker)
    if panel then return end
    panel = { marker = marker, view = "select", tab = "exams" }
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    addEventHandler("onClientClick", root, onClick)
    addEventHandler("onClientDoubleClick", root, onDoubleClick)
    showCursor(true)
end

-- called by menus.lua whenever the usable work marker changes
function onExamMarkerChange(marker)
    if panel and panel.marker ~= marker then close() end
end

---------------------------------------------------------------- server events

addEvent("work:examOverview", true)
addEventHandler("work:examOverview", resourceRoot, function(o)
    if type(o) ~= "table" then return end
    if not panel then
        if not CurrentMarker then return end
        open(CurrentMarker)
    end
    panel.overview = o
    o.received = getTickCount()
    if panel.view ~= "result" then panel.view = "select" end
end)

addEvent("work:examQuestion", true)
addEventHandler("work:examQuestion", resourceRoot, function(q)
    if not panel or type(q) ~= "table" then return end
    panel.view, panel.question, panel.pick, panel.abortArmed = "question", q, nil, nil
    panel.sent, panel.feedback = nil, nil
end)

-- the answer was scored: the question stays on screen for WORK.EXAM_FEEDBACK_TIME with the picked
-- answer red (wrong) or green (right) and the correct one green, then the next question / the result comes
addEvent("work:examFeedback", true)
addEventHandler("work:examFeedback", resourceRoot, function(index, pick, correct)
    if not panel or not panel.question or panel.question.index ~= index then return end
    panel.feedback = { pick = tonumber(pick), correct = tonumber(correct) }
    playSoundFrontEnd(panel.feedback.pick == panel.feedback.correct and 101 or 4)
end)

addEvent("work:examResult", true)
addEventHandler("work:examResult", resourceRoot, function(r)
    if not panel or type(r) ~= "table" then return end
    panel.view, panel.result, panel.question, panel.sent, panel.feedback = "result", r, nil, nil, nil
    playSoundFrontEnd(r.passed and 101 or 4)
end)

---------------------------------------------------------------- actions

local function send()
    local q = panel and panel.question
    if not q or not panel.pick or panel.sent then return end
    triggerServerEvent("work:examAnswer", resourceRoot, q.index, panel.pick)
    panel.sent = true      -- locked until the feedback and the next question arrive
end

local function startExam(id)
    triggerServerEvent("work:examStart", resourceRoot, panel.marker, id)
end

local function openHelp(topic)
    local res = getResourceFromName("ui_help")
    if res and getResourceState(res) == "running" then
        close(true)
        exports.ui_help:openHelp(topic)
    end
end

local function startMinigame(m)
    local res = type(m.resource) == "string" and getResourceFromName(m.resource)
    if not res or getResourceState(res) ~= "running" then
        exports.ui_core:addNotification(L("work_core.exam.title"), L("work_core.exam.minigame_unavailable"))
        return
    end
    close(true)
    local ok = pcall(function()
        local args = type(m.args) == "table" and m.args or {}
        exports[m.resource][m.fn](exports[m.resource], unpack(args, 1, m.argc or #args))
    end)
    if not ok then exports.ui_core:addNotification(L("work_core.exam.title"), L("work_core.exam.minigame_unavailable")) end
end

---------------------------------------------------------------- drawing

local PW, PH = s(1120), s(740)
local PX, PY = (sw - PW) / 2, (sh - PH) / 2
local PAD = s(26)

local function badgeOf(o, compId)
    local w = getWork(o.work)
    for _, r in ipairs(w and w.competency and w.competency.ranks or {}) do
        if r.id == compId then return r.badge, r.short end
    end
    for _, x in ipairs(w and w.competency and w.competency.certs or {}) do
        if x.id == compId then return nil, x.short end
    end
    return nil, nil
end

local function drawBadge(path, short, x, y, h, color)
    local tex = texture(path)
    if tex then
        local tw, th = dxGetMaterialSize(tex)
        local w = h * tw / th
        dxDrawImage(x, y, w, h, tex)
        return w
    end
    local w = h * 0.9
    round(x, y + (h - w) / 2, w, w, w / 2, rgb(C.card2))
    text(short or "?", x, y, w, h, rgb(C.gold), 13, true, "center", "center")
    return w
end

local function drawCard(o, card, x, y, w, h)
    local border = card.state == "done" and C.ok or (card.state == "failed" or card.state == "cooldown") and C.bad or C.line
    local alpha = card.state == "locked" and 140 or 255
    round(x, y, w, h, s(9), rgb(C.card, alpha))
    outline(x, y, w, h, rgb(border, alpha), card.state == "locked" and 1 or 2)
    local badge, short = badgeOf(o, card.comp)
    local bw = drawBadge(badge, short, x + s(12), y + s(12), s(46))
    text(card.title, x + s(20) + bw, y + s(12), w - bw - s(32), s(46), rgb(C.ink, alpha), 15, true, "left", "center", true)
    text(L("work_core.exam.card_meta", { count = card.count, pass = card.pass }), x + s(12), y + s(66), w - s(24), s(20),
        rgb(C.muted, alpha), 12)

    local by = y + h - s(46)
    if card.best then
        local bar = (w - s(24)) * math.min(100, card.best) / 100
        dxDrawRectangle(x + s(12), y + s(92), w - s(24), s(5), rgb(C.line))
        dxDrawRectangle(x + s(12), y + s(92), bar, s(5), rgb(card.state == "done" and C.ok or C.bad))
    end
    local status, scol
    if card.state == "done" then status, scol = L("work_core.exam.passed_pct", { pct = card.best or 0 }), C.ok
    elseif card.state == "held" then status, scol = L("work_core.exam.already_held"), C.ok
    elseif card.state == "failed" then status, scol = L("work_core.exam.failed_pct", { pct = card.best or 0 }), C.bad
    elseif card.state == "cooldown" then
        local left = math.max(0, math.ceil((card.wait or 0) - (getTickCount() - (o.received or 0)) / 1000))
        status, scol = L("work_core.exam.retry_wait", { time = ("%d:%02d"):format(math.floor(left / 60), left % 60) }), C.bad
        if left <= 0 then card.state = "failed" end
    elseif card.state == "locked" then status, scol = card.reason or L("work_core.exam.locked"), C.muted
    else status, scol = L("work_core.exam.not_taken"), C.muted end
    text(status, x + s(12), y + s(102), w - s(24), s(36), rgb(scol, alpha), 12, true, "left", "top", true)

    if card.state == "open" or card.state == "failed" then
        local hot = hovered(x + s(12), by, w - s(24), s(34))
        round(x + s(12), by, w - s(24), s(34), s(6), rgb(hot and { 70, 130, 255 } or C.sel))
        text(card.state == "failed" and L("work_core.exam.retry") or L("work_core.exam.start"), x + s(12), by, w - s(24), s(34),
            rgb(C.ink), 13, true, "center", "center")
        button(x + s(12), by, w - s(24), s(34), function() startExam(card.id) end)
    end
end

local function drawCards(o, list, y)
    local cols = 4
    local gap = s(14)
    local cw = (PW - 2 * PAD - gap * (cols - 1)) / cols
    local ch = s(190)
    for i, card in ipairs(list) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        drawCard(o, card, PX + PAD + col * (cw + gap), y + row * (ch + gap), cw, ch)
    end
    local rows = math.max(1, math.ceil(#list / cols))
    return y + rows * (ch + gap)
end

local function drawTabs(x, y)
    local tabs = { { "exams", L("work_core.exam.tab_exams") }, { "minigames", L("work_core.exam.tab_minigames") } }
    local tw, th = s(150), s(36)
    round(x - s(3), y - s(3), #tabs * tw + s(6), th + s(6), s(8), rgb(C.card))
    for i, t in ipairs(tabs) do
        local tx = x + (i - 1) * tw
        if panel.tab == t[1] then round(tx, y, tw, th, s(6), rgb(C.sel)) end
        text(L.upper(t[2]), tx, y, tw, th, rgb(panel.tab == t[1] and C.ink or C.muted), 14, true, "center", "center")
        button(tx, y, tw, th, function() panel.tab = t[1] end)
    end
end

local function drawHeader(o, title)
    text(title, PX + PAD, PY + PAD, PW / 2, s(34), rgb(C.ink), 24, true, "left", "center")
    -- current competency
    local rank = o and o.rank
    if o then
        local badge, short = badgeOf(o, rank)
        local x = PX + PAD
        local y = PY + PAD + s(40)
        local w = drawBadge(badge, short, x, y, s(26))
        local defs = getCompetencyDefs(o.work) or { ranks = {}, certs = {} }
        local rankName = "-"
        for _, r in ipairs(defs.ranks) do if r.id == rank then rankName = r.name end end
        local certs = {}
        for _, c in ipairs(defs.certs) do if o.certs and o.certs[c.id] then certs[#certs + 1] = c.name end end
        local line = L("work_core.exam.current", { rank = rankName })
        if #certs > 0 then line = line .. "  ·  " .. table.concat(certs, ", ") end
        text(line, x + w + s(10), y, PW - 2 * PAD, s(26), rgb(C.muted), 13, false, "left", "center")
    end
    -- close
    local cx, cy, cs = PX + PW - PAD - s(32), PY + PAD, s(32)
    local hot = hovered(cx, cy, cs, cs)
    round(cx, cy, cs, cs, s(6), rgb(hot and C.line or C.card))
    text("✕", cx, cy, cs, cs, rgb(C.ink), 14, true, "center", "center")
    button(cx, cy, cs, cs, function()
        if panel.view == "question" and not panel.abortArmed then
            panel.abortArmed = getTickCount()
            return
        end
        close()
    end)
end

local function drawSelect(o)
    drawHeader(o, L.upper(L("work_core.exam.centre_title", { work = o.workName })))
    drawTabs(PX + PW - PAD - s(32) - s(20) - s(300), PY + PAD)
    local y = PY + PAD + s(90)
    if panel.tab == "exams" then
        local main, extra = {}, {}
        for _, c in ipairs(o.cards) do
            if c.row == "cert" then extra[#extra + 1] = c else main[#main + 1] = c end
        end
        text(L.upper(L("work_core.exam.row_competency")), PX + PAD, y, PW, s(20), rgb(C.muted), 12, true)
        y = drawCards(o, main, y + s(24))
        if #extra > 0 then
            text(L.upper(L("work_core.exam.row_additional")), PX + PAD, y, PW, s(20), rgb(C.muted), 12, true)
            drawCards(o, extra, y + s(24))
        end
    else
        text(L.upper(L("work_core.exam.minigames_note")), PX + PAD, y, PW, s(20), rgb(C.muted), 12, true)
        local cols, gap = 4, s(14)
        local cw = (PW - 2 * PAD - gap * (cols - 1)) / cols
        local ch = s(150)
        for i, m in ipairs(o.minigames or {}) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local x, cy = PX + PAD + col * (cw + gap), y + s(24) + row * (ch + gap)
            round(x, cy, cw, ch, s(9), rgb(C.card))
            outline(x, cy, cw, ch, rgb(C.line), 1)
            text(L(tostring(m.name)), x + s(12), cy + s(12), cw - s(24), s(24), rgb(C.ink), 16, true)
            text(m.desc and L(tostring(m.desc)) or "", x + s(12), cy + s(40), cw - s(24), s(54), rgb(C.muted), 12, false, "left", "top", true)
            local by = cy + ch - s(46)
            local hot = hovered(x + s(12), by, cw - s(24), s(34))
            round(x + s(12), by, cw - s(24), s(34), s(6), rgb(hot and { 70, 130, 255 } or C.sel))
            text(L("work_core.exam.try_minigame"), x + s(12), by, cw - s(24), s(34), rgb(C.ink), 13, true, "center", "center")
            button(x + s(12), by, cw - s(24), s(34), function() startMinigame(m) end)
        end
    end
    -- help hint
    local hy = PY + PH - PAD - s(44)
    local hot = o.help and hovered(PX + PAD, hy, PW - 2 * PAD, s(44))
    round(PX + PAD, hy, PW - 2 * PAD, s(44), s(8), rgb(hot and C.card2 or C.card))
    round(PX + PAD + s(12), hy + s(9), s(40), s(26), s(4), rgb(C.gold))
    text("F1", PX + PAD + s(12), hy + s(9), s(40), s(26), tocolor(17, 17, 17), 13, true, "center", "center")
    text(L("work_core.exam.help_hint"), PX + PAD + s(64), hy, PW - 2 * PAD - s(76), s(44), rgb(C.muted), 13, false, "left", "center", true)
    if o.help then button(PX + PAD, hy, PW - 2 * PAD, s(44), function() openHelp(o.help) end) end
end

local function drawQuestion(o)
    local q = panel.question
    drawHeader(nil, q and L.upper(q.title) or "")
    if panel.abortArmed then
        if getTickCount() - panel.abortArmed > 4000 then panel.abortArmed = nil
        else text(L("work_core.exam.abort_confirm"), PX + PAD, PY + PAD + s(40), PW - 2 * PAD - s(40), s(24), rgb(C.bad), 13, true) end
    end
    if not q then
        text(L("work_core.exam.waiting"), PX, PY, PW, PH, rgb(C.muted), 16, false, "center", "center")
        return
    end
    local x, w = PX + PAD + s(60), PW - 2 * PAD - s(120)
    local y = PY + PAD + s(72)
    text(("%d / %d"):format(q.index, q.total), x, y, w, s(18), rgb(C.muted), 12, true, "right")
    dxDrawRectangle(x, y + s(22), w, s(4), rgb(C.line))
    dxDrawRectangle(x, y + s(22), w * (q.index - 1) / q.total, s(4), rgb(C.gold))
    y = y + s(40)
    text(q.text, x, y, w, s(80), rgb(C.ink), 19, true, "left", "top", true)
    y = y + s(84)
    local tex = texture(q.image)
    if tex then
        local tw, th = dxGetMaterialSize(tex)
        local ih = s(170)
        local iw = math.min(w, ih * tw / th)
        ih = iw * th / tw
        round(x + (w - iw) / 2 - s(6), y - s(6), iw + s(12), ih + s(12), s(8), tocolor(255, 255, 255))
        dxDrawImage(x + (w - iw) / 2, y, iw, ih, tex)
        y = y + ih + s(20)
    end
    local ah = s(54)
    local fb = panel.feedback
    for k, a in ipairs(q.answers) do
        local ay = y + (k - 1) * (ah + s(8))
        local picked = panel.pick == k
        -- after scoring: the correct answer green, a wrong pick red
        local mark = fb and (k == fb.correct and C.ok or (k == fb.pick and C.bad)) or nil
        local hot = not panel.sent and hovered(x, ay, w, ah)
        local bg = mark and { mark[1] * 0.35, mark[2] * 0.35, mark[3] * 0.35 } or (picked and C.selBg or (hot and C.card2 or C.card))
        round(x, ay, w, ah, s(8), rgb(bg))
        outline(x, ay, w, ah, rgb(mark or (picked and C.sel or C.line)), (mark or picked) and 2 or 1)
        round(x + s(12), ay + (ah - s(28)) / 2, s(28), s(28), s(14), rgb(mark or (picked and C.sel or C.card2)))
        text(tostring(k), x + s(12), ay, s(28), ah, rgb((mark or picked) and C.ink or C.muted), 13, true, "center", "center")
        text(a, x + s(52), ay, w - s(64), ah, rgb(C.ink), 15, false, "left", "center", true)
        if not panel.sent then
            button(x, ay, w, ah, function() panel.pick = k; playSoundFrontEnd(1) end, function() panel.pick = k; send() end)
        end
    end
    local fy = PY + PH - PAD - s(44)
    if fb then
        local right = fb.pick == fb.correct
        text(right and L("work_core.exam.answer_right") or L("work_core.exam.answer_wrong"), x, fy, w - s(180), s(44),
            rgb(right and C.ok or C.bad), 16, true, "left", "center")
    else
        text(L("work_core.exam.controls_hint"), x, fy, w - s(180), s(44), rgb(C.muted), 12, false, "left", "center")
    end
    local bx, bw = x + w - s(170), s(170)
    local can = panel.pick ~= nil and not panel.sent
    round(bx, fy, bw, s(44), s(7), rgb(C.gold, can and 255 or 90))
    text(L.upper(L("work_core.exam.send")), bx, fy, bw, s(44), tocolor(17, 17, 17, can and 255 or 120), 15, true, "center", "center")
    if can then button(bx, fy, bw, s(44), send) end
end

local function drawResult(o)
    local r = panel.result
    drawHeader(nil, L.upper(r.title))
    local col = r.passed and C.ok or C.bad
    text(("%d%%"):format(r.percent), PX, PY + s(170), PW, s(120), rgb(col), 64, true, "center", "center")
    text(L("work_core.exam.result_line", { correct = r.correct, total = r.total, pass = r.pass }), PX, PY + s(300), PW, s(30),
        rgb(C.ink), 17, false, "center", "center")
    local msg = r.aborted and L("work_core.exam.result_aborted")
        or r.passed and (r.granted and L("work_core.exam.result_passed_granted", { comp = r.granted }) or L("work_core.exam.result_passed"))
        or L("work_core.exam.result_failed")
    text(msg, PX + PAD, PY + s(340), PW - 2 * PAD, s(60), rgb(col), 16, true, "center", "top", true)
    local bw, bh = s(260), s(46)
    local bx, by = PX + (PW - bw) / 2, PY + s(440)
    local hot = hovered(bx, by, bw, bh)
    round(bx, by, bw, bh, s(7), rgb(hot and { 70, 130, 255 } or C.sel))
    text(L.upper(L("work_core.exam.back_to_exams")), bx, by, bw, bh, rgb(C.ink), 14, true, "center", "center")
    button(bx, by, bw, bh, function() panel.view, panel.result = "select", nil end)
end

render = function()
    if not panel then return end
    buttons = {}
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 110))
    round(PX, PY, PW, PH, s(14), rgb(C.bg))
    outline(PX, PY, PW, PH, rgb(C.line), 1)
    local o = panel.overview
    if panel.view == "question" then drawQuestion(o)
    elseif panel.view == "result" and panel.result then drawResult(o)
    elseif o then drawSelect(o)
    else text(L("work_core.exam.loading"), PX, PY, PW, PH, rgb(C.muted), 16, false, "center", "center") end
end

---------------------------------------------------------------- input

local function hit(cx, cy)
    for i = #buttons, 1, -1 do
        if isInside(buttons[i], cx, cy) then return buttons[i] end
    end
    return nil
end

onClick = function(btn, state, cx, cy)
    if btn ~= "left" or state ~= "down" or not panel then return end
    local b = hit(cx, cy)
    if b then b.fn() end
end

onDoubleClick = function(btn, cx, cy)
    if btn ~= "left" or not panel then return end
    local b = hit(cx, cy)
    if b and b.dbl then b.dbl() end
end

onKey = function(key, press)
    if not panel or not press or isChatBoxInputActive() or isConsoleActive() then return end
    if panel.view == "question" and panel.question and not panel.sent then
        local n = tonumber(key:match("^num_(%d)$") or key)
        if n and n >= 1 and n <= #panel.question.answers then
            panel.pick = n
            cancelEvent()
        elseif (key == "enter" or key == "num_enter") and panel.pick then
            send()
            cancelEvent()
        end
    elseif key == "backspace" and panel.view ~= "question" then
        close()
    end
end

addEventHandler("onClientResourceStop", resourceRoot, function() close(true) end)
addEventHandler("onClientPlayerWasted", localPlayer, function() close(true) end)
