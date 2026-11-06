-- ER hospital information system (DX): the shell of the J tablet (720x470, bottom right, modern
-- design) and the pages of the hospital PC (E at a PC). The PC is a dark Windows 7 style monitor on
-- 80 % of the screen (er/client/w7.lua: desktop, taskbar, windows); its "SBO" window draws the pages
-- here with HIS.drawPC, the patient panel and the med_docs viewer are windows of it too.
-- Tablet: the page selector sits in the top right corner, the back button
-- next to the title (history of pages). A patient opens the patient panel (er/client/exam.lua) in
-- "remote" mode (orders, results, documents, diagnoses; no bedside exam).
--   tablet pages: patients (own / all), todo, comms, notes
--   PC pages:     patients, board (ward / ICU / OR / pre-alerts), stock, comms, notes (+ the Dokumentumtár window)
-- Data: er/server/his.lua (his:request / his:list / his:case / his:dirty / his:action), comms.lua.

HIS = { open = false, mode = "tablet", page = "patients", history = {}, list = {}, board = {}, case = nil, caseId = nil,
        viewer = nil, menu = false, pcs = {}, ownOnly = true, thread = "internal", drugs = nil, stock = nil, tip = nil }

local s = HGfx.s
local T = HTheme
local TRI = { { 211, 57, 43 }, { 229, 130, 42 }, { 224, 180, 28 }, { 51, 148, 90 } }
HIS.TRI = TRI
local images = {}      -- path -> texture | "loading" | false

local function isStaff()
    local v = getElementData(localPlayer, "hosp.staff")
    return v ~= nil and v ~= false
end
HIS.isStaff = isStaff
local function t(key, p) return L("med_hospitals.his." .. key, p) end
HIS.t = t
local function send(what, arg) triggerServerEvent("his:request", resourceRoot, what, arg) end
HIS.send = send
function HIS.act(caseId, ...) triggerServerEvent("his:action", resourceRoot, caseId, ...) end

local PAGES = {
    tablet = { "patients", "todo", "comms", "notes" },
    pc = { "patients", "board", "stock", "comms", "notes" },
}

local function frame()
    if HIS.mode == "pc" then
        local w, h = HGfx.screenW * 0.8, HGfx.screenH * 0.8
        return (HGfx.screenW - w) / 2, (HGfx.screenH - h) / 2, w, h
    end
    local w, h = s(720), s(470)
    return HGfx.screenW - w - s(24), HGfx.screenH - h - s(24), w, h
end

---------------------------------------------------------------- text input (ui_core)

local inputToken, inputDone
function HIS.input(title, maxLen, default, done)
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" or exports.ui_core:isTextInputOpen() then return end
    inputDone = done
    inputToken = exports.ui_core:openTextInput(title, maxLen or 200, default or "", "")
end
addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if not inputToken or token ~= inputToken then return end
    inputToken = nil
    local done = inputDone
    inputDone = nil
    if HIS.open or EXAM and EXAM.open then setTimer(function() showCursor(true) end, 50, 1) end
    if text and text ~= false and done then done(text) end
end)

---------------------------------------------------------------- open / close / navigation

function HIS.show(mode)
    if not isStaff() then return end
    if HIS.open and HIS.mode ~= (mode or "tablet") then HIS.hide() end
    HIS.open, HIS.mode = true, mode or "tablet"
    HIS.viewer, HIS.menu, HIS.history = nil, false, {}
    local allowed = false
    for _, p in ipairs(PAGES[HIS.mode]) do if p == HIS.page and p ~= "docs" then allowed = true end end
    if not allowed then HIS.page = "patients" end
    showCursor(true)
    if HIS.mode == "pc" and PCS then PCS.show("staff") end
    send("list")
end

function HIS.hide()
    if not HIS.open then return end
    HIS.open, HIS.menu = false, false
    if HIS.mode == "pc" and PCS and PCS.open then return PCS.hide() end
    if not (EXAM and EXAM.open) then showCursor(false) end
end

-- the documents (of a case: filter.caseRef): the PC's Dokumentumtár window, else the med_docs panel
function HIS.openDocuments(filter)
    if PCS and PCS.open then return PCS.openWindow("docs", filter or {}) end
    local res = getResourceFromName("med_docs")
    if res and getResourceState(res) == "running" then
        if EXAM and EXAM.open then EXAM.close() end
        HIS.hide()
        exports.med_docs:openDocuments(filter or {})
    end
end

