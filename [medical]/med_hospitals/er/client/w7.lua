-- The hospital PC (E at a PC desk, 2026-11-06): a dark Windows 7 style monitor on 80 % of the screen.
-- Desktop with icons, taskbar (Start button with the hospital cross, a button per open window, clock),
-- maximized windows with a glass title bar and caption buttons:
--   his   "SBO" - the HIS pages (er/client/his.lua HIS.drawPC: patients, board, stock, comms, notes)
--   case  "Beteglap" - the patient panel (er/client/exam.lua EXAM.draw, with the documentation tab)
--   docs  "Dokumentumtár" - the med_docs viewer embedded (exports.med_docs:setDocumentsRect)
-- Staff get every window; an EMS medic at a hospital PC only the Dokumentumtár with their EMS sheets.
-- The PC opens on the desktop with no window open; the icons / Start menu open the applications.
-- Everything is drawn with the "w7" skin of gfx.lua (HGfx.setSkin). The tablet keeps the modern look.

PCS = { open = false, kind = "staff", windows = {}, z = {}, order = {}, start = false }

local s = HGfx.s
local T = HTheme
local function t(key, p) return L("med_hospitals.pc." .. key, p) end
local PC_LEAVE = 3.2   -- m from the PC desk: the PC closes (not when opened with /sbopc)

local WIN = {
    his  = { color = { 208, 71, 59 },  icon = "cross" },
    case = { color = { 91, 143, 196 }, icon = "card" },
    docs = { color = { 226, 226, 220 }, icon = "paper" },
}

-- med_docs running with the embedded viewer (setDocumentsRect, 2026-11-06). An older med_docs (not
-- restarted yet) would open its own panel and fail every frame: the window says so instead.
local embedCache = {}   -- [resource] = true | false
local function docsRunning()
    local res = getResourceFromName("med_docs")
    if not res or getResourceState(res) ~= "running" then return false end
    if embedCache[res] == nil then
        local ok = false
        for _, fn in ipairs(getResourceExportedFunctions(res) or {}) do if fn == "setDocumentsRect" then ok = true end end
        embedCache[res] = ok
    end
    return embedCache[res]
end
addEventHandler("onClientResourceStart", root, function(res) if getResourceName(res) == "med_docs" then embedCache = {} end end)
addEventHandler("onClientResourceStop", root, function(res)
    if getResourceName(res) == "med_docs" then embedCache = {} if PCS.windows.docs then PCS.windows.docs.lost = true end end
end)

local function winTitle(id)
    if id == "his" then return t("win_his") end
    if id == "case" then
        local c = EXAM and EXAM.case
        return t("win_case", { name = c and c.name or "…" })
    end
    return t("win_docs")
end
local function winShort(id)
    if id == "case" then
        local c = EXAM and EXAM.case
        return t("task_case", { name = c and c.name or "…" })
    end
    return t(id == "his" and "task_his" or "task_docs")
end

---------------------------------------------------------------- windows

local function topWindow()
    for i = #PCS.z, 1, -1 do
        local id = PCS.z[i]
        if PCS.windows[id] and not PCS.windows[id].min then return id end
    end
    return nil
end
function PCS.active() return topWindow() end

