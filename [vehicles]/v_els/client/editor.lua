-- /elseditor kliens: fénypontok elhelyezése az épp vezetett jármű körül.
-- A munkapéldányt helyben szerkesztjük (Beacons előnézettel), a szerverre csak
-- mentéskor megy. Menü: ui_inac temp menu (E), szövegbevitel: ui_core.
--
-- Billentyűk (zárt menünél):
--   nyilak       pont mozgatása X (jobbra/balra) és Y (előre/hátra)
--   PgUp / PgDn  pont mozgatása Z (fel/le);  Shift = finom mozgatás
--   [ / ]        előző / következő pont
--   N / M        új pont (másolat) / tükrözött másolat
--   Delete       pont törlése
--   C / G        szín / csoport váltása
--   + / -        méret
--   P            előnézet: folyamatos / minták
--   E            menü

local KEY_MENU    = "e"
local MOVE_SPEED  = 0.6   -- m/s
local FINE_SPEED  = 0.08  -- m/s, Shift-tel
local SIZE_STEP   = 0.05
local AXIS_LENGTH = 0.35
local SIZES       = { 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.7 }
local MIRROR_GROUP = { A = "B", B = "A", C = "D", D = "C" }

-- vezetés letiltása szerkesztés közben (a nyilak egyébként kormányoznak)
local LOCKED_CONTROLS = {
    "accelerate", "brake_reverse", "vehicle_left", "vehicle_right",
    "steer_forward", "steer_back", "handbrake", "horn",
    "vehicle_look_left", "vehicle_look_right",
}

local MOVE_KEYS = {
    { "arrow_l", 1, -1 }, { "arrow_r", 1, 1 },
    { "arrow_u", 2, 1 },  { "arrow_d", 2, -1 },
    { "pgup", 3, 1 },     { "pgdn", 3, -1 },
}
local AXIS_FIELD = { "x", "y", "z" }

local sw, sh = guiGetScreenSize()
local scale = math.max(0.75, sh / 1080)

-- ed = { veh, model, layout, sel, preview (false | minta index), dirty, wasFrozen, menuId, colorToken }
local ed = nil