function HIS.go(page)
    if page == HIS.page then HIS.menu = false return end
    if page == "docs" then return HIS.openDocuments({}) end
    HIS.history[#HIS.history + 1] = HIS.page
    HIS.page, HIS.menu = page, false
    if page == "stock" then send("stock") end
    send("list")
end

function HIS.back()
    local prev = table.remove(HIS.history)
    if prev then HIS.page = prev send("list") end
end

local function canUseKeys()
    return not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
        and not getElementData(localPlayer, "textInputOpen") and not getElementData(localPlayer, "browserOpen")
end
HIS.canUseKeys = canUseKeys

bindKey("j", "down", function()
    if not canUseKeys() or not isStaff() then return end
    if PCS and PCS.open then return PCS.hide() end
    if EXAM and EXAM.open then return EXAM.close() end
    if HIS.open then return HIS.hide() end
    if not getPedOccupiedVehicle(localPlayer) then HIS.show("tablet") end
end)

---------------------------------------------------------------- data

addEvent("his:list", true)
addEventHandler("his:list", resourceRoot, function(list, board) HIS.list, HIS.board = list or {}, board or {} end)
addEvent("his:case", true)
addEventHandler("his:case", resourceRoot, function(c)
    HIS.case = c or nil
    if not c then HIS.caseId = nil end
    if EXAM and EXAM.onCase then EXAM.onCase(c) end
end)
addEvent("his:drugs", true)
addEventHandler("his:drugs", resourceRoot, function(list) HIS.drugs = list or {} end)
addEvent("his:stock", true)
addEventHandler("his:stock", resourceRoot, function(v) HIS.stock = v end)
addEvent("his:dirty", true)
addEventHandler("his:dirty", resourceRoot, function()
    if HIS.open then send("list") if HIS.page == "stock" then send("stock") end end
    if EXAM and EXAM.open and EXAM.caseId then send("case", EXAM.caseId) end
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "hosp.staff" and not isStaff() then HIS.hide() if EXAM and EXAM.open then EXAM.close() end end
end)

-- a minigame starts (er/server/minigames.lua): the panels close
addEvent("his:hide", true)
addEventHandler("his:hide", resourceRoot, function()
    if EXAM and EXAM.open then EXAM.close() end
    HIS.hide()
end)

function HIS.openCase(id, bedside)
    HIS.caseId = id
    if EXAM then EXAM.show(id, bedside) end
end

---------------------------------------------------------------- images (downloaded on demand)

function HIS.image(path)
    local v = images[path]
    if v == nil then
        images[path] = "loading"
        if fileExists(path) then images[path] = dxCreateTexture(path) or false else downloadFile(path) end
        return nil
    end
    return v ~= "loading" and v or nil
end
addEventHandler("onClientFileDownloadComplete", resourceRoot, function(path, ok)
    if images[path] == "loading" then images[path] = ok and dxCreateTexture(path) or false end
end)
function HIS.imagePath(kind, file) return (ERC.IMAGE_PATH[kind] or "%s"):format(file) end

-- export (med_docs viewer): downloads an imaging file of this resource if it is not there yet
function requestImage(path)
    if type(path) ~= "string" or not path:find("^er/img/") then return false end
    if not fileExists(path) then downloadFile(path) end
    return true
end

---------------------------------------------------------------- small widgets (shared with exam.lua)

function HIS.triBadge(x, y, w, h, level)
    local c = TRI[level or 0]
    HGfx.round(x, y, w, h, s(4), c and HGfx.rgb(c) or tocolor(110, 120, 130))
    HGfx.text(level and level > 0 and ("T" .. level) or "?", x, y, w, h, tocolor(255, 255, 255), HGfx.font(9, true), "center")
end

function HIS.chip(x, y, label, color, font)
    local f = font or HGfx.font(8, true)
    local w = L.width(label, 1, f) + s(14)
    HGfx.round(x, y, w, s(18), s(9), color or T.panel2)
    HGfx.text(label, x, y, w, s(18), T.text, f, "center")
    return w
end

function HIS.hhmm(ts)
    if not ts then return "" end
    local tm = getRealTime(ts)
    return ("%02d:%02d"):format(tm.hour, tm.minute)
end
function HIS.mins(sec) return math.max(0, math.floor((sec or 0) / 60)) end

-- tooltip of the hovered element, drawn last
function HIS.tooltip(x, y, w, h, text)
    if text and HGfx.hover(x, y, w, h) then HIS.tip = text end
end
local function drawTip()
    local tip = HIS.tip
    HIS.tip = nil
    if not tip or tip == "" then return end
    local cx, cy = HGfx.cursor()
    local f = HGfx.font(9)
    local lines = HGfx.wrap(tip, s(320), f)
    local w, h = s(20), s(10) + #lines * s(16)
    for _, ln in ipairs(lines) do w = math.max(w, L.width(ln, 1, f) + s(20)) end
    local x, y = math.min(cx + s(14), HGfx.screenW - w - s(4)), math.min(cy + s(14), HGfx.screenH - h - s(4))
    HGfx.round(x, y, w, h, s(5), tocolor(8, 10, 12, 240))
    for i, ln in ipairs(lines) do HGfx.text(ln, x + s(10), y + s(5) + (i - 1) * s(16), w, s(16), T.text, f) end
end
HIS.drawTip = drawTip

---------------------------------------------------------------- header with back + page selector

local function pageName(p) return t("page_" .. p) end

local function drawHeader(x, y, w, h)
    HGfx.round(x, y, w, h, s(8), T.header)
    dxDrawRectangle(x, y + h - s(8), w, s(8), T.header)
    dxDrawRectangle(x, y + h - 1, w, 1, T.line)
    local bx = x + s(10)
    if #HIS.history > 0 then
        HGfx.button(bx, y + s(8), s(34), h - s(16), "‹", { color = { 40, 48, 58 }, font = HGfx.font(14, true) }, HIS.back)
        HIS.tooltip(bx, y + s(8), s(34), h - s(16), t("back"))
        bx = bx + s(42)
    end
    local ls = s(26)
    HGfx.round(bx, y + (h - ls) / 2, ls, ls, s(5), T.accent)
    HGfx.cross(bx + s(6), y + (h - ls) / 2 + s(6), ls - s(12), tocolor(255, 255, 255))
    HGfx.text(t(HIS.mode == "pc" and "title_pc" or "title_tablet") .. "  ·  " .. pageName(HIS.page), bx + s(34), y, w * 0.5, h, T.text, HGfx.font(12, true))
    -- right: name · points · time, page selector, close
    local closeW = s(34)
    HGfx.button(x + w - closeW - s(8), y + s(8), closeW, h - s(16), "X", { color = { 60, 40, 44 } }, HIS.hide)
    local label = "☰  " .. pageName(HIS.page)
    local selW = L.width(label, 1, HGfx.font(10, true)) + s(28)
    local selX = x + w - closeW - s(16) - selW
    HGfx.button(selX, y + s(8), selW, h - s(16), label, { color = HIS.menu and { 47, 134, 232 } or { 40, 48, 58 } }, function() HIS.menu = not HIS.menu end)
    HIS.menuAnchor = { selX, y + h - s(4), selW }
    local tm = getRealTime()
    local pts = getElementData(localPlayer, "hosp.points") or 0
    HGfx.text(("%s · %d %s · %02d:%02d"):format(getPlayerName(localPlayer):gsub("#%x%x%x%x%x%x", ""), pts, t("points"), tm.hour, tm.minute),
        x, y, selX - x - s(12), h, T.dim, HGfx.font(9), "right")
end

local function drawMenu()
    local a = HIS.menuAnchor
    if not a then return end
    HGfx.hits = {}
    local pages = PAGES[HIS.mode]
    local w = math.max(a[3], s(220))
    local x = a[1] + a[3] - w
    local y = a[2]
    local rowH = s(34)
    HGfx.hit(0, 0, HGfx.screenW, HGfx.screenH, function() HIS.menu = false end)
    HGfx.round(x, y, w, #pages * rowH + s(10), s(8), tocolor(16, 19, 23, 248))
    for i, p in ipairs(pages) do
        local ry = y + s(5) + (i - 1) * rowH
        local on = p == HIS.page
        local hov = HGfx.hover(x + s(5), ry, w - s(10), rowH - s(2))
        HGfx.round(x + s(5), ry, w - s(10), rowH - s(2), s(5), on and T.accent or (hov and T.panel2 or T.panel))
        HGfx.text(pageName(p), x + s(16), ry, w - s(30), rowH - s(2), T.text, HGfx.font(10, true))
        HGfx.hit(x + s(5), ry, w - s(10), rowH - s(2), function() HIS.go(p) end)
    end
end

---------------------------------------------------------------- page: patients

local function drawPatients(x, y, w, h)
    local rowH = s(42)
    local own = HIS.mode == "tablet" and HIS.ownOnly
    -- filter row (tablet: own / all)
    local fy = y
    if HIS.mode == "tablet" then
        HGfx.button(x, fy, s(130), s(26), t("own_patients"), { color = own and { 47, 134, 232 } or { 34, 40, 48 }, font = HGfx.font(9, true) }, function() HIS.ownOnly = true end)
        HGfx.button(x + s(136), fy, s(130), s(26), t("all_patients"), { color = (not own) and { 47, 134, 232 } or { 34, 40, 48 }, font = HGfx.font(9, true) }, function() HIS.ownOnly = false end)
        fy = fy + s(32)
    end
    local me = getElementData(localPlayer, "displayName") or getPlayerName(localPlayer)
    local rows = {}
    for _, c in ipairs(HIS.list) do
        if not own or c.treating == me or not c.treating then rows[#rows + 1] = { case = c } end
    end
    for _, u in ipairs(HIS.board.unregistered or {}) do rows[#rows + 1] = { unreg = u } end
    local cols = HIS.mode == "pc" and { 0.06, 0.26, 0.12, 0.08, 0.12, 0.16, 0.20 } or { 0.08, 0.34, 0.16, 0.20, 0.22 }
    local heads = HIS.mode == "pc" and { "", t("col_patient"), t("col_arrival"), t("col_wait"), t("col_place"), t("col_treating"), t("col_status") }
        or { "", t("col_patient"), t("col_place"), t("col_treating"), t("col_status") }
    local hx = x
    for i, cw in ipairs(cols) do HGfx.text(heads[i], hx + s(8), fy, w * cw, s(20), T.faint, HGfx.font(8, true)) hx = hx + w * cw end
    local top = fy + s(22)
    local visible = math.floor((y + h - top) / rowH)
    local off = HGfx.getScroll("plist", #rows - visible)
    HGfx.scrollArea("plist", x, top, w, y + h - top)
    for i = 1, math.min(visible, #rows - off) do
        local r = rows[i + off]
        local ry = top + (i - 1) * rowH
        local hov = HGfx.hover(x, ry, w, rowH - s(4))
        HGfx.round(x, ry, w, rowH - s(4), s(6), hov and T.panel2 or T.panel)
        local cx = x
        local values
        if r.case then
            local c = r.case
            values = {
                function(cx2, cw) HIS.triBadge(cx2 + s(8), ry + (rowH - s(24)) / 2, s(30), s(20), c.triage) end,
                function(cx2, cw)
                    HGfx.text(HGfx.fit(c.name or t("unknown"), cw - s(12), HGfx.font(10, true)), cx2 + s(8), ry + s(3), cw, s(20), T.text, HGfx.font(10, true))
                    HGfx.text(("%s%s"):format(c.age and (c.age .. " · ") or "", t("gender_" .. tostring(c.gender))), cx2 + s(8), ry + s(20), cw, s(16), T.dim, HGfx.font(8))
                end,
            }
            local status = c.dead and t("status_dead") or t("status_" .. tostring(c.status))
            local arrival = c.unit and (c.unit) or t("arrival_" .. tostring(c.arrival))
            local function chipCol(cx2, cw)
                local cwid = HIS.chip(cx2 + s(8), ry + (rowH - s(22)) / 2, status, c.dead and tocolor(90, 30, 30) or T.panel2)
                if (c.pending or 0) > 0 then HIS.chip(cx2 + s(14) + cwid, ry + (rowH - s(22)) / 2, t("pending", { n = c.pending }), tocolor(30, 70, 120)) end
            end
            if HIS.mode == "pc" then
                values[#values + 1] = function(cx2, cw) HGfx.text(arrival .. "\n" .. HIS.hhmm(c.created), cx2 + s(8), ry, cw, rowH - s(4), T.text, HGfx.font(8)) end
                values[#values + 1] = function(cx2, cw) HGfx.text(t("min_short", { n = HIS.mins(getRealTime().timestamp - (c.created or 0)) }), cx2 + s(8), ry, cw, rowH - s(4), T.text, HGfx.font(9)) end
            end
            values[#values + 1] = function(cx2, cw) HGfx.text(tostring(c.location or "-"), cx2 + s(8), ry, cw, rowH - s(4), T.text, HGfx.font(9)) end
            values[#values + 1] = function(cx2, cw) HGfx.text(HGfx.fit(c.treating or "—", cw - s(10), HGfx.font(9)), cx2 + s(8), ry, cw, rowH - s(4), c.treating and T.text or T.faint, HGfx.font(9)) end
            values[#values + 1] = chipCol
            HGfx.hit(x, ry, w, rowH - s(4), function() HIS.openCase(c.id, false) end)
        else
            local u = r.unreg
            values = {
                function(cx2, cw) HIS.triBadge(cx2 + s(8), ry + (rowH - s(24)) / 2, s(30), s(20), 0) end,
                function(cx2, cw) HGfx.text(t(u.gender == "female" and "unknown_female" or "unknown_male"), cx2 + s(8), ry, cw, rowH - s(4), T.text, HGfx.font(10, true)) end,
            }
            if HIS.mode == "pc" then
                values[#values + 1] = function(cx2, cw) HGfx.text(t("arrival_brought"), cx2 + s(8), ry, cw, rowH - s(4), T.text, HGfx.font(8)) end
                values[#values + 1] = function() end
            end
            values[#values + 1] = function(cx2, cw) HGfx.text(t("in_er"), cx2 + s(8), ry, cw, rowH - s(4), T.dim, HGfx.font(9)) end
            values[#values + 1] = function() end
            values[#values + 1] = function(cx2, cw)
                HGfx.button(cx2 + s(6), ry + s(7), math.min(cw - s(12), s(120)), rowH - s(18), t("register"), { color = { 47, 134, 232 }, font = HGfx.font(9, true) }, function() send("register", u.token) end)
            end
        end
        for ci, cw in ipairs(cols) do
            if values[ci] then values[ci](cx, w * cw) end
            cx = cx + w * cw
        end
    end
    if #rows == 0 then HGfx.text(t(own and "no_own_patients" or "no_patients"), x, top + s(30), w, s(30), T.faint, HGfx.font(10), "center") end
end

---------------------------------------------------------------- page: todo

local TODO_COLOR = { ok = { 63, 179, 122 }, need = { 229, 160, 58 }, run = { 47, 134, 232 }, hint = { 150, 160, 172 }, todo = { 150, 160, 172 } }
local TODO_ICON = { ok = "✓", need = "!", run = "◔", hint = "?", todo = "·" }
HIS.TODO_COLOR, HIS.TODO_ICON = TODO_COLOR, TODO_ICON

function HIS.todoText(td)
    local p = {}
    for k, val in pairs(td.params or {}) do p[k] = val end
    if p.order then p.order = L("med_hospitals.erc.order_" .. tostring(p.order):gsub("%.", "_")) end
    if p.region then p.region = t("region_" .. p.region) end
    return L("med_hospitals.his." .. td.key, p)
end

local function drawTodo(x, y, w, h)
    local listW = s(200)
    HGfx.text(t("todo_pick"), x, y, listW, s(20), T.faint, HGfx.font(8, true))
    local by = y + s(22)
    for _, c in ipairs(HIS.list) do
        if by > y + h - s(34) then break end
        local on = HIS.todoCase == c.id
        HGfx.button(x, by, listW, s(32), ("T%s  %s"):format(c.triage > 0 and c.triage or "?", c.name or t("unknown")),
            { align = "left", color = on and { 47, 134, 232 } or { 34, 40, 48 }, font = HGfx.font(9, true) },
            function() HIS.todoCase = c.id send("case", c.id) end)
        by = by + s(36)
    end
    local tx, tw = x + listW + s(12), w - listW - s(12)
    local c = HIS.case
    if not c or c.id ~= HIS.todoCase then
        return HGfx.text(t("todo_pick_hint"), tx, y + s(30), tw, s(30), T.faint, HGfx.font(10), "center")
    end
    HGfx.text(t("todo_for", { name = c.name or t("unknown") }), tx, y, tw - s(110), s(24), T.text, HGfx.font(11, true))
    HGfx.button(tx + tw - s(104), y, s(104), s(24), t("open_patient"), { color = { 47, 134, 232 }, font = HGfx.font(9, true) }, function() HIS.openCase(c.id, false) end)
    by = y + s(32)
    for _, td in ipairs(c.todos or {}) do
        if by > y + h - s(30) then break end
        local col = TODO_COLOR[td.state] or TODO_COLOR.todo
        HGfx.round(tx, by, tw, s(30), s(5), T.panel)
        dxDrawRectangle(tx, by, s(3), s(30), HGfx.rgb(col))
        HGfx.text(TODO_ICON[td.state] or "·", tx + s(8), by, s(20), s(30), HGfx.rgb(col), HGfx.font(11, true), "center")
        HGfx.text(HGfx.fit(HIS.todoText(td), tw - s(44), HGfx.font(10)), tx + s(34), by, tw - s(40), s(30), T.text, HGfx.font(10))
        by = by + s(34)
    end
end

---------------------------------------------------------------- page: board (PC)

local function drawBoard(x, y, w, h)
    local b = HIS.board or {}
    HGfx.text(t("board_summary", { free = b.corridorFree or 0, stretchers = b.stretchers or 0 }), x, y, w, s(22), T.dim, HGfx.font(10))
    local o = b["or"] or {}
    HGfx.round(x, y + s(26), w, s(34), s(6), o.busy and tocolor(70, 40, 40) or T.panel)
    HGfx.text(o.busy and t("or_busy", { name = o.name or t("unknown"), min = math.ceil((o.left or 0) / 60) }) or t("or_free"),
        x + s(12), y + s(26), w * 0.5, s(34), T.text, HGfx.font(10, true))
    -- the waiting place (U10) and the surgery requests waiting for a Physician (U2)
    local qs = {}
    for i, q in ipairs(b.orQueue or {}) do
        qs[#qs + 1] = ("%d. %s (%s%s)"):format(i, q.name or t("unknown"), L("med_hospitals.erc.surgery_" .. q.surgery), q.priority and ", !" or "")
    end
    HGfx.text(#qs > 0 and t("or_queue", { list = table.concat(qs, " · ") }) or t("or_queue_empty"), x + w * 0.5, y + s(26), w * 0.5 - s(12), s(34), T.dim, HGfx.font(9), "right")
    local ry = y + s(66)
    for _, r in ipairs(b.requests or {}) do
        HGfx.round(x, ry, w, s(30), s(5), tocolor(70, 55, 25))
        HGfx.text(t("or_request", { name = r.name or t("unknown"), by = r.by, what = L("med_hospitals.erc.surgery_" .. r.surgery) }), x + s(10), ry, w - s(250), s(30), T.text, HGfx.font(9, true))
        HGfx.button(x + w - s(236), ry + s(3), s(110), s(24), t("or_approve"), { color = { 40, 150, 90 }, font = HGfx.font(9, true) }, function() HIS.act(r.id, "outcome", "surgery_approve") end)
        HGfx.button(x + w - s(120), ry + s(3), s(110), s(24), t("or_reject"), { color = { 150, 50, 50 }, font = HGfx.font(9, true) }, function() HIS.act(r.id, "outcome", "surgery_reject") end)
        ry = ry + s(34)
    end
    y = ry - s(66)
    local function beds(title, list, by)
        HGfx.text(title, x, by, w, s(20), T.faint, HGfx.font(8, true))
        local bw, bh = (w - s(5 * 6)) / 6, s(46)
        for i, bed in ipairs(list or {}) do
            local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
            local bx, byy = x + col * (bw + s(6)), by + s(20) + row * (bh + s(6))
            HGfx.round(bx, byy, bw, bh, s(6), bed.free and T.panel or (bed.paused and tocolor(110, 40, 40) or tocolor(30, 70, 120)))
            HGfx.text(bed.free and t("bed_free") or HGfx.fit(bed.name or t("unknown"), bw - s(8), HGfx.font(9, true)), bx + s(6), byy + s(2), bw - s(8), s(22), T.text, HGfx.font(9, true))
            if not bed.free then
                HGfx.text(bed.paused and t("bed_alert") or t("bed_left", { min = math.ceil((bed.left or 0) / 60) }), bx + s(6), byy + s(22), bw - s(8), s(20), T.dim, HGfx.font(8))
                HGfx.hit(bx, byy, bw, bh, function() if bed.id then HIS.openCase(bed.id, false) end end)
            end
        end
        return by + s(20) + math.ceil(#(list or {}) / 6) * (bh + s(6))
    end
    local by = beds(t("board_ward"), b.ward, y + s(70))
    by = beds(t("board_icu"), b.icu, by + s(6))
    HGfx.text(t("board_cards"), x, by + s(4), w, s(20), T.faint, HGfx.font(8, true))
    by = by + s(24)
    for _, card in ipairs(b.cards or {}) do
        if by > y + h - s(24) then break end
        local parts = {}
        for _, it in ipairs(card.items or {}) do parts[#parts + 1] = L("med_hospitals.comms.p_" .. it.key) .. " " .. tostring(it.value) end
        HGfx.round(x, by, w, s(24), s(4), T.panel)
        HGfx.text(("%s  %s  ·  %s"):format(HIS.hhmm(card.at), card.unit, HGfx.fit(table.concat(parts, " · "), w - s(140), HGfx.font(9))), x + s(8), by, w - s(12), s(24), T.text, HGfx.font(9))
        by = by + s(28)
    end
end

---------------------------------------------------------------- page: stock (PC)

local function drawStock(x, y, w, h)
    local v = HIS.stock
    if not v then return HGfx.text(t("loading"), x, y, w, s(30), T.faint, HGfx.font(10), "center") end
    local head = v.order and t("stock_order_pending", { s = v.order.left, cost = v.order.cost }) or t("stock_missing_cost", { cost = v.cost or 0 })
    HGfx.text(head, x, y, w - s(170), s(26), T.text, HGfx.font(10, true))
    HGfx.button(x + w - s(160), y, s(160), s(26), t("stock_order"), { color = { 47, 134, 232 }, disabled = v.order or (v.cost or 0) <= 0, font = HGfx.font(9, true) },
        function() send("stockOrder") end)
    local colW = (w - s(4 * 8)) / 5
    for i, pool in ipairs(v.pools or {}) do
        local px = x + (i - 1) * (colW + s(8))
        HGfx.text(t("pool_" .. pool.id), px, y + s(34), colW, s(20), T.faint, HGfx.font(8, true))
        local rowH = s(18)
        local top = y + s(56)
        local visible = math.floor((y + h - top) / rowH)
        local off = HGfx.getScroll("pool" .. i, #pool.items - visible)
        HGfx.scrollArea("pool" .. i, px, top, colW, y + h - top)
        for j = 1, math.min(visible, #pool.items - off) do
            local it = pool.items[j + off]
            local ry = top + (j - 1) * rowH
            local low = not it.device and it.left < it.full
            HGfx.text(HGfx.fit(L("med_hospitals.stock.item_" .. it.id), colW - s(52), HGfx.font(8)), px, ry, colW - s(50), rowH, it.device and T.dim or T.text, HGfx.font(8))
            HGfx.text(it.device and t("device") or ("%d/%d"):format(it.left, it.full), px + colW - s(50), ry, s(48), rowH,
                (it.left == 0 and not it.device) and tocolor(255, 120, 110) or (low and tocolor(229, 160, 58) or T.dim), HGfx.font(8, true), "right")
        end
    end
end

---------------------------------------------------------------- page: comms

local function drawComms(x, y, w, h)
    local listW = s(190)
    local threads = HIS.board.threads or {}
    local by = y
    local found = false
    for _, th in ipairs(threads) do
        if th.key == HIS.thread then found = true end
        local on = th.key == HIS.thread
        local label = th.kind == "internal" and t("thread_internal") or th.unit
        local sub = #(th.msgs or {}) > 0 and HIS.hhmm(th.at) or ""
        HGfx.round(x, by, listW, s(40), s(5), on and tocolor(30, 70, 120) or T.panel)
        HGfx.text(label, x + s(10), by + s(3), listW - s(20), s(20), T.text, HGfx.font(10, true))
        HGfx.text(sub, x + s(10), by + s(20), listW - s(20), s(16), T.dim, HGfx.font(8))
        HGfx.hit(x, by, listW, s(40), function() HIS.thread = th.key end)
        by = by + s(44)
        if by > y + h - s(40) then break end
    end
    if not found then HIS.thread = "internal" end
    local th
    for _, x2 in ipairs(threads) do if x2.key == HIS.thread then th = x2 end end
    local mx, mw = x + listW + s(12), w - listW - s(12)
    local inputH = s(30)
    HGfx.round(mx, y, mw, h - inputH - s(6), s(6), tocolor(16, 19, 23))
    local msgs = th and th.msgs or {}
    local my = y + h - inputH - s(14)
    for i = #msgs, 1, -1 do
        local m = msgs[i]
        local text = m.text
        if m.card then
            local parts = {}
            for _, it in ipairs(m.card) do parts[#parts + 1] = L("med_hospitals.comms.p_" .. it.key) .. " " .. tostring(it.value) end
            text = t("params_card") .. ": " .. table.concat(parts, " · ")
        end
        local lines = HGfx.wrap(tostring(text or ""), mw * 0.7 - s(20), HGfx.font(9))
        local bh = s(20) + #lines * s(15)
        my = my - bh - s(6)
        if my < y + s(4) then break end
        local mine = m.side == "hospital"
        local bw = mw * 0.72
        local bx = mine and (mx + mw - bw - s(8)) or (mx + s(8))
        HGfx.round(bx, my, bw, bh, s(6), mine and tocolor(29, 58, 92) or (m.card and tocolor(60, 44, 26) or T.panel))
        HGfx.text(("%s · %s"):format(m.from or "?", HIS.hhmm(m.at)), bx + s(8), my + s(2), bw - s(16), s(16), T.dim, HGfx.font(8))
        for li, ln in ipairs(lines) do HGfx.text(ln, bx + s(8), my + s(16) + (li - 1) * s(15), bw - s(16), s(15), T.text, HGfx.font(9)) end
    end
    if #msgs == 0 then HGfx.text(t("no_messages"), mx, y + s(20), mw, s(30), T.faint, HGfx.font(10), "center") end
    HGfx.button(mx, y + h - inputH, mw, inputH, t("write_message", { to = th and (th.kind == "internal" and t("thread_internal") or th.unit) or "" }),
        { align = "left", color = { 34, 40, 48 }, font = HGfx.font(9) }, function()
            local key = HIS.thread
            HIS.input(t("write_message_title"), 300, "", function(text) triggerServerEvent("his:message", resourceRoot, key, text) end)
        end)
end

---------------------------------------------------------------- page: notes

local function drawNotes(x, y, w, h)
    local notes = HIS.board.notes or {}
    local rowH = s(34)
    local visible = math.floor(h / rowH)
    local off = HGfx.getScroll("notes", #notes - visible)
    HGfx.scrollArea("notes", x, y, w, h)
    for i = 1, math.min(visible, #notes - off) do
        local n = notes[i + off]
        local ry = y + (i - 1) * rowH
        HGfx.round(x, ry, w, rowH - s(4), s(5), n.alert and tocolor(70, 34, 30) or T.panel)
        HGfx.text(HIS.hhmm(n.at), x + s(10), ry, s(50), rowH - s(4), T.dim, HGfx.font(9, true))
        HGfx.text(HGfx.fit(tostring(n.text):gsub("\n", " · "), w - s(80), HGfx.font(9)), x + s(64), ry, w - s(74), rowH - s(4), T.text, HGfx.font(9))
    end
    if #notes == 0 then HGfx.text(t("no_notes"), x, y + s(30), w, s(30), T.faint, HGfx.font(10), "center") end
end

local DRAW = { patients = drawPatients, todo = drawTodo, board = drawBoard, stock = drawStock, comms = drawComms, notes = drawNotes }

---------------------------------------------------------------- render + input

-- The PC window "SBO" (w7.lua): Win7 toolbar with the pages, the page, a status bar
function HIS.drawPC(x, y, w, h)
    local tb = s(34)
    dxDrawRectangle(x, y, w, tb, tocolor(42, 48, 55))
    dxDrawRectangle(x, y, w, tb / 2, tocolor(255, 255, 255, 8))
    dxDrawRectangle(x, y + tb - 1, w, 1, tocolor(14, 16, 18))
    local bx = x + s(6)
    if #HIS.history > 0 then
        HGfx.button(bx, y + s(5), s(30), tb - s(10), "‹", { color = { 52, 60, 70 }, font = HGfx.font(12, true) }, HIS.back)
        HIS.tooltip(bx, y + s(5), s(30), tb - s(10), t("back"))
        bx = bx + s(36)
    end
    for _, p in ipairs(PAGES.pc) do
        local label = pageName(p)
        local bw = L.width(label, 1, HGfx.font(9, true)) + s(22)
        local on = p == HIS.page
        local hov = HGfx.hover(bx, y + s(5), bw, tb - s(10))
        if on or hov then
            dxDrawRectangle(bx, y + s(5), bw, tb - s(10), tocolor(92, 106, 120))
            dxDrawRectangle(bx + 1, y + s(5) + 1, bw - 2, tb - s(10) - 2, on and tocolor(60, 74, 90) or tocolor(54, 62, 72))
            dxDrawRectangle(bx + 1, y + s(5) + 1, bw - 2, 1, tocolor(255, 255, 255, 35))
        end
        HGfx.text(label, bx, y + s(5), bw, tb - s(10), T.text, HGfx.font(9, on), "center")
        HGfx.hit(bx, y + s(5), bw, tb - s(10), function() HIS.go(p) end)
        bx = bx + bw + s(3)
    end
    -- status bar: name, points, time
    local sb = s(24)
    dxDrawRectangle(x, y + h - sb, w, sb, tocolor(38, 43, 49))
    dxDrawRectangle(x, y + h - sb, w, 1, tocolor(14, 16, 18))
    local pts = getElementData(localPlayer, "hosp.points") or 0
    HGfx.text(("%s  ·  %d %s"):format((getElementData(localPlayer, "displayName") or getPlayerName(localPlayer)):gsub("#%x%x%x%x%x%x", ""), pts, t("points")),
        x + s(10), y + h - sb, w * 0.6, sb, T.dim, HGfx.font(8))
    HGfx.text(t("pc_status_patients", { n = #HIS.list }), x + w * 0.6, y + h - sb, w * 0.4 - s(10), sb, T.dim, HGfx.font(8), "right")
    local fn = DRAW[HIS.page]
    if fn then fn(x + s(10), y + tb + s(8), w - s(20), h - tb - sb - s(16)) end
end

addEventHandler("onClientRender", root, function()
    if not HIS.open or HIS.mode == "pc" or (EXAM and EXAM.open) then return end
    HGfx.hits, HGfx.scrollAreas = {}, {}
    HGfx.setSkin("modern")
    local x, y, w, h = frame()
    HGfx.round(x - s(6), y - s(6), w + s(12), h + s(12), s(14), T.bezel)
    HGfx.round(x, y, w, h, s(8), T.bg)
    local hh = s(46)
    drawHeader(x, y, w, hh)
    local bx, by, bw, bh = x + s(12), y + hh + s(10), w - s(24), h - hh - s(22)
    local fn = DRAW[HIS.page]
    if fn then fn(bx, by, bw, bh) end
    if HIS.menu then drawMenu() end
    drawTip()
end)

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not HIS.open or HIS.mode == "pc" or (EXAM and EXAM.open) or button ~= "left" or state ~= "down" then return end
    HGfx.click(ax, ay)
end)

-- ESC of the PC window "SBO" (w7.lua): the page history, then false (the window closes)
function HIS.escapePC()
    if #HIS.history > 0 then HIS.back() return true end
    return false
end

addEventHandler("onClientKey", root, function(key, press)
    if not HIS.open or HIS.mode == "pc" or (EXAM and EXAM.open) or not press then return end
    if key == "mouse_wheel_up" then HGfx.wheel(-1)
    elseif key == "mouse_wheel_down" then HGfx.wheel(1)
    elseif key == "escape" then
        cancelEvent()
        if HIS.menu then HIS.menu = false elseif #HIS.history > 0 then HIS.back() else HIS.hide() end
    elseif key == "backspace" and #HIS.history > 0 and not getElementData(localPlayer, "textInputOpen") then
        HIS.back()
    end
end)

---------------------------------------------------------------- hospital PCs (E at the desk)

local PC_RANGE = 1.7
local nearPC = false
addEvent("his:pcs", true)
addEventHandler("his:pcs", resourceRoot, function(list) HIS.pcs = list or {} end)
addEventHandler("onClientResourceStart", resourceRoot, function() triggerServerEvent("his:hello", resourceRoot) end)

local function isEms() return getElementData(localPlayer, "work.id") == "ems" end

setTimer(function()
    nearPC = false
    if HIS.open or (EXAM and EXAM.open) or (PCS and PCS.open) or not (isStaff() or isEms()) then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, pc in ipairs(HIS.pcs) do
        if getDistanceBetweenPoints3D(px, py, pz, pc.x, pc.y, pc.z) <= PC_RANGE then nearPC = true break end
    end
end, 300, 0)

addEventHandler("onClientRender", root, function()
    if not nearPC or HIS.open or (EXAM and EXAM.open) or (PCS and PCS.open) then return end
    local text = t("pc_hint")
    local f = HGfx.font(10, true)
    local w = L.width(text, 1, f) + s(30)
    local x, y = (HGfx.screenW - w) / 2, HGfx.screenH * 0.78
    HGfx.round(x, y, w, s(32), s(6), tocolor(14, 18, 22, 210))
    HGfx.text(text, x, y, w, s(32), T.text, f, "center")
end)

bindKey("e", "down", function()
    if not nearPC or HIS.open or (EXAM and EXAM.open) or (PCS and PCS.open) or not canUseKeys() then return end
    if isStaff() then return HIS.show("pc") end
    -- an EMS medic at a hospital PC: the same PC, only the Dokumentumtár with their EMS case sheets
    local res = getResourceFromName("med_docs")
    if res and getResourceState(res) == "running" and not exports.med_docs:isDocumentViewerOpen() and PCS then PCS.show("ems") end
end)

-- /sbo: the tablet without the J key, /sbopc [caseId]: the PC view (both only on hospital duty)
addCommandHandler("sbo", function() if HIS.open then HIS.hide() elseif isStaff() then HIS.show("tablet") end end)
addCommandHandler("sbopc", function(_, id, tab)
    if not id and EXAM and EXAM.open then EXAM.close() return HIS.hide() end
    if HIS.open and not id then return HIS.hide() end
    if not isStaff() then return end
    HIS.show("pc")
    if PCS then PCS.anywhere = true end
    if tonumber(id) then HIS.openCase(tonumber(id), false) if tab and EXAM then EXAM.tab = tab end end
end)
