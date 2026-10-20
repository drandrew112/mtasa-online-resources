-- /gangwareditor client: ui_inac temp menus (one menu per page), positions from your own ped, preview peds,
-- 3D circles and patrol lines, the zone on the radar. The server re-checks everything on save (server/sanitize.lua).
-- Preview peds carry a local ui_interactobject menu (drag, duplicate, skin, delete).
-- The server moves you into a private editor dimension; preview peds go there, the docs keep the world dimension
-- you opened the editor in.

local uicore = exports.ui_core
local inac = exports.ui_inac
local iobj = exports.ui_interactobject

Editor = {
    active = false,
    list = {},          -- gang wars from the server (with state / cooldown)
    doc = nil,          -- working copy being edited
    dirty = false,
    sel = nil,          -- selected attacker index
    page = nil,         -- current menu page
    menuId = nil,
    recording = false,  -- patrol recording of attacker `sel`
    drag = nil,         -- { index, ped, x, y, z, rot, copy } while an attacker follows your aim
    dimension = 0,      -- your private editor dimension (preview peds)
    worldDimension = 0, -- where you opened the editor: new / re-centered gang wars get this one
}

local E = Editor
local LIM = GW.LIMITS
local DAY_KEYS = { "mon", "tue", "wed", "thu", "fri", "sat", "sun" }

local function notify(key, params)
    uicore:addNotification(L("v_gangwar.editor.title"), L(key, params))
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepcopy(v) end
    return out
end

local function myPos()
    local x, y, z = getElementPosition(localPlayer)
    local _, _, rot = getElementRotation(localPlayer)
    return x, y, z, rot
end

local function weaponName(id)
    if not id or id == 0 then return L("v_gangwar.editor.unarmed") end
    return getWeaponNameFromID(id) or tostring(id)
end

local function fmtCooldown(s)
    s = math.floor(s or 0)
    return ("%dd %02dh %02dm"):format(math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60))
end

--------------------------------------------------------------------------------
-- preview: ghost peds, radar circle
--------------------------------------------------------------------------------

local previews = {}     -- index -> ped
local previewIndex = {} -- ped -> index
local previewMenus = {} -- index -> ui_interactobject menu id
local radarCircle = nil

local function iobjRunning()
    local res = getResourceFromName("ui_interactobject")
    return res and getResourceState(res) == "running"
end