local function raise(id)
    for i = #PCS.z, 1, -1 do if PCS.z[i] == id then table.remove(PCS.z, i) end end
    PCS.z[#PCS.z + 1] = id
end

function PCS.openWindow(id, arg)
    if not PCS.open or not WIN[id] then return false end
    if PCS.kind == "ems" and id ~= "docs" then return false end
    if not PCS.windows[id] then
        PCS.windows[id] = {}
        PCS.order[#PCS.order + 1] = id
    end
    PCS.windows[id].min = false
    raise(id)
    PCS.start = false
    if id == "docs" then
        if not docsRunning() then return false end
        local filter = arg or PCS.windows.docs.filter or (PCS.kind == "ems" and { type = "ems", only = "ems" } or {})
        PCS.windows.docs.filter = filter
        if exports.med_docs:isDocumentViewerOpen() then
            if arg then exports.med_docs:setDocumentsFilter(filter) end
        else
            exports.med_docs:openDocuments(filter, { embed = true })
        end
    elseif id == "his" then
        if not HIS.open then HIS.open, HIS.mode = true, "pc" HIS.send("list") end
    end
    return true
end

-- fromExam: EXAM.close() asked (the panel is closed already)
function PCS.closeWindow(id, fromExam)
    if not PCS.windows[id] then return end
    PCS.windows[id] = nil
    for i = #PCS.order, 1, -1 do if PCS.order[i] == id then table.remove(PCS.order, i) end end
    for i = #PCS.z, 1, -1 do if PCS.z[i] == id then table.remove(PCS.z, i) end end
    if id == "docs" and docsRunning() then exports.med_docs:closeDocuments() end
    if id == "case" and not fromExam and EXAM and EXAM.open then EXAM.open = false end
end

function PCS.minimize(id)
    if PCS.windows[id] then PCS.windows[id].min = true end
end

function PCS.show(kind)
    if PCS.open then PCS.hide() end
    PCS.open, PCS.kind, PCS.windows, PCS.z, PCS.order, PCS.start = true, kind or "staff", {}, {}, {}, false
    PCS.anywhere = false   -- /sbopc sets it: no closing away from a desk
    HGfx.scroll = HGfx.scroll or {}
    showCursor(true)
    -- the PC starts on the empty desktop: no application is open (2026-11-06)
end

function PCS.hide()
    if not PCS.open then return end
    PCS.open, PCS.start = false, false
    if PCS.windows.docs and docsRunning() then exports.med_docs:closeDocuments() end
    PCS.windows, PCS.z, PCS.order = {}, {}, {}
    if EXAM and EXAM.open and EXAM.source == "pc" then EXAM.open = false end
    if HIS.open and HIS.mode == "pc" then HIS.open, HIS.menu = false, false end
    HGfx.setSkin("modern")
    if not (EXAM and EXAM.open) and not HIS.open then showCursor(false) end
end

---------------------------------------------------------------- drawing helpers (Win7 dark)

local function frame()
    local w, h = HGfx.screenW * 0.8, HGfx.screenH * 0.8
    return (HGfx.screenW - w) / 2, (HGfx.screenH - h) / 2, w, h
end

local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end

-- vertical gradient as strips (the look needs only a few)
local function vgrad(x, y, w, h, top, bottom, steps, alpha)
    steps = steps or 8
    local sh = h / steps
    for i = 0, steps - 1 do
        local c = mix(top, bottom, i / math.max(1, steps - 1))
        dxDrawRectangle(x, y + i * sh, w, sh + 1, tocolor(c[1], c[2], c[3], alpha or 255))
    end
end

local function hovered(x, y, w, h) return HGfx.hover(x, y, w, h) end

-- the small window / taskbar icons
local function icon(kind, x, y, size)
    local c = WIN[kind] and WIN[kind].color or { 120, 140, 160 }
    HGfx.round(x, y, size, size, s(2), HGfx.rgb(HGfx.darken(c, 40)))
    vgrad(x + 1, y + 1, size - 2, size - 2, HGfx.lighten(c, 30), c, 4)
    local ink = kind == "docs" and tocolor(90, 100, 112) or tocolor(255, 255, 255)
    if WIN[kind] and WIN[kind].icon == "cross" then
        HGfx.cross(x + size * 0.25, y + size * 0.25, size * 0.5, ink)
    elseif WIN[kind] and WIN[kind].icon == "paper" then
        for i = 0, 3 do dxDrawRectangle(x + size * 0.22, y + size * (0.24 + i * 0.15), size * (i == 3 and 0.36 or 0.56), math.max(1, size * 0.06), ink) end
    else
        dxDrawRectangle(x + size * 0.2, y + size * 0.28, size * 0.6, size * 0.44, tocolor(255, 255, 255, 230))
        dxDrawRectangle(x + size * 0.28, y + size * 0.38, size * 0.18, size * 0.18, HGfx.rgb(c))
        dxDrawRectangle(x + size * 0.52, y + size * 0.40, size * 0.2, math.max(1, size * 0.05), tocolor(90, 100, 112))
        dxDrawRectangle(x + size * 0.52, y + size * 0.50, size * 0.14, math.max(1, size * 0.05), tocolor(90, 100, 112))
    end
end

-- caption button: the close one is red and wider
local function caption(x, y, w, h, label, red, fn)
    local hov = hovered(x, y, w, h)
    local top, bottom = { 89, 99, 110 }, { 35, 41, 48 }
    if red then top, bottom = { 227, 120, 109 }, { 158, 44, 34 } end
    if hov then top, bottom = HGfx.lighten(top, 25), HGfx.lighten(bottom, 25) end
    dxDrawRectangle(x, y, w, h, tocolor(11, 15, 20))
    vgrad(x + 1, y, w - 2, h - 1, top, bottom, 4)
    dxDrawRectangle(x + 1, y, w - 2, 1, tocolor(255, 255, 255, 50))
    HGfx.text(label, x, y, w, h, tocolor(240, 244, 248), HGfx.font(red and 10 or 9, true), "center")
    if fn then HGfx.hit(x, y, w, h, fn) end
end

---------------------------------------------------------------- monitor: desktop, windows, taskbar

local TASK_H = 40
local TITLE_H = 30
local BORDER = 4

-- interactive = false while a window covers the desktop (the icons must not react under it)
local function drawDesktop(x, y, w, h, interactive)
    vgrad(x, y, w, h, { 12, 21, 31 }, { 22, 46, 70 }, 14)
    dxDrawCircle(x + w * 0.72, y + h * 0.38, h * 0.55, 0, 360, tocolor(40, 80, 120, 40), tocolor(40, 80, 120, 0), 48)
    -- watermark
    HGfx.text(t("wallpaper_title"), x, y + s(36), w - s(50), s(64), tocolor(255, 255, 255, 26), HGfx.font(40, true), "right")
    HGfx.text(t("wallpaper_sub"), x, y + s(98), w - s(52), s(24), tocolor(255, 255, 255, 26), HGfx.font(12, true), "right")
    -- icons (staff: SBO + Dokumentumtár, EMS: Dokumentumtár)
    local ids = PCS.kind == "staff" and { "his", "docs" } or { "docs" }
    local iy = y + s(16)
    for _, id in ipairs(ids) do
        local ix, iw = x + s(14), s(86)
        local hov = interactive and hovered(ix, iy, iw, s(78))
        if hov then
            dxDrawRectangle(ix, iy, iw, s(78), tocolor(120, 170, 230, 70))
            dxDrawRectangle(ix + 1, iy + 1, iw - 2, s(78) - 2, tocolor(60, 100, 150, 70))
        end
        icon(id, ix + (iw - s(42)) / 2, iy + s(6), s(42))
        HGfx.text(t("icon_" .. id), ix - s(4), iy + s(50), iw + s(8), s(28), tocolor(0, 0, 0, 200), HGfx.font(8, true), "center", "top", true)
        HGfx.text(t("icon_" .. id), ix - s(5), iy + s(49), iw + s(8), s(28), tocolor(255, 255, 255), HGfx.font(8, true), "center", "top", true)
        if interactive then HGfx.hit(ix, iy, iw, s(78), function() PCS.openWindow(id) end) end
        iy = iy + s(92)
    end
end

-- a maximized window: glass title bar, caption buttons, frame; returns the content rectangle
local function drawWindow(id, x, y, w, h)
    local th, b = s(TITLE_H), s(BORDER)
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0))
    vgrad(x + 1, y + 1, w - 2, th, { 54, 70, 88 }, { 24, 33, 44 }, 6)
    dxDrawRectangle(x + 1, y + 1, w - 2, th * 0.45, tocolor(255, 255, 255, 18))
    dxDrawRectangle(x + 1, y + th + 1, w - 2, h - th - 2, tocolor(27, 37, 48))
    icon(id, x + s(9), y + (th - s(16)) / 2 + 1, s(16))
    local title = HGfx.fit(winTitle(id), w - s(190), HGfx.font(10))
    HGfx.text(title, x + s(33), y + 2, w, th, tocolor(0, 0, 0, 220), HGfx.font(10))
    HGfx.text(title, x + s(32), y + 1, w, th, tocolor(240, 244, 248), HGfx.font(10))
    -- caption buttons (top right, hanging from the top edge)
    local cy, chh = y + 1, s(20)
    caption(x + w - s(48) - 1, cy, s(46), chh, "X", true, function()
        if id == "case" then EXAM.close() elseif id == "his" and PCS.kind == "staff" then PCS.hide() else PCS.closeWindow(id) end
    end)
    caption(x + w - s(48) - s(27) - 1, cy, s(27), chh, "□", false, nil)
    caption(x + w - s(48) - s(54) - 1, cy, s(27), chh, "–", false, function() PCS.minimize(id) end)
    local cx, cyy, cw, ch = x + b, y + th + 1, w - 2 * b, h - th - b - 1
    dxDrawRectangle(cx - 1, cyy - 1, cw + 2, ch + 2, tocolor(0, 0, 0))
    dxDrawRectangle(cx, cyy, cw, ch, T.bg)
    return cx, cyy, cw, ch
