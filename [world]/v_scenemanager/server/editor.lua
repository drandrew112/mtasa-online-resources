-- In-game scene editor (/sceneeditor toggles it).
--
-- Every editor works in a private dimension. The scene being edited is a set of real
-- vehicles / peds in that dimension (no medsys simulation, no AI). The R menu (ui_inac temp
-- menu, client/editor.lua) sends actions here; the elements themselves are edited
-- through ui_interactobject menus (server/interact.lua). Nothing is written to disk
-- until Save / Save as; a scene with validation errors (Storage.validate) is not saved.
-- Check issues: the scenes flagged with /flagscene or on the web (server/issues.lua).
--
-- Session: { player, slot, back = { x, y, z, rz, interior, dimension },
--            scene = nil | { file (nil until saved), data, dirty,
--                            vehicles = { [id] = element }, peds = { [id] = element } } }

Editor = {
    sessions = {},  -- [player] = session
    locks = {},     -- [scene name] = player editing it
}

local textRequests = {} -- [player] = { id, callback }
local nextRequest = 1

addEvent("vsm:editorAction", true)
addEvent("vsm:textResult", true)

local TITLE = "v_scenemanager.editor.title"

local function notify(session, key, params)
    vsmNotify(session.player, TITLE, key, params)
end
Editor.notify = notify

---------------------------------------------------------------- helpers

local function freeSlot()
    local used = {}
    for _, s in pairs(Editor.sessions) do used[s.slot] = true end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    return slot
end

function Editor.dimension(session)
    return VSM.EDITOR_DIMENSION + session.slot
end

-- Asks the player for a text (ui_core text input); callback(text) only on confirm.
-- title: v_locals key (+ params), resolved in the player's language.
function Editor.askText(player, title, maxLen, default, callback, params)
    local id = nextRequest
    nextRequest = nextRequest + 1
    textRequests[player] = { id = id, callback = callback }
    triggerClientEvent(player, "vsm:askText", resourceRoot, id, L.msg(title, params), maxLen or 64, default and tostring(default) or "")
end

addEventHandler("vsm:textResult", resourceRoot, function(id, text)
    local req = textRequests[client]
    if not req or req.id ~= id then return end
    textRequests[client] = nil
    if type(text) == "string" and Editor.sessions[client] then req.callback(text) end
end)

local function playerSpot(player)
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    return { vsmRound(x), vsmRound(y), vsmRound(z) }, vsmRound(rz, 1)
end

local function nextEntityId(list, prefix)
    local used = {}
    for _, e in ipairs(list) do used[e.id] = true end
    local n = 1
    while used[prefix .. n] do n = n + 1 end
    return prefix .. n
end

function Editor.findEntry(scene, kind, id)
    local list = kind == "vehicle" and scene.data.vehicles or scene.data.peds
    for i, entry in ipairs(list) do
        if entry.id == id then return entry, i end
    end
    return nil
end

---------------------------------------------------------------- labels

