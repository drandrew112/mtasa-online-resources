-- In-game scene editor (/medsceneeditor toggles it).
--
-- Every editor works in a private dimension. The scene being edited is a set of real
-- vehicles / peds in that dimension (no medsys simulation). The R menu (ui_inac temp
-- menu, client/editor.lua) sends actions here; the elements themselves are edited
-- through ui_interactobject menus (server/interact.lua). Nothing is written to disk
-- until Save / Save as.
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

addEvent("msm:editorAction", true)
addEvent("msm:textResult", true)

---------------------------------------------------------------- helpers

local function freeSlot()
    local used = {}
    for _, s in pairs(Editor.sessions) do used[s.slot] = true end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    return slot
end

function Editor.dimension(session)
    return MSM.EDITOR_DIMENSION + session.slot
end

-- Asks the player for a text (ui_core text input); callback(text) only on confirm.
function Editor.askText(player, title, maxLen, default, callback)
    local id = nextRequest
    nextRequest = nextRequest + 1
    textRequests[player] = { id = id, callback = callback }
    triggerClientEvent(player, "msm:askText", resourceRoot, id, title, maxLen or 64, default and tostring(default) or "")
end

addEventHandler("msm:textResult", resourceRoot, function(id, text)
    local req = textRequests[client]
    if not req or req.id ~= id then return end
    textRequests[client] = nil
    if type(text) == "string" and Editor.sessions[client] then req.callback(text) end
end)

local function playerSpot(player)
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    return { msmRound(x), msmRound(y), msmRound(z) }, msmRound(rz, 1)
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