local function skinItems()
    local items = {
        { label = L("v_gangwar.editor.io_skin_prev"), value = { "skinstep", -1 }, closeOnSelect = false },
        { label = L("v_gangwar.editor.io_skin_next"), value = { "skinstep", 1 }, closeOnSelect = false },
    }
    for _, preset in ipairs(GW.SKIN_PRESETS) do
        local sub = {}
        for _, id in ipairs(preset[2]) do
            sub[#sub + 1] = { label = L("v_gangwar.editor.io_skin_id", { id = id }), value = { "skin", id }, closeOnSelect = false }
        end
        local name = L("v_gangwar.editor.skin_" .. preset[1])
        items[#items + 1] = { label = name, title = L.upper(name), items = sub }
    end
    items[#items + 1] = { label = L("v_gangwar.editor.io_skin_custom"), value = { "skincustom" } }
    return items
end

local function attackerMenuTitle(i)
    local a = E.doc.attackers[i]
    return L("v_gangwar.editor.io_title", { i = i, skin = a.skin, weapon = weaponName(a.weapon) })
end

local function addPreviewMenu(i, ped)
    if not iobjRunning() then return end
    previewMenus[i] = iobj:addInteractMenu(ped, {
        title = attackerMenuTitle(i),
        range = GW.ATTACKER_MENU_RANGE,
        lineOfSight = false,
        priority = 50,
        items = {
            { label = L("v_gangwar.editor.io_drag"), value = { "drag" }, desc = L("v_gangwar.editor.io_drag_desc") },
            { label = L("v_gangwar.editor.io_duplicate"), value = { "dup" }, desc = L("v_gangwar.editor.io_duplicate_desc") },
            { label = L("v_gangwar.editor.io_skin"), title = L("v_gangwar.editor.io_skin_title"), items = skinItems() },
            { label = L("v_gangwar.editor.io_edit"), value = { "edit" } },
            { label = L("v_gangwar.editor.delete"), title = L.upper(L("v_gangwar.editor.delete")), items = {
                { label = L("v_gangwar.editor.a_delete_confirm", { i = i }), value = { "delete" } },
            } },
        },
    })
end

-- skin / weapon change of one attacker without rebuilding (keeps its interact menu open)
local function refreshPreview(i)
    local ped, a = previews[i], E.doc and E.doc.attackers[i]
    if not isElement(ped) or not a then return end
    setElementModel(ped, a.skin)
    if previewMenus[i] and iobjRunning() then iobj:updateInteractMenu(previewMenus[i], { title = attackerMenuTitle(i) }) end
end

local function clearPreviews()
    for _, ped in pairs(previews) do
        if isElement(ped) then destroyElement(ped) end -- its interact menu goes with it
    end
    previews, previewIndex, previewMenus = {}, {}, {}
end

local function rebuildPreviews()
    clearPreviews()
    if not E.doc then return end
    for i, a in ipairs(E.doc.attackers) do
        local ped = createPed(a.skin, a.x, a.y, a.z, a.rot)
        if ped then
            setElementDimension(ped, E.dimension)
            setElementInterior(ped, E.doc.interior or 0)
            setElementFrozen(ped, true)
            setElementCollisionsEnabled(ped, false)
            setElementAlpha(ped, 170)
            if a.weapon and a.weapon > 0 then givePedWeapon(ped, a.weapon, 1, true) end
            previews[i], previewIndex[ped] = ped, i
            addPreviewMenu(i, ped)
        end
    end
end

local function radarRunning()
    local res = getResourceFromName("v_radar")
    return res and getResourceState(res) == "running"
end

local function updateRadar()
    if not radarRunning() then return end
    if not E.doc then
        if radarCircle then exports.v_radar:removeCircleArea(radarCircle) end
        radarCircle = nil
        return
    end
    local c = GW.CIRCLE_COLOR
    if radarCircle and exports.v_radar:updateCircleArea(radarCircle, E.doc.x, E.doc.y, E.doc.zone_radius, c[1], c[2], c[3], c[4], false) then
        return
    end
    radarCircle = exports.v_radar:addCircleArea(E.doc.x, E.doc.y, E.doc.zone_radius, c[1], c[2], c[3], c[4], false)
end

-- something in the doc changed
local function changed(rebuild)
    E.dirty = true
    if rebuild ~= false then rebuildPreviews() end
    updateRadar()
end

--------------------------------------------------------------------------------
-- menus
--------------------------------------------------------------------------------

local Pages = {}

local function leaf(label, value, desc, extra)
    local item = { label = label, value = value, desc = desc, closeOnSelect = false }
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

local function sub(label, items, desc)
    return { label = label, items = items, desc = desc, title = L.upper(label) }
end

local function open(page, title, items)
    -- the page is kept even if the menu cannot open (e.g. another ui_inac menu is up), so the menu key
    -- comes back to it instead of the gang war list
    E.page = page
    if iobjRunning() and iobj:isInteractMenuOpen() then iobj:closeInteractMenu() end
    E.menuId = inac:createTempMenu({ title = title, items = items }) or nil
end

local function closeMenu()
    if E.menuId then
        local id = E.menuId
        E.menuId = nil
        if inac:isTempMenuOpen() then inac:closeTempMenu() end
        return id
    end
end

function Pages.root()
    local items = { leaf(L("v_gangwar.editor.new_here"), { "new" }, L("v_gangwar.editor.new_here_desc")) }
    for _, gw in ipairs(E.list) do
        local status
        if gw.state ~= "idle" then
            status = L("v_gangwar.editor.status_run", { state = gw.state, player = tostring(gw.starter or "-") })
        elseif gw.cooldown > 0 then
            status = L("v_gangwar.editor.status_cooldown", { time = fmtCooldown(gw.cooldown) })
        else
            status = gw.enabled and L("v_gangwar.editor.status_ready") or L("v_gangwar.editor.status_disabled")
        end
        local actions = {
            leaf(L("v_gangwar.editor.edit"), { "edit", gw.id }),
            leaf(L("v_gangwar.editor.teleport"), { "tp", gw.x, gw.y, gw.z }),
            leaf(L("v_gangwar.editor.test_run"), { "test", gw.id }, L("v_gangwar.editor.test_run_desc")),
        }
        if gw.state ~= "idle" then actions[#actions + 1] = leaf(L("v_gangwar.editor.abort_run"), { "abort", gw.id }) end
        if gw.cooldown > 0 then actions[#actions + 1] = leaf(L("v_gangwar.editor.reset_cooldown"), { "resetcd", gw.id }) end
        actions[#actions + 1] = sub(L("v_gangwar.editor.delete"), {
            leaf(L("v_gangwar.editor.delete_confirm", { name = gw.name }), { "delete", gw.id }),
        })
        items[#items + 1] = sub(("#%d %s"):format(gw.id, gw.name), actions,
            L("v_gangwar.editor.list_line", { status = status, attackers = #gw.attackers }))
    end
    items[#items + 1] = leaf(L("v_gangwar.editor.close_editor"), { "exit" })
    open("root", L("v_gangwar.editor.title"), items)
end

local function daysText(days)
    local names = {}
    for d = 1, 7 do
        if days:find(tostring(d), 1, true) then names[#names + 1] = L("v_gangwar.editor.day_short_" .. DAY_KEYS[d]) end
    end
    return #names == 7 and L("v_gangwar.editor.every_day") or table.concat(names, ", ")
end

function Pages.doc()
    local d = E.doc
    local items = {
        leaf(L("v_gangwar.editor.name", { v = d.name }), { "text", "name" }),
        leaf(L("v_gangwar.editor.gang", { v = d.gang }), { "text", "gang" }, L("v_gangwar.editor.gang_desc")),
        leaf(L("v_gangwar.editor.enabled"), { "toggle_enabled" }, nil, { checked = d.enabled }),
        leaf(L("v_gangwar.editor.center_here"), { "center" }, L("v_gangwar.editor.center_here_desc")),
        leaf(L("v_gangwar.editor.trigger_radius", { v = d.trigger_radius }), { "text", "trigger_radius" }, L("v_gangwar.editor.trigger_radius_desc")),
        leaf(L("v_gangwar.editor.zone_radius", { v = d.zone_radius }), { "text", "zone_radius" }, L("v_gangwar.editor.zone_radius_desc")),
        leaf(L("v_gangwar.editor.release_radius", { v = d.release_radius }), { "text", "release_radius" }, L("v_gangwar.editor.release_radius_desc")),
        leaf(L("v_gangwar.editor.reward_money", { v = L.money(d.reward_money) }), { "text", "reward_money" }, L("v_gangwar.editor.reward_desc")),
        leaf(L("v_gangwar.editor.reward_xp", { v = d.reward_xp }), { "text", "reward_xp" }, L("v_gangwar.editor.reward_desc")),
        leaf(L("v_gangwar.editor.days", { v = daysText(d.days) }), { "page", "days" }),
        leaf(L("v_gangwar.editor.hour_from", { v = d.hour_from }), { "text", "hour_from" }, L("v_gangwar.editor.hours_desc")),
        leaf(L("v_gangwar.editor.hour_to", { v = d.hour_to }), { "text", "hour_to" }, L("v_gangwar.editor.hours_desc")),
        leaf(L("v_gangwar.editor.attackers", { n = #d.attackers }), { "page", "attackers" }),
        leaf(E.dirty and L("v_gangwar.editor.save_dirty") or L("v_gangwar.editor.save"), { "save" }),
    }
    if E.dirty then
        items[#items + 1] = sub(L("v_gangwar.editor.back_to_list"), {
            leaf(L("v_gangwar.editor.discard_confirm"), { "discard" }),
        }, L("v_gangwar.editor.unsaved_desc"))
    else
        items[#items + 1] = leaf(L("v_gangwar.editor.back_to_list"), { "discard" })
    end
    local title = d.id and ("#%d %s"):format(d.id, d.name) or L("v_gangwar.editor.new_title", { name = d.name })
    open("doc", L.upper(title), items)
end

function Pages.days()
    local items = {}
    for day = 1, 7 do
        items[#items + 1] = leaf(L("v_gangwar.editor.day_" .. DAY_KEYS[day]), { "day", day }, nil,
            { checked = E.doc.days:find(tostring(day), 1, true) ~= nil })
    end
    items[#items + 1] = leaf(L("v_gangwar.editor.back"), { "page", "doc" })
    open("days", L("v_gangwar.editor.days_title"), items)
end

function Pages.attackers()
    local items = { leaf(L("v_gangwar.editor.add_attacker"), { "add" }, L("v_gangwar.editor.add_attacker_desc")) }
    for i, a in ipairs(E.doc.attackers) do
        local task = a.task == "patrol" and L("v_gangwar.editor.task_patrol_n", { n = #a.patrol }) or L("v_gangwar.editor.task_guard")
        items[#items + 1] = leaf(L("v_gangwar.editor.attacker_line", { i = i, skin = a.skin, weapon = weaponName(a.weapon), task = task }),
            { "select", i })
    end
    items[#items + 1] = leaf(L("v_gangwar.editor.back"), { "page", "doc" })
    open("attackers", L("v_gangwar.editor.attackers_title", { n = #E.doc.attackers, max = LIM.attackers }), items)
end

function Pages.attacker()
    local a = E.doc.attackers[E.sel]
    if not a then return Pages.attackers() end
    local items = {
        leaf(L("v_gangwar.editor.a_skin", { v = a.skin }), { "atext", "skin" }),
        leaf(L("v_gangwar.editor.a_weapon", { v = weaponName(a.weapon), id = a.weapon }), { "atext", "weapon" }, L("v_gangwar.editor.a_weapon_desc")),
        leaf(L("v_gangwar.editor.a_ammo", { v = a.ammo }), { "atext", "ammo" }),
        leaf(L("v_gangwar.editor.a_health", { v = a.health }), { "atext", "health" }),
        leaf(L("v_gangwar.editor.a_armor", { v = a.armor }), { "atext", "armor" }),
        leaf(L("v_gangwar.editor.a_accuracy", { v = math.floor(a.accuracy * 100 + 0.5) }), { "atext", "accuracy" }, L("v_gangwar.editor.a_accuracy_desc")),
        leaf(L("v_gangwar.editor.a_aggro", { v = a.aggro }), { "atext", "aggro" }, L("v_gangwar.editor.a_aggro_desc")),
        leaf(L("v_gangwar.editor.a_task_guard"), { "task", "guard" }, L("v_gangwar.editor.a_task_guard_desc"), { checked = a.task == "guard" }),
        leaf(L("v_gangwar.editor.a_task_patrol"), { "task", "patrol" }, L("v_gangwar.editor.a_task_patrol_desc"), { checked = a.task == "patrol" }),
        leaf(L("v_gangwar.editor.a_record", { n = #a.patrol }), { "record" },
            L("v_gangwar.editor.a_record_desc", { add = GW.KEY_POINT:upper(), undo = GW.KEY_UNDO:upper(), done = GW.KEY_DONE:upper() })),
        leaf(L("v_gangwar.editor.a_clear_route"), { "clearroute" }),
        leaf(L("v_gangwar.editor.a_wait", { min = a.wait[1] / 1000, max = a.wait[2] / 1000 }), { "atext", "wait" }, L("v_gangwar.editor.a_wait_desc")),
        leaf(L("v_gangwar.editor.a_speed", { v = L("v_gangwar.editor.speed_" .. a.speed) }), { "speed" }),
        leaf(L("v_gangwar.editor.a_move_here"), { "movehere" }),
        leaf(L("v_gangwar.editor.teleport"), { "tp", a.x, a.y, a.z }),
        leaf(L("v_gangwar.editor.a_duplicate"), { "duplicate" }),
        sub(L("v_gangwar.editor.delete"), { leaf(L("v_gangwar.editor.a_delete_confirm", { i = E.sel }), { "adelete" }) }),
        leaf(L("v_gangwar.editor.back"), { "page", "attackers" }),
    }
    open("attacker", L("v_gangwar.editor.attacker_title", { i = E.sel }), items)
end

local function reopen()
    if E.doc then
        local fn = E.page ~= "root" and Pages[E.page]
        return (fn or Pages.doc)()
    end
    Pages.root()
end

--------------------------------------------------------------------------------
-- text input
--------------------------------------------------------------------------------

local textToken, textField, textTarget

local function askText(target, field, title, max, default)
    closeMenu()
    textTarget, textField = target, field
    textToken = uicore:openTextInput(title, max, tostring(default or ""))
    if not textToken then reopen() end
end

local DOC_NUMBERS = {
    trigger_radius = LIM.radius, zone_radius = LIM.radius, release_radius = LIM.radius,
    reward_money = LIM.money, reward_xp = LIM.xp, hour_from = { 0, 24 }, hour_to = { 0, 24 },
}
local ATTACKER_NUMBERS = {
    skin = { 0, 312 }, ammo = LIM.ammo, health = LIM.health, armor = LIM.armor, aggro = LIM.aggro, accuracy = { 0, 100 },
}

local function applyText(text)
    local d = E.doc
    if not d then return end
    if textTarget == "doc" then
        if textField == "name" or textField == "gang" then
            if text ~= "" then d[textField] = text:sub(1, textField == "name" and LIM.name or LIM.gang) end
        elseif DOC_NUMBERS[textField] then
            local v = GW.clamp((text:gsub(",", ".")), DOC_NUMBERS[textField])
            if not v then return notify("v_gangwar.editor.bad_number") end
            if textField ~= "trigger_radius" and textField ~= "zone_radius" and textField ~= "release_radius" then v = math.floor(v + 0.5) end
            d[textField] = v
        end
        changed(false)
        return
    end
    local a = d.attackers[E.sel]
    if not a then return end
    if textField == "weapon" then
        local id = tonumber(text) or getWeaponIDFromName(text)
        if not id or (id ~= 0 and not GW.isPedWeapon(id)) then return notify("v_gangwar.editor.bad_weapon") end
        a.weapon = id
    elseif textField == "wait" then
        local w1, w2 = text:match("^%s*([%d%.]+)%s*[%-%s]%s*([%d%.]+)%s*$")
        w1, w2 = tonumber(w1), tonumber(w2 or w1)
        if not w1 then w1 = tonumber(text) w2 = w1 end
        if not w1 or not w2 then return notify("v_gangwar.editor.bad_number") end
        w1, w2 = GW.clamp(w1 * 1000, LIM.wait), GW.clamp(w2 * 1000, LIM.wait)
        a.wait = { math.min(w1, w2), math.max(w1, w2) }
    elseif ATTACKER_NUMBERS[textField] then
        local v = GW.clamp((text:gsub(",", ".")), ATTACKER_NUMBERS[textField])
        if not v then return notify("v_gangwar.editor.bad_number") end
        if textField == "accuracy" then a.accuracy = v / 100 else a[textField] = math.floor(v + 0.5) end
    end
    changed(textField == "skin" or textField == "weapon")
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= textToken then return end
    textToken = nil
    if text and E.active then applyText((text:gsub("^%s+", ""):gsub("%s+$", ""))) end
    if E.active then reopen() end
end)

--------------------------------------------------------------------------------
-- patrol recording
--------------------------------------------------------------------------------

local stopRecording

local function addPoint()
    local a = E.doc and E.doc.attackers[E.sel]
    if not a then return stopRecording() end
    if #a.patrol >= LIM.patrol then return notify("v_gangwar.editor.route_full", { max = LIM.patrol }) end
    local x, y, z = myPos()
    a.patrol[#a.patrol + 1] = { x, y, z }
    changed(false)
end

local function undoPoint()
    local a = E.doc and E.doc.attackers[E.sel]
    if a and #a.patrol > 0 then
        a.patrol[#a.patrol] = nil
        changed(false)
    end
end

function stopRecording()
    if not E.recording then return end
    E.recording = false
    unbindKey(GW.KEY_POINT, "down", addPoint)
    unbindKey(GW.KEY_UNDO, "down", undoPoint)
    unbindKey(GW.KEY_DONE, "down", stopRecording)
    if iobjRunning() then iobj:setInteractionDisabled(false) end
    local a = E.doc and E.doc.attackers[E.sel]
    if a and #a.patrol >= 2 then a.task = "patrol" end
    if E.active then Pages.attacker() end
end

local function startRecording()
    closeMenu()
    E.recording = true
    E.page = "attacker"
    if iobjRunning() then iobj:setInteractionDisabled(true) end
    bindKey(GW.KEY_POINT, "down", addPoint)
    bindKey(GW.KEY_UNDO, "down", undoPoint)
    bindKey(GW.KEY_DONE, "down", stopRecording)
    notify("v_gangwar.editor.recording", { add = GW.KEY_POINT:upper(), undo = GW.KEY_UNDO:upper(), done = GW.KEY_DONE:upper() })
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

local function newAttacker()
    local x, y, z, rot = myPos()
    local a = deepcopy(GW.ATTACKER)
    a.x, a.y, a.z, a.rot, a.patrol = x, y, z, rot, {}
    return a
end

local cancelDrag

local function setDoc(gw)
    if cancelDrag then cancelDrag() end
    E.doc = gw and deepcopy(gw) or nil
    E.dirty, E.sel = false, nil
    rebuildPreviews()
    updateRadar()
end

local actions = {}

function actions.new()
    local x, y, z = myPos()
    local d = deepcopy(GW.DEFAULTS)
    d.x, d.y, d.z = x, y, z
    d.interior, d.dimension = getElementInterior(localPlayer), E.worldDimension
    d.attackers = {}
    setDoc(d)
    E.dirty = true
    Pages.doc()
end

function actions.edit(v)
    for _, gw in ipairs(E.list) do
        if gw.id == v[2] then
            setDoc(gw)
            return Pages.doc()
        end
    end
end

function actions.tp(v)
    setElementPosition(localPlayer, v[2], v[3], v[4] + 0.5)
end

function actions.test(v)
    closeMenu()
    triggerServerEvent("gangwar:editorTest", resourceRoot, v[2])
end

function actions.abort(v) triggerServerEvent("gangwar:editorAbort", resourceRoot, v[2]) end
function actions.resetcd(v) triggerServerEvent("gangwar:editorResetCooldown", resourceRoot, v[2]) end
function actions.delete(v) triggerServerEvent("gangwar:editorDelete", resourceRoot, v[2]) end

function actions.exit()
    closeMenu()
    triggerServerEvent("gangwar:editorClose", resourceRoot)
    Editor.stop()
end

function actions.page(v) Pages[v[2]]() end

function actions.text(v)
    local f = v[2]
    askText("doc", f, L("v_gangwar.editor.input_" .. f), f == "name" and LIM.name or (f == "gang" and LIM.gang or 10), E.doc[f])
end

function actions.toggle_enabled()
    E.doc.enabled = not E.doc.enabled
    changed(false)
    Pages.doc()
end

function actions.center()
    local x, y, z = myPos()
    E.doc.x, E.doc.y, E.doc.z = x, y, z
    E.doc.interior, E.doc.dimension = getElementInterior(localPlayer), E.worldDimension
    changed()
    Pages.doc()
end

function actions.day(v)
    local d, s = tostring(v[2]), E.doc.days
    if s:find(d, 1, true) then s = s:gsub(d, "") else s = s .. d end
    local list = {}
    for c in s:gmatch("%d") do list[#list + 1] = c end
    table.sort(list)
    E.doc.days = table.concat(list)
    changed(false)
    Pages.days()
end

function actions.save()
    if E.doc.days == "" then return notify("v_gangwar.editor.err_no_days") end
    if #E.doc.attackers == 0 then notify("v_gangwar.editor.warn_no_attackers") end
    triggerServerEvent("gangwar:editorSave", resourceRoot, E.doc)
end

function actions.discard()
    setDoc(nil)
    triggerServerEvent("gangwar:editorRequestList", resourceRoot)
    Pages.root()
end

function actions.add()
    if #E.doc.attackers >= LIM.attackers then return notify("v_gangwar.editor.too_many", { max = LIM.attackers }) end
    local a = newAttacker()
    local prev = E.doc.attackers[E.sel or #E.doc.attackers]
    if prev then -- the last one's setup is the most likely next one
        a.skin, a.weapon, a.ammo, a.health, a.armor, a.accuracy, a.aggro = prev.skin, prev.weapon, prev.ammo, prev.health, prev.armor, prev.accuracy, prev.aggro
    end
    E.doc.attackers[#E.doc.attackers + 1] = a
    E.sel = #E.doc.attackers
    changed()
    Pages.attackers()
end

function actions.select(v)
    E.sel = v[2]
    Pages.attacker()
end

function actions.atext(v)
    local a = E.doc.attackers[E.sel]
    local f = v[2]
    local default = a[f]
    if f == "accuracy" then default = math.floor(a.accuracy * 100 + 0.5)
    elseif f == "wait" then default = ("%g-%g"):format(a.wait[1] / 1000, a.wait[2] / 1000) end
    askText("attacker", f, L("v_gangwar.editor.input_a_" .. f), 24, default)
end

function actions.task(v)
    local a = E.doc.attackers[E.sel]
    if v[2] == "patrol" and #a.patrol < 2 then
        notify("v_gangwar.editor.need_route")
    else
        a.task = v[2]
        changed(false)
    end
    Pages.attacker()
end

function actions.record() startRecording() end

function actions.clearroute()
    local a = E.doc.attackers[E.sel]
    a.patrol, a.task = {}, "guard"
    changed(false)
    Pages.attacker()
end

function actions.speed()
    local a = E.doc.attackers[E.sel]
    a.speed = a.speed == "walk" and "run" or (a.speed == "run" and "sprint" or "walk")
    changed(false)
    Pages.attacker()
end

function actions.movehere()
    local a = E.doc.attackers[E.sel]
    a.x, a.y, a.z, a.rot = myPos()
    changed()
    Pages.attacker()
end

function actions.duplicate()
    if #E.doc.attackers >= LIM.attackers then return notify("v_gangwar.editor.too_many", { max = LIM.attackers }) end
    local a = deepcopy(E.doc.attackers[E.sel])
    a.x, a.y, a.z, a.rot = myPos()
    a.patrol, a.task = {}, "guard"
    E.doc.attackers[#E.doc.attackers + 1] = a
    E.sel = #E.doc.attackers
    changed()
    Pages.attacker()
end

function actions.adelete()
    table.remove(E.doc.attackers, E.sel)
    E.sel = nil
    changed()
    Pages.attackers()
end

addEvent("ui_inac:tempMenuSelect")
addEventHandler("ui_inac:tempMenuSelect", root, function(rootId, value)
    if not E.active or rootId ~= E.menuId or type(value) ~= "table" then return end
    local fn = actions[value[1]]
    if fn then fn(value) end
end)

addEvent("ui_inac:tempMenuClose")
addEventHandler("ui_inac:tempMenuClose", root, function(rootId)
    if rootId == E.menuId then E.menuId = nil end
end)

--------------------------------------------------------------------------------
-- dragging an attacker: the preview ped follows your aim until you put it down
--------------------------------------------------------------------------------

local DRAG_CONTROLS = { "fire", "aim_weapon", "next_weapon", "previous_weapon" }
local dragControls = {}

local function dragTarget()
    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    local dx, dy, dz = lx - cx, ly - cy, lz - cz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then return end
    dx, dy, dz = dx / len, dy / len, dz / len
    local px, py, pz = getElementPosition(localPlayer)
    local reach = GW.DRAG_MAX_DIST + getDistanceBetweenPoints3D(cx, cy, cz, px, py, pz)
    local hit, hx, hy, hz = processLineOfSight(cx, cy, cz, cx + dx * reach, cy + dy * reach, cz + dz * reach,
        true, true, false, true, false, false, false, false, localPlayer)
    if not hit then
        hx, hy = cx + dx * reach, cy + dy * reach
        local gz = getGroundPosition(hx, hy, pz + 50)
        hz = (gz and gz ~= 0) and gz or pz - 1
    end
    -- keep it within DRAG_MAX_DIST of you (horizontally)
    local ox, oy = hx - px, hy - py
    local dist = math.sqrt(ox * ox + oy * oy)
    if dist > GW.DRAG_MAX_DIST then
        hx, hy = px + ox / dist * GW.DRAG_MAX_DIST, py + oy / dist * GW.DRAG_MAX_DIST
        local gz = getGroundPosition(hx, hy, hz + 3)
        if gz and gz ~= 0 then hz = gz end
    end
    return hx, hy, hz + 1.0 -- ped position is ~1 m above its feet, like a player's
end

local function dragFrame()
    local d = E.drag
    if not d or not isElement(d.ped) then return cancelDrag() end
    local x, y, z = dragTarget()
    if x then d.x, d.y, d.z = x, y, z end
    setElementPosition(d.ped, d.x, d.y, d.z)
    setElementRotation(d.ped, 0, 0, d.rot, "default", true)
end

local placeDrag, dragRotate

local function endDrag()
    removeEventHandler("onClientPreRender", root, dragFrame)
    unbindKey(GW.KEY_DRAG_PLACE, "down", placeDrag)
    unbindKey("mouse1", "down", placeDrag)
    unbindKey(GW.KEY_DRAG_CANCEL, "down", cancelDrag)
    unbindKey("mouse2", "down", cancelDrag)
    unbindKey("mouse_wheel_up", "down", dragRotate)
    unbindKey("mouse_wheel_down", "down", dragRotate)
    for control, was in pairs(dragControls) do toggleControl(control, was) end
    dragControls = {}
    if iobjRunning() then iobj:setInteractionDisabled(false) end
    E.drag = nil
end

function dragRotate(key)
    local d = E.drag
    if d then d.rot = (d.rot + (key == "mouse_wheel_up" and GW.DRAG_ROTATE_STEP or -GW.DRAG_ROTATE_STEP)) % 360 end
end

-- the number key that picked "Drag" / "Duplicate" must not put it down / cancel it at once
local function dragFresh(d) return getTickCount() - d.started < 250 end

function placeDrag()
    local d = E.drag
    if not d or dragFresh(d) then return end
    local a = E.doc and E.doc.attackers[d.index]
    endDrag()
    if not a then return end
    a.x, a.y, a.z, a.rot = d.x, d.y, d.z, d.rot
    E.sel = d.index
    changed(false)
    notify("v_gangwar.editor.drag_placed", { i = d.index })
end

function cancelDrag(key)
    local d = E.drag
    if not d or (key and dragFresh(d)) then return end
    endDrag()
    if not E.doc then return end
    if d.copy then -- the copy was made for this drag only
        table.remove(E.doc.attackers, d.index)
        E.sel = nil
        changed()
    else
        local a = E.doc.attackers[d.index]
        if a and isElement(d.ped) then
            setElementPosition(d.ped, a.x, a.y, a.z)
            setElementRotation(d.ped, 0, 0, a.rot, "default", true)
        end
    end
end

local function startDrag(index, copy)
    local a = E.doc and E.doc.attackers[index]
    local ped = previews[index]
    if not a or not isElement(ped) or E.drag or E.recording then return end
    closeMenu()
    if iobjRunning() then
        iobj:closeInteractMenu()
        iobj:setInteractionDisabled(true)
    end
    E.sel = index
    E.drag = { index = index, ped = ped, x = a.x, y = a.y, z = a.z, rot = a.rot or 0, copy = copy, started = getTickCount() }
    for _, control in ipairs(DRAG_CONTROLS) do
        dragControls[control] = isControlEnabled(control)
        toggleControl(control, false)
    end
    addEventHandler("onClientPreRender", root, dragFrame)
    bindKey(GW.KEY_DRAG_PLACE, "down", placeDrag)
    bindKey("mouse1", "down", placeDrag)
    bindKey(GW.KEY_DRAG_CANCEL, "down", cancelDrag)
    bindKey("mouse2", "down", cancelDrag)
    bindKey("mouse_wheel_up", "down", dragRotate)
    bindKey("mouse_wheel_down", "down", dragRotate)
end

--------------------------------------------------------------------------------
-- attacker interact menu (ui_interactobject on the preview peds)
--------------------------------------------------------------------------------

local function stepSkin(skin, dir)
    local models = getValidPedModels and getValidPedModels(false)
    if type(models) ~= "table" or #models == 0 then
        return (skin + dir) % 313
    end
    table.sort(models)
    local pos = #models
    for n, id in ipairs(models) do
        if id >= skin then pos = n break end
    end
    if models[pos] ~= skin and dir < 0 then dir = 0 end -- an unlisted skin steps to the next listed one
    return models[(pos - 1 + dir) % #models + 1]
end

local ioActions = {}

function ioActions.drag(i) startDrag(i, false) end

function ioActions.dup(i)
    if #E.doc.attackers >= LIM.attackers then return notify("v_gangwar.editor.too_many", { max = LIM.attackers }) end
    local a = deepcopy(E.doc.attackers[i])
    a.patrol, a.task = {}, "guard"
    E.doc.attackers[#E.doc.attackers + 1] = a
    changed() -- the new preview ped appears on top of the original
    startDrag(#E.doc.attackers, true)
end

function ioActions.skin(i, v)
    E.doc.attackers[i].skin = v[2]
    E.sel = i
    changed(false)
    refreshPreview(i)
end

function ioActions.skinstep(i, v)
    local a = E.doc.attackers[i]
    a.skin = stepSkin(a.skin, v[2])
    E.sel = i
    changed(false)
    refreshPreview(i)
end

function ioActions.skincustom(i)
    E.sel, E.page = i, "attacker"
    askText("attacker", "skin", L("v_gangwar.editor.input_a_skin"), 24, E.doc.attackers[i].skin)
end

function ioActions.edit(i)
    E.sel = i
    Pages.attacker()
end

function ioActions.delete(i)
    table.remove(E.doc.attackers, i)
    E.sel = nil
    changed()
    if E.menuId and E.page == "attackers" then Pages.attackers() end
end

addEvent("onClientInteractMenuSelect")
addEventHandler("onClientInteractMenuSelect", root, function(menuId, value, target)
    if not E.active or not E.doc or E.drag or E.recording or type(value) ~= "table" then return end
    local i = previewIndex[target]
    if not i or previewMenus[i] ~= menuId or not E.doc.attackers[i] then return end
    local fn = ioActions[value[1]]
    if fn then fn(i, value) end
end)

-- ui_interactobject restarted: its menus are gone, register them again
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "ui_interactobject" and E.active and E.doc and not E.drag then
        setTimer(rebuildPreviews, 500, 1)
    end
end)

--------------------------------------------------------------------------------
-- 3D view: circles, attacker labels, patrol routes
--------------------------------------------------------------------------------

local function circle3D(x, y, z, r, color)
    local steps = math.max(24, math.min(96, math.floor(r / 2)))
    local px, py
    for i = 0, steps do
        local a = i / steps * math.pi * 2
        local cx, cy = x + math.cos(a) * r, y + math.sin(a) * r
        if px then dxDrawLine3D(px, py, z, cx, cy, z, color, 3) end
        px, py = cx, cy
    end
end

local function label(x, y, z, text, color)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0.05)
    if sx then dxDrawText(text, sx, sy, sx, sy, color or tocolor(255, 255, 255), 1.2, "default-bold", "center", "center") end
end

local function render()
    local px, py = getElementPosition(localPlayer)
    if not E.doc then
        for _, gw in ipairs(E.list) do
            if (gw.x - px) ^ 2 + (gw.y - py) ^ 2 < 600 ^ 2 then
                label(gw.x, gw.y, gw.z + 2, ("#%d %s"):format(gw.id, gw.name), tocolor(255, 200, 60))
            end
        end
    else
        local d = E.doc
        local z = d.z - 0.9
        circle3D(d.x, d.y, z, d.zone_radius, tocolor(230, 40, 40, 220))
        circle3D(d.x, d.y, z, d.trigger_radius, tocolor(240, 200, 40, 160))
        circle3D(d.x, d.y, z, d.release_radius, tocolor(160, 160, 160, 120))
        label(d.x, d.y, d.z + 1.5, d.name, tocolor(255, 80, 80))
        for i, a in ipairs(d.attackers) do
            local sel = i == E.sel
            local col = sel and tocolor(80, 220, 255) or tocolor(255, 255, 255)
            local ax, ay, az = a.x, a.y, a.z
            if E.drag and E.drag.index == i then
                ax, ay, az = E.drag.x, E.drag.y, E.drag.z
                circle3D(ax, ay, az - 0.95, 0.6, tocolor(80, 220, 255, 220))
            end
            label(ax, ay, az + 1.3, ("#%d %s"):format(i, weaponName(a.weapon)), col)
            local last = { a.x, a.y, a.z - 0.9 }
            for n, p in ipairs(a.patrol) do
                dxDrawLine3D(last[1], last[2], last[3], p[1], p[2], p[3] - 0.9, sel and tocolor(80, 220, 255) or tocolor(255, 255, 255, 140), sel and 4 or 2)
                if sel then label(p[1], p[2], p[3] - 0.4, tostring(n), col) end
                last = { p[1], p[2], p[3] - 0.9 }
            end
            if a.task == "patrol" and #a.patrol >= 2 then -- loop back
                local f = a.patrol[1]
                dxDrawLine3D(last[1], last[2], last[3], f[1], f[2], f[3] - 0.9, tocolor(255, 255, 255, 60), 1)
            end
        end
    end
    local sw, sh = guiGetScreenSize()
    local hint
    if E.recording then
        hint = L("v_gangwar.editor.recording_hint", { add = GW.KEY_POINT:upper(), undo = GW.KEY_UNDO:upper(), done = GW.KEY_DONE:upper() })
    elseif E.drag then
        hint = L("v_gangwar.editor.drag_hint", { place = GW.KEY_DRAG_PLACE:upper(), cancel = GW.KEY_DRAG_CANCEL:upper() })
    elseif E.doc then
        hint = L("v_gangwar.editor.hint_doc", { key = GW.KEY_MENU:upper(), open = "X" })
    else
        hint = L("v_gangwar.editor.hint", { key = GW.KEY_MENU:upper() })
    end
    dxDrawText(hint, 0, sh - 40, sw, sh - 10, tocolor(255, 255, 255, 220), 1.2, "default-bold", "center", "center")
end

--------------------------------------------------------------------------------
-- start / stop
--------------------------------------------------------------------------------

local function menuKey()
    if not E.active or E.recording or E.drag or textToken or inac:isTempMenuOpen() then return end
    reopen()
end

function Editor.stop()
    if not E.active then return end
    stopRecording()
    if cancelDrag then cancelDrag() end
    E.active = false
    closeMenu()
    unbindKey(GW.KEY_MENU, "down", menuKey)
    removeEventHandler("onClientRender", root, render)
    setDoc(nil)
    E.page = nil
    if iobjRunning() then iobj:setInteractionDisabled(false) end
    notify("v_gangwar.editor.closed")
end

addEvent("gangwar:editorStart", true)
addEventHandler("gangwar:editorStart", resourceRoot, function(list, dimension, worldDimension)
    E.list = list or {}
    E.dimension, E.worldDimension = dimension or getElementDimension(localPlayer), worldDimension or 0
    if E.active then return reopen() end
    E.active = true
    bindKey(GW.KEY_MENU, "down", menuKey)
    addEventHandler("onClientRender", root, render)
    notify("v_gangwar.editor.opened", { key = GW.KEY_MENU:upper(), dim = E.dimension })
    Pages.root()
end)

addEvent("gangwar:editorStop", true)
addEventHandler("gangwar:editorStop", resourceRoot, function() Editor.stop() end)

addEvent("gangwar:editorList", true)
addEventHandler("gangwar:editorList", resourceRoot, function(list)
    E.list = list or {}
    if E.active and E.page == "root" and E.menuId then Pages.root() end
end)

addEvent("gangwar:editorSaved", true)
addEventHandler("gangwar:editorSaved", resourceRoot, function(id, err, gw)
    if not E.active then return end
    if not id then return notify("v_gangwar.editor.save_failed", { err = tostring(err) }) end
    notify("v_gangwar.editor.saved", { id = id })
    if gw and E.doc then
        local sel = E.sel
        setDoc(gw)
        E.sel = sel
        if E.menuId and E.page then reopen() end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if cancelDrag then cancelDrag() end
    clearPreviews()
end)