end

local function drawTaskbar(x, y, w, h)
    vgrad(x, y, w, h, { 58, 70, 84 }, { 6, 9, 12 }, 6, 245)
    dxDrawRectangle(x, y, w, 1, tocolor(255, 255, 255, 46))
    -- Start orb with the hospital cross
    local r = h * 0.42
    local ox, oy = x + s(8) + r, y + h / 2
    local hov = hovered(ox - r, oy - r, r * 2, r * 2) or PCS.start
    dxDrawCircle(ox, oy, r + 2, 0, 360, tocolor(6, 36, 65), tocolor(6, 36, 65), 32)
    dxDrawCircle(ox, oy, r, 0, 360, hov and tocolor(70, 160, 230) or tocolor(43, 139, 208), tocolor(12, 61, 110), 32)
    dxDrawCircle(ox, oy - r * 0.35, r * 0.55, 0, 360, tocolor(200, 235, 255, hov and 120 or 90), tocolor(200, 235, 255, 0), 24)
    HGfx.cross(ox - r * 0.42, oy - r * 0.42, r * 0.84, tocolor(255, 255, 255))
    HGfx.hit(ox - r, oy - r, r * 2, r * 2, function() PCS.start = not PCS.start end)
    -- one button per open window
    local bx = ox + r + s(12)
    local active = topWindow()
    for _, id in ipairs(PCS.order) do
        local bw, bh = s(190), h - s(8)
        local by = y + s(4)
        local on = id == active
        local bhov = hovered(bx, by, bw, bh)
        dxDrawRectangle(bx, by, bw, bh, on and tocolor(150, 200, 250, 120) or tocolor(255, 255, 255, bhov and 70 or 36))
        if on then vgrad(bx + 1, by + 1, bw - 2, bh - 2, { 70, 110, 150 }, { 40, 72, 106 }, 4, 230)
        else vgrad(bx + 1, by + 1, bw - 2, bh - 2, { 52, 60, 70 }, { 22, 27, 33 }, 4, bhov and 235 or 200) end
        icon(id, bx + s(8), by + (bh - s(16)) / 2, s(16))
        HGfx.text(HGfx.fit(winShort(id), bw - s(40), HGfx.font(9)), bx + s(30), by, bw - s(36), bh, tocolor(236, 241, 246), HGfx.font(9))
        HGfx.hit(bx, by, bw, bh, function()
            if id == topWindow() then PCS.minimize(id) else PCS.openWindow(id) end
        end)
        bx = bx + bw + s(4)
    end
    -- tray: online dot, language, clock
    local tm = getRealTime()
    local tx = x + w - s(10)
    local clock = ("%02d:%02d"):format(tm.hour, tm.minute)
    local date = ("%04d.%02d.%02d."):format(tm.year + 1900, tm.month + 1, tm.monthday)
    HGfx.text(clock, tx - s(90), y + s(3), s(90), h / 2, tocolor(236, 241, 246), HGfx.font(9), "center")
    HGfx.text(date, tx - s(90), y + h / 2 - s(2), s(90), h / 2, tocolor(236, 241, 246), HGfx.font(8), "center")
    HGfx.text((L.lang and L.lang() or "hu"):upper(), tx - s(130), y, s(36), h, tocolor(236, 241, 246), HGfx.font(8, true), "center")
    dxDrawCircle(tx - s(146), y + h / 2, s(4), 0, 360, tocolor(70, 211, 122), tocolor(70, 211, 122), 12)