-- data of the 3D label over a scene element (client/editor.lua turns it into text in the player's language)
local function vehicleLabel(entry)
    return {
        kind = "vehicle", id = entry.id, model = entry.model, health = tonumber(entry.health) or 1000,
        engine = entry.engine or false, lightsOn = entry.lightsOn or false, sirens = entry.sirens or false,
        locked = entry.locked or false, frozen = entry.frozen or false, tow = entry.tow or false,
        stolen = entry.record and entry.record.stolen or false,
    }
end

local function pedLabel(entry)
    return {
        kind = "ped", id = entry.id, skin = entry.skin or 0, anim = entry.anim, role = entry.role,
        vehicle = entry.vehicle or false, seat = entry.seat or 0,
        injuries = entry.injuries, state = entry.state, ai = entry.ai or false,
        record = entry.record and true or false, warrant = entry.record and entry.record.warrants and true or false,
    }
end

function Editor.refreshElement(session, kind, entry)
    local scene = session.scene
    local element = kind == "vehicle" and scene.vehicles[entry.id] or scene.peds[entry.id]
    if not isElement(element) then return end
    setElementData(element, "vsm.label", kind == "vehicle" and vehicleLabel(entry) or pedLabel(entry))
    Interact.update(session, kind, entry)
end

---------------------------------------------------------------- client state

-- Open issues for the Check issues menu: one row per scene { name, path, count, issues = { ... } }
local function issueRows()
    local byScene, order = {}, {}
    for _, i in ipairs(Issues.query("open")) do
        local row = byScene[i.scene]
        if not row then
            row = { name = i.scene, path = i.path, issues = {}, locked = false }
            byScene[i.scene] = row
            order[#order + 1] = row
        end
        row.issues[#row.issues + 1] = { id = i.id, comment = i.comment, byName = i.byName, at = i.at, source = i.source,
                                       pos = i.pos or false }
    end
    return order
end

-- Everything the R menu needs
function Editor.sync(session)
    local player = session.player
    local lang = L.lang and L.lang(player) or "en"
    local state = { active = true, scenes = {}, locations = Storage.locations(), issues = issueRows() }
    for _, row in ipairs(state.issues) do
        local lockedBy = Editor.locks[row.name]
        row.locked = lockedBy ~= nil and lockedBy ~= player
    end
    for _, s in ipairs(Storage.list()) do
        local lockedBy = Editor.locks[s.name]
        state.scenes[#state.scenes + 1] = {
            name = s.name, path = s.path, title = Storage.title(s, lang), peds = s.peds, vehicles = s.vehicles,
            needs = s.needs, valid = s.valid,
            locked = lockedBy ~= nil and lockedBy ~= player,
        }
    end
    local scene = session.scene
    if scene then
        local d = scene.data
        local validation = {}
        for _, v in ipairs(Storage.validate(Storage.normalize(d, scene.file))) do
            validation[#validation + 1] = { level = v.level, key = v.key, params = v.params }
        end
        local issues = {}
        if scene.file then
            for _, i in ipairs(Issues.query("open")) do
                if i.scene == scene.file then issues[#issues + 1] = i end
            end
        end
        state.scene = {
            file = scene.file or false, dirty = scene.dirty,
            path = scene.file and Storage.file(scene.file) or false,
            target = VSM.SCENE_DIR .. Storage.pathFor(scene.file or "<name>", d) .. ".json",
            category = d.category,
            location = d.location, suggestedLocation = vsmSuggestedLocation(d.center, d.interior), locations = state.locations,
            agencies = {}, safe = d.safe ~= false, enabled = d.enabled, weight = d.weight,
            center = d.center, interior = d.interior,
            vehicles = {}, peds = {}, validation = validation, issues = issues,
        }
        for _, id in ipairs(VSM.AGENCY_ORDER) do state.scene.agencies[id] = Storage.agency(d, id) end
        for _, v in ipairs(d.vehicles) do state.scene.vehicles[#state.scene.vehicles + 1] = vehicleLabel(v) end
        for _, p in ipairs(d.peds) do state.scene.peds[#state.scene.peds + 1] = pedLabel(p) end
    end
    triggerClientEvent(player, "vsm:editorState", resourceRoot, state)
end

function Editor.markDirty(session)
    if session.scene then session.scene.dirty = true end
    Editor.sync(session)
end

---------------------------------------------------------------- scene elements

function Editor.spawnVehicle(session, entry)
    local scene = session.scene
    local vehicle = Builder.createVehicle(entry, scene.data.interior, Editor.dimension(session), false)
    if not vehicle then return nil end
    setVehicleDamageProof(vehicle, false)
    scene.vehicles[entry.id] = vehicle
    setElementData(vehicle, "vsm.editor", true)
    Interact.add(session, "vehicle", entry, vehicle)
    Editor.refreshElement(session, "vehicle", entry)
    return vehicle
end

function Editor.spawnPed(session, entry)
    local scene = session.scene
    local ped = Builder.createPed(entry, scene.data.interior, Editor.dimension(session), scene.vehicles, not entry.vehicle)
    if not ped then return nil end
    scene.peds[entry.id] = ped
    setElementData(ped, "vsm.editor", true)
    Builder.applyPedPose(ped, entry)
    Interact.add(session, "ped", entry, ped)
    Editor.refreshElement(session, "ped", entry)
    return ped
end

local function destroySceneElements(scene)
    for _, list in ipairs({ scene.peds, scene.vehicles }) do
        for _, element in pairs(list) do
            if isElement(element) then destroyElement(element) end -- removes the interact menus too
        end
    end
    scene.peds, scene.vehicles = {}, {}
end

---------------------------------------------------------------- scene load / unload

function Editor.unloadScene(session)
    local scene = session.scene
    if not scene then return end
    if getPedOccupiedVehicle(session.player) then removePedFromVehicle(session.player) end
    destroySceneElements(scene)
    Interact.clear(session)
    if scene.file and Editor.locks[scene.file] == session.player then Editor.locks[scene.file] = nil end
    session.scene = nil
end

local function teleport(player, x, y, z, interior)
    if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    if interior then setElementInterior(player, interior) end
    setElementPosition(player, x, y, z + 0.5)
end

local function openScene(session, data, file)
    Editor.unloadScene(session)
    session.scene = { file = file, data = data, dirty = false, vehicles = {}, peds = {} }
    if file then Editor.locks[file] = session.player end
    setElementInterior(session.player, data.interior)
    for _, entry in ipairs(data.vehicles) do Editor.spawnVehicle(session, entry) end
    for _, entry in ipairs(data.peds) do Editor.spawnPed(session, entry) end
end

local function newScene(session)
    local pos = playerSpot(session.player)
    local data = Storage.normalize({
        center = pos,
        interior = getElementInterior(session.player),
        dimension = session.back.dimension,
        agencies = { ems = { need = 2, priority = VSM.DEFAULT_PRIORITY, caller = VSM.DEFAULT_CALLER } },
    })
    openScene(session, data, nil)
    session.scene.dirty = true
    notify(session, "v_scenemanager.editor.new_scene")
end

local function loadScene(session, name, pos)
    local lockedBy = Editor.locks[name]
    if lockedBy and lockedBy ~= session.player then
        notify(session, "v_scenemanager.editor.in_use", { name = name, player = vsmPlayerName(lockedBy) })
        return
    end
    local data, err = Storage.load(name)
    if not data then
        vsmNotify(session.player, TITLE, err)
        return
    end
    openScene(session, data, name)
    local c = type(pos) == "table" and pos or data.center
    if c then teleport(session.player, c[1], c[2], c[3], data.interior) end
    notify(session, type(pos) == "table" and "v_scenemanager.editor.loaded_issue" or "v_scenemanager.editor.loaded", { name = name })
end

-- Drops seat references to vehicles that no longer exist.
local function cleanReferences(session)
    local scene = session.scene
    for _, entry in ipairs(scene.data.peds) do
        if entry.vehicle and not Editor.findEntry(scene, "vehicle", entry.vehicle) then
            entry.vehicle, entry.seat = nil, nil
        end
    end
end

-- validation: errors stop the save (the first one is shown), warnings are only reported
local function checkScene(session, name)
    local list = Storage.validate(Storage.normalize(session.scene.data, name))
    local errors, warnings = Storage.countIssues(list)
    for _, v in ipairs(list) do
        if v.level == "error" then
            notify(session, "v_scenemanager.editor.save_blocked", { count = errors, first = L.msg(v.key, v.params) })
            return false
        end
    end
    if warnings > 0 then
        for _, v in ipairs(list) do
            notify(session, "v_scenemanager.editor.save_warning", { count = warnings, first = L.msg(v.key, v.params) })
            break
        end
    end
    return true
end

local function writeScene(session, name)
    local scene = session.scene
    local lockedBy = Editor.locks[name]
    if lockedBy and lockedBy ~= session.player then
        notify(session, "v_scenemanager.editor.in_use", { name = name, player = vsmPlayerName(lockedBy) })
        return false
    end
    cleanReferences(session)
    -- a new scene without a category takes the one in its name (ls_heartattack26)
    if not scene.file and scene.data.category == "" then
        scene.data.category = vsmCategory(nil, name)
    end
    if not checkScene(session, name) then return false end
    local ok, result = Storage.save(name, scene.data)
    if not ok then
        notify(session, "v_scenemanager.editor.save_failed", { error = result })
        return false
    end
    if scene.file ~= name then
        if scene.file and Editor.locks[scene.file] == session.player then Editor.locks[scene.file] = nil end
        scene.file = name
        Editor.locks[name] = session.player
    end
    scene.data.name = name
    scene.dirty = false
    notify(session, "v_scenemanager.editor.saved", { file = result })
    vsmLog("%s saved scene '%s'", vsmPlayerName(session.player), name)
    return true
end

---------------------------------------------------------------- start / stop

function Editor.start(player)
    if Editor.sessions[player] then return end
    if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local session = {
        player = player, slot = freeSlot(),
        back = { x = x, y = y, z = z, rz = rz, interior = getElementInterior(player), dimension = getElementDimension(player) },
    }
    Editor.sessions[player] = session
    setElementDimension(player, Editor.dimension(session))
    setElementData(player, "vsm.editor", true)
    Editor.sync(session)
    notify(session, "v_scenemanager.editor.on", { dimension = Editor.dimension(session), key = VSM.KEY_MENU:upper() })
end

function Editor.stop(player, quitting)
    local session = Editor.sessions[player]
    if not session then return end
    Editor.unloadScene(session)
    Editor.sessions[player] = nil
    textRequests[player] = nil
    if quitting then return end
    local b = session.back
    setElementInterior(player, b.interior)
    setElementDimension(player, b.dimension)
    setElementPosition(player, b.x, b.y, b.z)
    setElementRotation(player, 0, 0, b.rz, "default", true)
    removeElementData(player, "vsm.editor")
    triggerClientEvent(player, "vsm:editorState", resourceRoot, false)
    notify(session, "v_scenemanager.editor.off")
end

addCommandHandler(VSM.CMD_EDITOR, function(player)
    if not vsmIsAllowed(player) then return end
    if Editor.sessions[player] then
        Editor.stop(player)
    else
        Editor.start(player)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    Editor.stop(source, true)
end)

addEventHandler("onPlayerWasted", root, function()
    -- a dead editor respawns wherever the spawn manager puts it: leave the editor cleanly
    if Editor.sessions[source] then Editor.stop(source) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Editor.sessions) do Editor.stop(player) end
end)

-- the issue list changed (a new flag): editors see it in Check issues
addEventHandler("onSceneFlagged", resourceRoot, function()
    for _, session in pairs(Editor.sessions) do Editor.sync(session) end
end)

---------------------------------------------------------------- actions

local function addPed(session)
    local player = session.player
    if getPedOccupiedVehicle(player) then
        notify(session, "v_scenemanager.editor.get_out_ped")
        return
    end
    local scene = session.scene
    local pos, rz = playerSpot(player)
    local entry = {
        id = nextEntityId(scene.data.peds, "p"),
        skin = VSM.PED_SKINS[math.random(#VSM.PED_SKINS)],
        pos = pos, rot = rz, anim = "ko_back", injuries = {}, state = {}, role = "patient",
    }
    scene.data.peds[#scene.data.peds + 1] = entry
    -- the player stands on that spot: step back so the ped is not inside the player
    local a = math.rad(rz)
    setElementPosition(player, pos[1] + math.sin(a) * 1.2, pos[2] - math.cos(a) * 1.2, pos[3])
    Editor.spawnPed(session, entry)
    Editor.markDirty(session)
    notify(session, "v_scenemanager.editor.ped_placed", { id = entry.id })
end

local function addVehicle(session, text)
    local player = session.player
    local model = tonumber(text) or getVehicleModelFromName(text)
    if not model or not getVehicleNameFromModel(model) or getVehicleNameFromModel(model) == "" then
        notify(session, "v_scenemanager.editor.unknown_model", { model = tostring(text) })
        return
    end
    if getPedOccupiedVehicle(player) then
        notify(session, "v_scenemanager.editor.get_out_vehicle")
        return
    end
    local scene = session.scene
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local entry = {
        id = nextEntityId(scene.data.vehicles, "v"), model = model,
        pos = { vsmRound(x), vsmRound(y), vsmRound(z + 0.5) },
        rot = { 0, 0, vsmRound(rz, 2) },
        health = 1000, engine = false, lightsOn = false, locked = false, frozen = false,
    }
    scene.data.vehicles[#scene.data.vehicles + 1] = entry
    local vehicle = Editor.spawnVehicle(session, entry)
    if not vehicle then
        table.remove(scene.data.vehicles)
        notify(session, "v_scenemanager.editor.vehicle_failed")
        return
    end
    Builder.captureVehicle(vehicle, entry)
    warpPedIntoVehicle(player, vehicle, 0)
    Editor.markDirty(session)
    notify(session, "v_scenemanager.editor.vehicle_created", { id = entry.id })
end

-- Saves the position + state of the scene vehicle the player sits in
function Editor.saveVehicle(session, entry)
    local vehicle = session.scene.vehicles[entry.id]
    if not isElement(vehicle) then return false end
    Builder.captureVehicle(vehicle, entry)
    Editor.refreshElement(session, "vehicle", entry)
    Editor.markDirty(session)
    notify(session, "v_scenemanager.editor.vehicle_saved", { id = entry.id })
    return true
end

local function currentSceneVehicle(session)
    local vehicle = getPedOccupiedVehicle(session.player)
    if not vehicle or not session.scene then return nil end
    for id, element in pairs(session.scene.vehicles) do
        if element == vehicle then return Editor.findEntry(session.scene, "vehicle", id) end
    end
    return nil
end

-- the agency block of the scene being edited (created when missing)
local function agencyBlock(session, id)
    if not VSM.AGENCIES[id] then return nil end
    local agencies = session.scene.data.agencies
    local b = agencies[id]
    if not b then
        b = { need = 0 }
        agencies[id] = b
    end
    b.locales = b.locales or {}
    b.priority = b.priority or VSM.DEFAULT_PRIORITY
    if id == "ems" then b.caller = b.caller or VSM.DEFAULT_CALLER end
    return b
end

-- Asks for one text of one language of an agency. An empty answer clears it (both fields empty = language removed).
local function askLocale(session, arg, field, maxLen)
    if type(arg) ~= "table" or type(arg.lang) ~= "string" or not arg.lang:match("^%l%l") then return end
    local b = agencyBlock(session, arg.agency)
    if not b then return end
    local current = b.locales[arg.lang] and b.locales[arg.lang][field] or ""
    Editor.askText(session.player, field == "title" and "v_scenemanager.editor.ask_title" or "v_scenemanager.editor.ask_description",
        maxLen, current, function(text)
            if not session.scene then return end
            local entry = b.locales[arg.lang] or { title = "", description = "" }
            entry[field] = text
            if entry.title == "" and entry.description == "" then
                b.locales[arg.lang] = nil
            else
                b.locales[arg.lang] = entry
            end
            Editor.markDirty(session)
        end, { agency = L.msg(VSM.AGENCIES[arg.agency].label), lang = arg.lang:upper() })
    return true
end

-- the latest reported spot of a scene's open issues | nil
local function issueSpot(name)
    for _, i in ipairs(Issues.query("open")) do
        if i.scene == name and type(i.pos) == "table" then return i.pos end
    end
end

local ACTIONS = {
    new = function(session) newScene(session) end,
    load = function(session, name)
        if type(name) == "string" then loadScene(session, name) end
    end,
    issue_load = function(session, name)
        if type(name) == "string" then loadScene(session, name, issueSpot(name) or true) end
    end,
    exit = function(session) Editor.stop(session.player) end,
}

local SCENE_ACTIONS = {
    leave = function(session)
        local dirty = session.scene.dirty
        Editor.unloadScene(session)
        notify(session, dirty and "v_scenemanager.editor.closed_discarded" or "v_scenemanager.editor.closed")
    end,
    save = function(session)
        if not session.scene.file then
            notify(session, "v_scenemanager.editor.never_saved")
            return
        end
        writeScene(session, session.scene.file)
    end,
    saveas = function(session)
        Editor.askText(session.player, "v_scenemanager.editor.ask_save_as", VSM.NAME_MAX, session.scene.file or "", function(text)
            if not session.scene then return end
            local name = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.json$", ""):gsub("%s", "_")
            if not vsmValidName(name) then
                notify(session, "v_scenemanager.editor.invalid_name")
                return
            end
            if Storage.exists(name) and name ~= session.scene.file then
                notify(session, "v_scenemanager.editor.name_exists", { name = name })
                return
            end
            writeScene(session, name)
            Editor.sync(session)
        end)
        return true
    end,
    validate = function(session)
        local list = Storage.validate(Storage.normalize(session.scene.data, session.scene.file))
        if #list == 0 then notify(session, "v_scenemanager.editor.valid_ok") end
        for i, v in ipairs(list) do
            if i > 4 then break end
            vsmNotify(session.player, v.level == "error" and "v_scenemanager.valid.error" or "v_scenemanager.valid.warning",
                L.msg(v.key, v.params))
        end
        return true
    end,
    teleport = function(session)
        local c = session.scene.data.center
        teleport(session.player, c[1], c[2], c[3], session.scene.data.interior)
        return true
    end,
    center = function(session)
        local pos = playerSpot(session.player)
        session.scene.data.center = pos
        session.scene.data.interior = getElementInterior(session.player)
        notify(session, "v_scenemanager.editor.centre_set")
    end,
    agency_need = function(session, arg)
        local b = type(arg) == "table" and agencyBlock(session, arg.agency)
        local v = b and math.floor(tonumber(arg.v) or -1)
        if b and v >= 0 and v <= 2 then b.need = v end
    end,
    agency_priority = function(session, arg)
        local b = type(arg) == "table" and agencyBlock(session, arg.agency)
        local p = b and math.floor(tonumber(arg.v) or 0)
        if b and p >= 1 and p <= 4 then b.priority = p end
    end,
    agency_latejoin = function(session, agency)
        local b = agencyBlock(session, agency)
        if b then b.lateJoin = b.lateJoin == false end
    end,
    agency_title = function(session, arg) return askLocale(session, arg, "title", 80) end,
    agency_description = function(session, arg) return askLocale(session, arg, "description", 400) end,
    agency_caller = function(session)
        local b = agencyBlock(session, "ems")
        Editor.askText(session.player, "v_scenemanager.editor.ask_caller", 40, b.caller, function(text)
            if session.scene and text ~= "" then b.caller = text; Editor.markDirty(session) end
        end)
        return true
    end,
    pd_close = function(session, key)
        local b = agencyBlock(session, "pd")
        local known = false
        for _, k in ipairs(VSM_PD_CLOSE) do if k == key then known = true end end
        if not known then return true end
        b.close = b.close or {}
        b.close[key] = not b.close[key] or nil
    end,
    safe = function(session)
        session.scene.data.safe = session.scene.data.safe == false
    end,
    enabled = function(session)
        session.scene.data.enabled = not session.scene.data.enabled
    end,
    category = function(session, id)
        if type(id) == "string" then session.scene.data.category = vsmCategory(id) end
    end,
    location = function(session, label)
        if vsmValidLocation(label) then session.scene.data.location = label end
    end,
    newlocation = function(session)
        Editor.askText(session.player, "v_scenemanager.editor.ask_location", VSM.NAME_MAX, session.scene.data.location, function(text)
            if not session.scene then return end
            local label = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
            if not vsmValidLocation(label) then
                notify(session, "v_scenemanager.editor.invalid_location")
                return
            end
            session.scene.data.location = label
            Editor.markDirty(session)
        end)
        return true
    end,
    weight = function(session, w)
        w = tonumber(w)
        if w and w >= 0 then session.scene.data.weight = w end
    end,
    addped = function(session) addPed(session); return true end,
    addveh = function(session)
        Editor.askText(session.player, "v_scenemanager.editor.ask_model", 30, "", function(text)
            if session.scene then addVehicle(session, text) end
        end)
        return true
    end,
    savevehicle = function(session)
        local entry = currentSceneVehicle(session)
        if not entry then
            notify(session, "v_scenemanager.editor.sit_in_vehicle")
            return true
        end
        Editor.saveVehicle(session, entry)
        return true
    end,
    gotoped = function(session, id)
        local ped = session.scene.peds[id]
        if isElement(ped) then
            local x, y, z = getElementPosition(ped)
            teleport(session.player, x + 1.5, y, z)
        end
        return true
    end,
    gotoveh = function(session, id)
        local vehicle = session.scene.vehicles[id]
        if isElement(vehicle) then
            local x, y, z = getElementPosition(vehicle)
            teleport(session.player, x + 3, y, z + 0.5)
        end
        return true
    end,
    issue_tp = function(session, id)
        local issue = Issues.get(id)
        if issue and type(issue.pos) == "table" then
            teleport(session.player, issue.pos[1], issue.pos[2], issue.pos[3], session.scene.data.interior)
        else
            notify(session, "v_scenemanager.editor.issue_no_spot")
        end
        return true
    end,
    issue_resolve = function(session, id)
        if Issues.resolve(id, vsmAccount(session.player)) then notify(session, "v_scenemanager.editor.issue_resolved", { id = id }) end
        Editor.sync(session)
        return true
    end,
    issue_resolve_all = function(session)
        local n = session.scene.file and Issues.resolveScene(session.scene.file, vsmAccount(session.player)) or 0
        notify(session, "v_scenemanager.editor.issues_resolved", { count = n })
        Editor.sync(session)
        return true
    end,
}

addEventHandler("vsm:editorAction", resourceRoot, function(action, arg)
    local session = Editor.sessions[client]
    if not session or type(action) ~= "string" then return end
    if not vsmIsAllowed(client) then
        Editor.stop(client)
        return
    end
    local handler = ACTIONS[action]
    if handler then
        handler(session, arg)
    else
        handler = SCENE_ACTIONS[action]
        if not handler or not session.scene then return end
        -- true = the handler syncs on its own (or nothing to mark dirty)
        if handler(session, arg) then
            if Editor.sessions[client] then Editor.sync(session) end
            return
        end
        if session.scene and action ~= "leave" and action ~= "save" then
            session.scene.dirty = true
        end
    end
    if Editor.sessions[client] then Editor.sync(session) end
end)