local function vehicleLabel(entry)
    local name = getVehicleNameFromModel(entry.model) or tostring(entry.model)
    local opts = {}
    if entry.engine then opts[#opts + 1] = "engine" end
    if entry.lightsOn then opts[#opts + 1] = "lights" end
    if entry.sirens then opts[#opts + 1] = "sirens" end
    if entry.locked then opts[#opts + 1] = "locked" end
    if entry.frozen then opts[#opts + 1] = "frozen" end
    return ("%s  %s (%d hp)%s"):format(entry.id, name, tonumber(entry.health) or 1000,
        #opts > 0 and ("\n" .. table.concat(opts, ", ")) or "")
end

local function pedLabel(entry)
    local lines = { ("%s  skin %d"):format(entry.id, entry.skin or 0) }
    local anim = msmAnimById(entry.anim)
    if entry.vehicle then
        lines[1] = lines[1] .. ("  [in %s, seat %d]"):format(entry.vehicle, entry.seat or 0)
    elseif anim and anim.id ~= "none" then
        lines[1] = lines[1] .. "  " .. anim.label
    end
    for _, inj in ipairs(entry.injuries) do
        lines[#lines + 1] = ("%s (%s)"):format(msmInjuryLabel(inj.type), MSM_SEVERITY[inj.severity] or "?")
    end
    for _, key in ipairs(MSM_STATE_ORDER) do
        if entry.state[key] ~= nil then
            lines[#lines + 1] = ("%s: %s"):format(MSM_STATE[key].label, msmStateValueLabel(key, entry.state[key]))
        end
    end
    if #lines == 1 then lines[2] = "no injuries" end
    return table.concat(lines, "\n")
end

function Editor.refreshElement(session, kind, entry)
    local scene = session.scene
    local element = kind == "vehicle" and scene.vehicles[entry.id] or scene.peds[entry.id]
    if not isElement(element) then return end
    setElementData(element, "msm.label", kind == "vehicle" and vehicleLabel(entry) or pedLabel(entry))
    Interact.update(session, kind, entry)
end

---------------------------------------------------------------- client state

-- Everything the R menu needs
function Editor.sync(session)
    local player = session.player
    local state = { active = true, scenes = {} }
    for _, s in ipairs(Storage.list()) do
        local lockedBy = Editor.locks[s.name]
        state.scenes[#state.scenes + 1] = {
            name = s.name, title = s.title, peds = s.peds, vehicles = s.vehicles,
            locked = lockedBy ~= nil and lockedBy ~= player,
        }
    end
    local scene = session.scene
    if scene then
        local d = scene.data
        state.scene = {
            file = scene.file or false, dirty = scene.dirty,
            erm = d.erm, enabled = d.enabled, weight = d.weight,
            center = d.center, interior = d.interior,
            vehicles = {}, peds = {},
        }
        for _, v in ipairs(d.vehicles) do
            state.scene.vehicles[#state.scene.vehicles + 1] = { id = v.id, label = (vehicleLabel(v):gsub("\n", " | ")) }
        end
        for _, p in ipairs(d.peds) do
            state.scene.peds[#state.scene.peds + 1] = { id = p.id, label = (pedLabel(p):gsub("\n", " | ")) }
        end
    end
    triggerClientEvent(player, "msm:editorState", resourceRoot, state)
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
    setElementData(vehicle, "msm.editor", true)
    Interact.add(session, "vehicle", entry, vehicle)
    Editor.refreshElement(session, "vehicle", entry)
    return vehicle
end

function Editor.spawnPed(session, entry)
    local scene = session.scene
    local ped = Builder.createPed(entry, scene.data.interior, Editor.dimension(session), scene.vehicles, not entry.vehicle)
    if not ped then return nil end
    scene.peds[entry.id] = ped
    setElementData(ped, "msm.editor", true)
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
        erm = msmCopy(MSM.DEFAULT_ERM),
    })
    openScene(session, data, nil)
    session.scene.dirty = true
    msmNotify(session.player, "Scene editor", "New scene created. The ERM centre is your position.")
end

local function loadScene(session, name)
    local lockedBy = Editor.locks[name]
    if lockedBy and lockedBy ~= session.player then
        msmNotify(session.player, "Scene editor", name .. " is being edited by " .. getPlayerName(lockedBy))
        return
    end
    local data, err = Storage.load(name)
    if not data then
        msmNotify(session.player, "Scene editor", err)
        return
    end
    openScene(session, data, name)
    msmNotify(session.player, "Scene editor", "Loaded " .. name .. ". Use Teleport to scene to go there.")
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

local function writeScene(session, name)
    local scene = session.scene
    local lockedBy = Editor.locks[name]
    if lockedBy and lockedBy ~= session.player then
        msmNotify(session.player, "Scene editor", name .. " is being edited by " .. getPlayerName(lockedBy))
        return false
    end
    cleanReferences(session)
    local ok, err = Storage.save(name, scene.data)
    if not ok then
        msmNotify(session.player, "Scene editor", "Save failed: " .. tostring(err))
        return false
    end
    if scene.file ~= name then
        if scene.file and Editor.locks[scene.file] == session.player then Editor.locks[scene.file] = nil end
        scene.file = name
        Editor.locks[name] = session.player
    end
    scene.data.name = name
    scene.dirty = false
    msmNotify(session.player, "Scene editor", "Saved: " .. MSM.SCENE_DIR .. name .. ".json")
    msmLog("%s saved scene '%s'", getPlayerName(session.player), name)
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
    setElementData(player, "msm.editor", true)
    Editor.sync(session)
    msmSay(player, ("Scene editor #5ad25aON#ffffff (private dimension %d). Press #ffd24aE#ffffff for the menu."):format(Editor.dimension(session)))
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
    removeElementData(player, "msm.editor")
    triggerClientEvent(player, "msm:editorState", resourceRoot, false)
    msmSay(player, "Scene editor #ff5a5aOFF")
end

addCommandHandler(MSM.CMD_EDITOR, function(player)
    if not msmIsAllowed(player) then return end
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

---------------------------------------------------------------- actions

local function teleport(player, x, y, z, interior)
    if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    if interior then setElementInterior(player, interior) end
    setElementPosition(player, x, y, z + 0.5)
end

local function addPed(session)
    local player = session.player
    if getPedOccupiedVehicle(player) then
        msmNotify(player, "Scene editor", "Get out of the vehicle to place a ped.")
        return
    end
    local scene = session.scene
    local pos, rz = playerSpot(player)
    local entry = {
        id = nextEntityId(scene.data.peds, "p"),
        skin = MSM.PED_SKINS[math.random(#MSM.PED_SKINS)],
        pos = pos, rot = rz, anim = "ko_back", injuries = {}, state = {},
    }
    scene.data.peds[#scene.data.peds + 1] = entry
    -- the player stands on that spot: step back so the ped is not inside the player
    local a = math.rad(rz)
    setElementPosition(player, pos[1] + math.sin(a) * 1.2, pos[2] - math.cos(a) * 1.2, pos[3])
    Editor.spawnPed(session, entry)
    Editor.markDirty(session)
    msmNotify(player, "Scene editor", entry.id .. " placed. Press X near it to edit (skin, pose, injuries ...).")
end

local function addVehicle(session, text)
    local player = session.player
    local model = tonumber(text) or getVehicleModelFromName(text)
    if not model or not getVehicleNameFromModel(model) or getVehicleNameFromModel(model) == "" then
        msmNotify(player, "Scene editor", "Unknown vehicle model: " .. tostring(text))
        return
    end
    if getPedOccupiedVehicle(player) then
        msmNotify(player, "Scene editor", "Get out of the vehicle first, the new one is created where you stand.")
        return
    end
    local scene = session.scene
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local entry = {
        id = nextEntityId(scene.data.vehicles, "v"), model = model,
        pos = { msmRound(x), msmRound(y), msmRound(z + 0.5) },
        rot = { 0, 0, msmRound(rz, 2) },
        health = 1000, engine = false, lightsOn = false, locked = false, frozen = false,
    }
    scene.data.vehicles[#scene.data.vehicles + 1] = entry
    local vehicle = Editor.spawnVehicle(session, entry)
    if not vehicle then
        table.remove(scene.data.vehicles)
        msmNotify(player, "Scene editor", "Could not create the vehicle here.")
        return
    end
    Builder.captureVehicle(vehicle, entry)
    warpPedIntoVehicle(player, vehicle, 0)
    Editor.markDirty(session)
    msmNotify(player, "Scene editor", entry.id .. " created. Drive it into place, then save its position (R menu or X).")
end

-- Saves the position + state of the scene vehicle the player sits in
function Editor.saveVehicle(session, entry)
    local vehicle = session.scene.vehicles[entry.id]
    if not isElement(vehicle) then return false end
    Builder.captureVehicle(vehicle, entry)
    Editor.refreshElement(session, "vehicle", entry)
    Editor.markDirty(session)
    msmNotify(session.player, "Scene editor", entry.id .. ": position and state saved.")
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

local SCENE_ACTIONS -- actions that need a loaded scene

local ACTIONS = {
    new = function(session) newScene(session) end,
    load = function(session, name)
        if type(name) == "string" then loadScene(session, name) end
    end,
    exit = function(session) Editor.stop(session.player) end,
}

SCENE_ACTIONS = {
    leave = function(session)
        local dirty = session.scene.dirty
        Editor.unloadScene(session)
        msmNotify(session.player, "Scene editor", dirty and "Scene closed, unsaved changes discarded." or "Scene closed.")
    end,
    save = function(session)
        if not session.scene.file then
            msmNotify(session.player, "Scene editor", "This scene was never saved. Use Save as.")
            return
        end
        writeScene(session, session.scene.file)
    end,
    saveas = function(session)
        Editor.askText(session.player, "Save scene as (a-z, 0-9, _ -)", MSM.NAME_MAX, session.scene.file or "", function(text)
            if not session.scene then return end
            local name = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.json$", ""):gsub("%s", "_")
            if not msmValidName(name) then
                msmNotify(session.player, "Scene editor", "Invalid name. Letters, digits, _ and - only.")
                return
            end
            if Storage.exists(name) and name ~= session.scene.file then
                msmNotify(session.player, "Scene editor", name .. " already exists. Pick another name (or load it).")
                return
            end
            writeScene(session, name)
            Editor.sync(session)
        end)
    end,
    teleport = function(session)
        local c = session.scene.data.center
        teleport(session.player, c[1], c[2], c[3], session.scene.data.interior)
    end,
    center = function(session)
        local pos = playerSpot(session.player)
        session.scene.data.center = pos
        session.scene.data.interior = getElementInterior(session.player)
        msmNotify(session.player, "Scene editor", "ERM task centre set to your position.")
    end,
    title = function(session)
        Editor.askText(session.player, "ERM task title", 80, session.scene.data.erm.title, function(text)
            if session.scene and text ~= "" then session.scene.data.erm.title = text; Editor.markDirty(session) end
        end)
        return true
    end,
    description = function(session)
        Editor.askText(session.player, "ERM task description", 250, session.scene.data.erm.description, function(text)
            if session.scene then session.scene.data.erm.description = text; Editor.markDirty(session) end
        end)
        return true
    end,
    caller = function(session)
        Editor.askText(session.player, "ERM caller", 40, session.scene.data.erm.caller, function(text)
            if session.scene and text ~= "" then session.scene.data.erm.caller = text; Editor.markDirty(session) end
        end)
        return true
    end,
    priority = function(session, p)
        p = math.floor(tonumber(p) or 0)
        if p >= 1 and p <= 4 then session.scene.data.erm.priority = p end
    end,
    enabled = function(session)
        session.scene.data.enabled = not session.scene.data.enabled
    end,
    weight = function(session, w)
        w = tonumber(w)
        if w and w >= 0 then session.scene.data.weight = w end
    end,
    addped = function(session) addPed(session); return true end,
    addveh = function(session)
        Editor.askText(session.player, "Vehicle model (ID or name)", 30, "", function(text)
            if session.scene then addVehicle(session, text) end
        end)
        return true
    end,
    savevehicle = function(session)
        local entry = currentSceneVehicle(session)
        if not entry then
            msmNotify(session.player, "Scene editor", "Sit in a scene vehicle first.")
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
}

addEventHandler("msm:editorAction", resourceRoot, function(action, arg)
    local session = Editor.sessions[client]
    if not session or type(action) ~= "string" then return end
    if not msmIsAllowed(client) then
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
        if handler(session, arg) then return end
        if session.scene and action ~= "leave" and action ~= "save" and action ~= "saveas" and action ~= "teleport" then
            session.scene.dirty = true
        end
    end
    if Editor.sessions[client] then Editor.sync(session) end
end)