end

-- the Start menu (overlay pass: above the embedded documents)
local function drawStart(x, y, h)
    local items = {}
    if PCS.kind == "staff" then items[#items + 1] = { "his", function() PCS.openWindow("his") end } end
    items[#items + 1] = { "docs", function() PCS.openWindow("docs") end }
    items[#items + 1] = false
    items[#items + 1] = { "logout", function() PCS.hide() end }
    local mw, rowH = s(280), s(36)
    local mh = s(54) + #items * rowH
    local mx, my = x + s(4), y + h - s(TASK_H) - mh
    HGfx.hit(0, 0, HGfx.screenW, HGfx.screenH, function() PCS.start = false end)
    dxDrawRectangle(mx, my, mw, mh, tocolor(0, 0, 0, 240))
    vgrad(mx + 1, my + 1, mw - 2, mh - 2, { 40, 54, 70 }, { 18, 24, 32 }, 8, 248)
    -- user strip
    local name = (getElementData(localPlayer, "displayName") or getPlayerName(localPlayer)):gsub("#%x%x%x%x%x%x", "")
    dxDrawRectangle(mx + s(8), my + s(8), s(36), s(36), tocolor(91, 143, 196))
    HGfx.cross(mx + s(16), my + s(16), s(20), tocolor(255, 255, 255))
    HGfx.text(name, mx + s(52), my + s(8), mw - s(60), s(36), tocolor(240, 244, 248), HGfx.font(10, true))
    local iy = my + s(52)
    for _, it in ipairs(items) do
        if not it then
            dxDrawRectangle(mx + s(10), iy + s(4), mw - s(20), 1, tocolor(255, 255, 255, 30))
            iy = iy + s(10)
        else
            local hov = hovered(mx + s(6), iy, mw - s(12), rowH - s(2))
            if hov then
                dxDrawRectangle(mx + s(6), iy, mw - s(12), rowH - s(2), tocolor(110, 160, 220, 140))
                dxDrawRectangle(mx + s(7), iy + 1, mw - s(14), rowH - s(4), tocolor(52, 92, 136, 220))
            end
            if it[1] ~= "logout" then icon(it[1], mx + s(14), iy + (rowH - s(2) - s(22)) / 2, s(22)) end
            HGfx.text(t("start_" .. it[1]), mx + s(46), iy, mw - s(56), rowH - s(2), tocolor(240, 244, 248), HGfx.font(10))
            HGfx.hit(mx + s(6), iy, mw - s(12), rowH - s(2), function() PCS.start = false it[2]() end)
            iy = iy + rowH
        end
    end
end

---------------------------------------------------------------- render + input

local docsRect = nil   -- the documents content rectangle of this frame (wheel goes to med_docs there)

addEventHandler("onClientRender", root, function()
    if not PCS.open then return end
    -- the case window lost its panel (closed elsewhere) / the panel closed: tidy up
    if PCS.windows.case and not (EXAM and EXAM.open) then PCS.closeWindow("case", true) end
    HGfx.hits, HGfx.scrollAreas = {}, {}
    HGfx.setSkin("w7")
    local x, y, w, h = frame()
    -- the monitor bezel
    local bz = s(12)
    HGfx.round(x - bz, y - bz, w + 2 * bz, h + 2 * bz + s(10), s(8), tocolor(14, 15, 17))
    dxDrawRectangle(x - 1, y - 1, w + 2, h + 2, tocolor(0, 0, 0))
    HGfx.text(t("monitor_brand"), x, y + h + s(1), w, bz + s(8), tocolor(120, 126, 134), HGfx.font(7, true), "center")
    dxDrawCircle(x + w - s(14), y + h + bz / 2 + s(4), s(3), 0, 360, tocolor(70, 200, 110), tocolor(70, 200, 110), 10)
    local th = s(TASK_H)
    local active = topWindow()
    drawDesktop(x, y, w, h - th, active == nil)
    docsRect = nil
    if active then
        local cx, cy, cw, ch = drawWindow(active, x, y, w, h - th)
        if active == "his" then HIS.drawPC(cx, cy, cw, ch)
        elseif active == "case" then EXAM.draw(cx, cy, cw, ch)
        elseif active == "docs" then
            if not docsRunning() then
                HGfx.text(t("docs_unavailable"), cx, cy, cw, ch, T.faint, HGfx.font(11), "center")
            elseif not PCS.start then
                docsRect = { cx, cy, cw, ch }
            end
        end
    end
    if PCS.windows.docs and docsRunning() then
        if not exports.med_docs:isDocumentViewerOpen() then
            exports.med_docs:openDocuments(PCS.windows.docs.filter or {}, { embed = true })
        end
        if docsRect then exports.med_docs:setDocumentsRect(docsRect[1], docsRect[2], docsRect[3], docsRect[4])
        else exports.med_docs:setDocumentsRect() end
    end
    drawTaskbar(x, y + h - th, w, th)
end)

-- overlays above the embedded documents (med_docs draws at "low-5"): Start menu, tooltips
addEventHandler("onClientRender", root, function()
    if not PCS.open then return end
    local x, y, w, h = frame()
    if PCS.start then
        HIS.tip = nil
        drawStart(x, y, h)
    end
    HIS.drawTip()
end, true, "low-10")

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not PCS.open or button ~= "left" or state ~= "down" then return end
    HGfx.click(ax, ay)
end)

local function escape()
    if PCS.start then PCS.start = false return end
    local active = topWindow()
    if active == "case" then EXAM.escape()
    elseif active == "his" then if not HIS.escapePC() then PCS.hide() end
    elseif active == "docs" then
        if PCS.kind == "ems" then PCS.hide() else PCS.closeWindow("docs") end
    else PCS.hide() end
end

addEventHandler("onClientKey", root, function(key, press)
    if not PCS.open or not press then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local cx, cy = HGfx.cursor()
        if docsRect and HGfx.inside(cx, cy, docsRect[1], docsRect[2], docsRect[3], docsRect[4]) then return end   -- med_docs scrolls
        HGfx.wheel(key == "mouse_wheel_up" and -1 or 1)
    elseif key == "escape" then
        cancelEvent()
        if getElementData(localPlayer, "textInputOpen") then return end
        escape()
    elseif key == "backspace" and topWindow() == "his" and not getElementData(localPlayer, "textInputOpen") then
        HIS.escapePC()
    end
end)

-- walking away from the desk closes the PC
setTimer(function()
    if not PCS.open then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, pc in ipairs(HIS.pcs or {}) do
        if getDistanceBetweenPoints3D(px, py, pz, pc.x, pc.y, pc.z) <= PC_LEAVE then return end
    end
    if #(HIS.pcs or {}) > 0 and not PCS.anywhere then PCS.hide() end
end, 1000, 0)