addEvent("els:editorToggle", true)
addEvent("els:editorSaved", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")

------------------------------------------------------------
-- SEGÉDEK
------------------------------------------------------------

local function notify(text)
    exports.ui_core:addNotification("ELS Editor", text)
end

local function copyPoint(p)
    return { x = p.x, y = p.y, z = p.z, r = p.r, g = p.g, b = p.b, group = p.group, size = p.size }
end

local function copyLayout(layout)
    local points = {}
    for i, p in ipairs(layout and layout.points or {}) do
        points[i] = copyPoint(p)
    end
    return { points = points }
end

local function selected()
    return ed.layout.points[ed.sel]
end

local function colorName(p)
    for _, c in ipairs(ELS_COLORS) do
        if c[2] == p.r and c[3] == p.g and c[4] == p.b then return c[1] end
    end
    return ("%d %d %d"):format(p.r, p.g, p.b)
end

local function previewName()
    return ed.preview and ELS_PATTERNS[ed.preview].name or "Steady"
end

local function changed()
    ed.dirty = true
    Beacons.prepare(ed.layout)
end

local function menuOpen()
    return ed.menuId ~= nil and exports.ui_inac:isTempMenuOpen()
end

local function keysUsable()
    return ed and not (isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
        or menuOpen() or ed.colorToken)
end

------------------------------------------------------------
-- MŰVELETEK
------------------------------------------------------------

local Actions = {}

function Actions.select(index)
    if ed.layout.points[index] then ed.sel = index end
end

function Actions.step(delta)
    local n = #ed.layout.points
    if n > 0 then ed.sel = (ed.sel - 1 + delta) % n + 1 end
end

function Actions.add()
    local points = ed.layout.points
    if #points >= ELS_MAX_POINTS then
        notify(("Maximum %d points per vehicle."):format(ELS_MAX_POINTS))
        return
    end
    local p = selected()
    p = p and copyPoint(p) or { x = 0, y = 0, z = 1.2, r = 30, g = 60, b = 255, group = "A", size = 0.3 }
    if selected() then p.x = p.x + 0.15 end
    points[#points + 1] = p
    ed.sel = #points
    changed()
end

function Actions.mirror()
    local p = selected()
    if not p or #ed.layout.points >= ELS_MAX_POINTS then return end
    Actions.add()
    local copy = selected()
    copy.x, copy.group = -p.x, MIRROR_GROUP[p.group] or p.group
    changed()
end

function Actions.delete()
    if not selected() then return end
    table.remove(ed.layout.points, ed.sel)
    ed.sel = math.max(1, math.min(ed.sel, #ed.layout.points))
    changed()
end

function Actions.color(index)
    local p = selected()
    if not p then return end
    if not index then -- következő szín
        index = 1
        for i, c in ipairs(ELS_COLORS) do
            if c[2] == p.r and c[3] == p.g and c[4] == p.b then index = i % #ELS_COLORS + 1 end
        end
    end
    local c = ELS_COLORS[index]
    p.r, p.g, p.b = c[2], c[3], c[4]
    changed()
end

function Actions.customColor()
    local p = selected()
    if not p then return end
    ed.colorToken = exports.ui_core:openTextInput("Light color (R G B)", 11, ("%d %d %d"):format(p.r, p.g, p.b))
end

function Actions.group(group)
    local p = selected()
    if not p then return end
    if not group then -- következő csoport
        for i, g in ipairs(ELS_GROUPS) do
            if g == p.group then group = ELS_GROUPS[i % #ELS_GROUPS + 1] end
        end
    end
    p.group = group or "A"
    changed()
end

function Actions.size(value)
    local p = selected()
    if not p then return end
    p.size = math.max(ELS_SIZE_MIN, math.min(ELS_SIZE_MAX, value))
    changed()
end

function Actions.resize(delta)
    local p = selected()
    if p then Actions.size(p.size + delta) end
end

function Actions.preview(pattern)
    if pattern == nil then -- következő: folyamatos → 1. minta → ... → folyamatos
        pattern = (ed.preview or 0) + 1
        if pattern > #ELS_PATTERNS then pattern = false end
    end
    ed.preview = pattern
    Beacons.setPreview(ed.veh, ed.layout, ed.preview)
end

function Actions.save()
    triggerServerEvent("els:editorSave", resourceRoot, ed.model, { points = ed.layout.points })
end

function Actions.exit()
    stopEditor()
end

------------------------------------------------------------
-- MENÜ
------------------------------------------------------------

local function item(label, action, arg, desc, extra)
    local it = { label = label, desc = desc, value = { a = action, v = arg } }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end

local function buildMenu()
    local p = selected()

    local pointItems = {}
    for i, pt in ipairs(ed.layout.points) do
        pointItems[i] = item(("#%d  %s  %s"):format(i, pt.group, colorName(pt)), "select", i,
            ("x %.2f  y %.2f  z %.2f  size %.2f"):format(pt.x, pt.y, pt.z, pt.size), { checked = i == ed.sel })
    end
    if #pointItems == 0 then pointItems[1] = item("No points yet", "noop") end

    local colorItems = {}
    for i, c in ipairs(ELS_COLORS) do
        colorItems[i] = item(c[1], "color", i, nil, { checked = p and colorName(p) == c[1] })
    end
    colorItems[#colorItems + 1] = item("Custom (R G B)...", "customColor")

    local groupItems = {}
    for i, g in ipairs(ELS_GROUPS) do
        groupItems[i] = item("Group " .. g, "group", g, "Patterns flash the groups separately",
            { checked = p and p.group == g })
    end

    local sizeItems = {}
    for i, s in ipairs(SIZES) do
        sizeItems[i] = item(("%.2f"):format(s), "size", s, nil, { checked = p and p.size == s })
    end

    local previewItems = { item("Steady (all on)", "preview", false, nil, { checked = not ed.preview }) }
    for i, pat in ipairs(ELS_PATTERNS) do
        previewItems[#previewItems + 1] = item(pat.name, "preview", i, nil, { checked = ed.preview == i })
    end

    local items = {
        { label = ("Points (%d)"):format(#ed.layout.points), title = "Select point", items = pointItems },
        item("Add point", "add", nil, "Copy of the selected point (N)"),
        item("Mirror point", "mirror", nil, "Mirrored copy on the other side, A<->B, C<->D (M)"),
        item("Delete point", "delete", nil, "Delete the selected point (Del)"),
    }
    if p then
        items[#items + 1] = { label = "Color: " .. colorName(p), title = "Color", items = colorItems }
        items[#items + 1] = { label = "Group: " .. p.group, title = "Group", items = groupItems }
        items[#items + 1] = { label = ("Size: %.2f"):format(p.size), title = "Size", items = sizeItems }
    end
    items[#items + 1] = { label = "Preview: " .. previewName(), title = "Preview", items = previewItems }
    items[#items + 1] = item("Save", "save", nil, #ed.layout.points == 0
        and "No points: removes the layout, the vehicle gets the GTA siren lights back"
        or "Saves to lights.json for every vehicle of this model")
    items[#items + 1] = item("Exit editor", "exit", nil, ed.dirty and "Unsaved changes will be lost!" or nil)

    return { title = "ELS Editor - " .. getVehicleNameFromModel(ed.model), items = items }
end

local function toggleMenu()
    if not ed then return end
    if menuOpen() then
        exports.ui_inac:closeTempMenu()
        return
    end
    if keysUsable() then
        ed.menuId = exports.ui_inac:createTempMenu(buildMenu()) or nil
    end
end

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if not ed or rootId ~= ed.menuId or type(value) ~= "table" then return end
    local action = Actions[value.a]
    if action then action(value.v) end
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if ed and rootId == ed.menuId then ed.menuId = nil end
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    if not ed or token ~= ed.colorToken then return end
    ed.colorToken = nil
    if not text then return end

    local r, g, b = text:match("^%s*(%d+)[%s,]+(%d+)[%s,]+(%d+)%s*$")
    local p = selected()
    if not (r and p) then
        notify("Invalid color, use: R G B (0-255)")
        return
    end
    p.r, p.g, p.b = math.min(255, tonumber(r)), math.min(255, tonumber(g)), math.min(255, tonumber(b))
    changed()
end)

------------------------------------------------------------
-- BILLENTYŰK
------------------------------------------------------------

local keyActions = {
    ["["] = function() Actions.step(-1) end,
    ["]"] = function() Actions.step(1) end,
    n = Actions.add,
    m = Actions.mirror,
    delete = Actions.delete,
    c = function() Actions.color() end,
    g = function() Actions.group() end,
    num_add = function() Actions.resize(SIZE_STEP) end,
    ["="]   = function() Actions.resize(SIZE_STEP) end,
    num_sub = function() Actions.resize(-SIZE_STEP) end,
    ["-"]   = function() Actions.resize(-SIZE_STEP) end,
    p = function() Actions.preview() end,
}

local function onKey(key)
    if keysUsable() and keyActions[key] then keyActions[key]() end
end

local function bindEditorKeys(bind)
    local fn = bind and bindKey or unbindKey
    for key in pairs(keyActions) do fn(key, "down", onKey) end
    fn(KEY_MENU, "down", toggleMenu)
end

------------------------------------------------------------
-- RAJZOLÁS ÉS MOZGATÁS
------------------------------------------------------------

local function moveSelected(timeSlice)
    local p = selected()
    if not p or not keysUsable() then return end

    local speed = (getKeyState("lshift") or getKeyState("rshift")) and FINE_SPEED or MOVE_SPEED
    local delta = speed * timeSlice / 1000
    local moved = false
    for _, k in ipairs(MOVE_KEYS) do
        if getKeyState(k[1]) then
            local field = AXIS_FIELD[k[2]]
            p[field] = p[field] + k[3] * delta
            moved = true
        end
    end
    if moved then changed() end
end

local function drawAxes(m, p)
    local x, y, z = Beacons.toWorld(m, p.x, p.y, p.z)
    local axes = {
        { AXIS_LENGTH, 0, 0, tocolor(255, 60, 60) },
        { 0, AXIS_LENGTH, 0, tocolor(60, 255, 60) },
        { 0, 0, AXIS_LENGTH, tocolor(60, 120, 255) },
    }
    for _, a in ipairs(axes) do
        local ex, ey, ez = Beacons.toWorld(m, p.x + a[1], p.y + a[2], p.z + a[3])
        dxDrawLine3D(x, y, z, ex, ey, ez, a[4], 2)
    end
end

local function onPreRender(timeSlice)
    if not isElement(ed.veh) then
        stopEditor()
        return
    end
    moveSelected(timeSlice)

    local m = getElementMatrix(ed.veh)
    local p = selected()
    if p then drawAxes(m, p) end
end

local function drawPanel()
    local p = selected()
    local lines = {
        ("#FFFFFF%s  #AAAAAA(%s)%s"):format(getVehicleNameFromModel(ed.model), "model " .. ed.model,
            ed.dirty and "  #FFC800* unsaved" or ""),
        p and ("#FFFFFFPoint %d/%d   Group %s   %s   Size %.2f"):format(ed.sel, #ed.layout.points, p.group, colorName(p), p.size)
          or "#FFFFFFNo points - press N to add one",
        p and ("#AAAAAAx %.3f   y %.3f   z %.3f"):format(p.x, p.y, p.z) or "",
        "#FFFFFFPreview: " .. previewName(),
        "#888888Arrows X/Y  PgUp/PgDn Z  Shift fine   [ ] select",
        "#888888N add  M mirror  Del delete  C color  G group  +/- size  P preview  E menu",
    }

    local w, h = 560 * scale, (#lines * 20 + 34) * scale
    local x, y = 24 * scale, sh - h - 200 * scale
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 16, 200))
    dxDrawRectangle(x, y, w, 3 * scale, tocolor(60, 120, 255, 255))
    dxDrawText("ELS Editor", x + 12 * scale, y + 8 * scale, 0, 0, tocolor(255, 255, 255), 1.3 * scale, "default-bold")
    for i, line in ipairs(lines) do
        dxDrawText(line, x + 12 * scale, y + (12 + i * 20) * scale, 0, 0, tocolor(255, 255, 255), 1.0 * scale,
            "default", "left", "top", false, false, false, true)
    end
end

local function drawLabels()
    local m = getElementMatrix(ed.veh)
    for i, p in ipairs(ed.layout.points) do
        local sx, sy = getScreenFromWorldPosition(Beacons.toWorld(m, p.x, p.y, p.z + 0.12))
        if sx then
            local color = i == ed.sel and tocolor(255, 200, 0) or tocolor(255, 255, 255, 180)
            dxDrawText(("#%d %s"):format(i, p.group), sx, sy, sx, sy, color, 1.0 * scale, "default-bold",
                "center", "bottom")
        end
    end
end

local function onRender()
    if not isElement(ed.veh) then return end
    drawLabels()
    drawPanel()
end

------------------------------------------------------------
-- INDÍTÁS / LEÁLLÍTÁS
------------------------------------------------------------

local function lockVehicle(lock)
    for _, control in ipairs(LOCKED_CONTROLS) do
        toggleControl(control, not lock)
    end
    if isElement(ed.veh) then
        setElementFrozen(ed.veh, lock or ed.wasFrozen)
    end
end

local function startEditor(veh, model, layout)
    ed = {
        veh = veh, model = model, layout = copyLayout(layout),
        sel = 1, preview = false, dirty = false,
        wasFrozen = isElementFrozen(veh),
    }
    lockVehicle(true)
    bindEditorKeys(true)
    addEventHandler("onClientPreRender", root, onPreRender)
    addEventHandler("onClientRender", root, onRender)
    Beacons.setPreview(veh, ed.layout, ed.preview)
    notify("Editor opened. Press E for the menu, /elseditor to close.")
end

function stopEditor()
    if not ed then return end
    if menuOpen() then exports.ui_inac:closeTempMenu() end
    if ed.dirty then notify("Editor closed, unsaved changes discarded.") end

    removeEventHandler("onClientPreRender", root, onPreRender)
    removeEventHandler("onClientRender", root, onRender)
    bindEditorKeys(false)
    lockVehicle(false)
    Beacons.clearPreview()
    ed = nil
end

addEventHandler("els:editorToggle", resourceRoot, function(veh, model, layout)
    if ed then
        stopEditor()
    elseif isElement(veh) and getPedOccupiedVehicle(localPlayer) == veh then
        startEditor(veh, model, layout or nil)
    end
end)

addEventHandler("els:editorSaved", resourceRoot, function(ok, message)
    if ed and ok then ed.dirty = false end
    notify(message)
end)

addEventHandler("onClientPlayerVehicleExit", localPlayer, stopEditor)
addEventHandler("onClientResourceStop", resourceRoot, stopEditor)
