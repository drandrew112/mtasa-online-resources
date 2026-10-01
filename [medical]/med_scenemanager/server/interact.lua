-- ui_interactobject menus on the editor's scene vehicles / peds (X opens, 1-9 picks).
-- Only the editing player sees them. Element changes are not saved to disk until Save.

Interact = {}

local IO = "ui_interactobject"
local menus = {} -- [menuId] = { session, kind, id }

local function iobj()
    return exports[IO]
end

local function mark(on, label)
    return (on and "» " or "") .. label
end

---------------------------------------------------------------- menu definitions

local function pedItems(entry)
    local anims = {}
    for _, a in ipairs(MSM_ANIMS) do
        anims[#anims + 1] = { label = mark(entry.anim == a.id, a.label), value = { a = "anim", v = a.id }, closeOnSelect = false }
    end

    local addInjury = {}
    for _, inj in ipairs(MSM_INJURIES) do
        local severities = {}
        for sev, label in ipairs(MSM_SEVERITY) do
            severities[sev] = { label = label, value = { a = "injury", t = inj.id, s = sev }, closeOnSelect = false }
        end
        addInjury[#addInjury + 1] = { label = inj.label, items = severities }
    end
    local injuries = { { label = "Add injury", items = addInjury } }
    for i, inj in ipairs(entry.injuries) do
        injuries[#injuries + 1] = {
            label = ("Remove: %s (%s)"):format(msmInjuryLabel(inj.type), MSM_SEVERITY[inj.severity] or "?"),
            value = { a = "uninjure", i = i }, closeOnSelect = false,
        }
    end
    if #entry.injuries > 0 then
        injuries[#injuries + 1] = { label = "Remove all", value = { a = "uninjure", i = 0 }, closeOnSelect = false }
    end

    local state = {}
    for _, key in ipairs(MSM_STATE_ORDER) do
        local def = MSM_STATE[key]
        local current = entry.state[key]
        local values = { { label = mark(current == nil, "Not set (simulated)"), value = { a = "state", k = key, clear = true }, closeOnSelect = false } }
        for i, preset in ipairs(def.presets) do
            values[#values + 1] = { label = mark(current == preset[2], preset[1]), value = { a = "state", k = key, i = i }, closeOnSelect = false }
        end
        state[#state + 1] = {
            label = ("%s: %s"):format(def.label, current == nil and "-" or msmStateValueLabel(key, current)),
            items = values,
        }
    end

    local seats = {
        { label = "Nearest vehicle: driver", value = { a = "seat", s = 0 } },
        { label = "Nearest vehicle: front passenger", value = { a = "seat", s = 1 } },
        { label = "Nearest vehicle: rear left", value = { a = "seat", s = 2 } },
        { label = "Nearest vehicle: rear right", value = { a = "seat", s = 3 } },
        { label = "Take out of the vehicle", value = { a = "unseat" }, disabled = entry.vehicle == nil },
    }

    return {
        { label = "Move to my position", value = { a = "move" } },
        { label = "Face me", value = { a = "face" }, closeOnSelect = false },
        { label = "Pose", items = anims },
        { label = ("Injuries (%d)"):format(#entry.injuries), items = injuries },
        { label = "Medical state", items = state },
        { label = ("Skin (%d) ..."):format(entry.skin or 0), value = { a = "skin" } },
        { label = entry.vehicle and ("Seat: %s / %d"):format(entry.vehicle, entry.seat or 0) or "Seat in vehicle", items = seats },
        { label = "Delete", items = { { label = "Yes, delete " .. entry.id, value = { a = "delete" } } } },
    }
end

local function vehicleItems(entry)
    local damage, colors = {}, {}
    for _, d in ipairs(MSM_DAMAGE) do
        damage[#damage + 1] = { label = d.label, value = { a = "damage", v = d.id }, closeOnSelect = false }
    end
    for i, c in ipairs(MSM_COLORS) do
        colors[#colors + 1] = { label = c[1], value = { a = "color", i = i }, closeOnSelect = false }
    end
    local function onOff(v) return v and "ON" or "OFF" end
    local options = {
        { label = "Engine: " .. onOff(entry.engine), value = { a = "toggle", k = "engine" }, closeOnSelect = false },
        { label = "Lights: " .. onOff(entry.lightsOn), value = { a = "toggle", k = "lightsOn" }, closeOnSelect = false },
        { label = "Sirens: " .. onOff(entry.sirens), value = { a = "toggle", k = "sirens" }, closeOnSelect = false },
        { label = "Locked: " .. onOff(entry.locked), value = { a = "toggle", k = "locked" }, closeOnSelect = false },
        { label = "Frozen in the live scene: " .. onOff(entry.frozen), value = { a = "toggle", k = "frozen" }, closeOnSelect = false },
    }
    return {
        { label = "Save position & state", value = { a = "save" } },
        { label = "Get in (driver)", value = { a = "enter" } },
        { label = "Damage", items = damage },
        { label = "Colour", items = colors },
        { label = "Options", items = options },
        { label = ("Plate (%s) ..."):format(entry.plate or "-"), value = { a = "plate" } },
        { label = ("Model (%d) ..."):format(entry.model), value = { a = "model" } },
        { label = "Delete", items = { { label = "Yes, delete " .. entry.id, value = { a = "delete" } } } },
    }
end

local function definition(kind, entry)
    if kind == "vehicle" then
        return {
            title = "Scene vehicle " .. entry.id, range = MSM.INTERACT_RANGE, priority = 50,
            lineOfSight = false, allowInVehicle = true, items = vehicleItems(entry),
        }
    end
    return {
        title = "Scene ped " .. entry.id, range = MSM.INTERACT_RANGE, priority = 50,
        lineOfSight = false, items = pedItems(entry),
    }
end

---------------------------------------------------------------- registry

function Interact.add(session, kind, entry, element)
    if not msmResourceRunning(IO) then return end
    local id = iobj():addInteractMenu(element, definition(kind, entry), session.player)
    if id then
        menus[id] = { session = session, kind = kind, id = entry.id, element = element }
        session.menus = session.menus or {}
        session.menus[kind .. ":" .. entry.id] = id
    end
end

function Interact.update(session, kind, entry)
    local menuId = session.menus and session.menus[kind .. ":" .. entry.id]
    if not menuId or not msmResourceRunning(IO) then return end
    local def = definition(kind, entry)
    iobj():updateInteractMenu(menuId, { title = def.title, items = def.items })
end

function Interact.remove(session, kind, entryId)
    local key = kind .. ":" .. entryId
    local menuId = session.menus and session.menus[key]
    if not menuId then return end
    session.menus[key] = nil
    menus[menuId] = nil
    if msmResourceRunning(IO) and iobj():isInteractMenu(menuId) then iobj():removeInteractMenu(menuId) end
end

function Interact.clear(session)
    for _, menuId in pairs(session.menus or {}) do
        menus[menuId] = nil
        if msmResourceRunning(IO) and iobj():isInteractMenu(menuId) then iobj():removeInteractMenu(menuId) end
    end
    session.menus = {}
end

-- ui_interactobject restarted: every registration is gone, register again
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= IO then return end
    setTimer(function()
        menus = {}
        for _, session in pairs(Editor.sessions) do
            local scene = session.scene
            session.menus = {}
            if scene then
                for _, entry in ipairs(scene.data.vehicles) do
                    if isElement(scene.vehicles[entry.id]) then Interact.add(session, "vehicle", entry, scene.vehicles[entry.id]) end
                end
                for _, entry in ipairs(scene.data.peds) do
                    if isElement(scene.peds[entry.id]) then Interact.add(session, "ped", entry, scene.peds[entry.id]) end
                end
            end
        end
    end, 500, 1)
end)

---------------------------------------------------------------- vehicle actions

local function nearestSceneVehicle(scene, element, maxDist)
    local x, y, z = getElementPosition(element)
    local best, bestId, bestDist
    for id, vehicle in pairs(scene.vehicles) do
        if isElement(vehicle) then
            local d = getDistanceBetweenPoints3D(x, y, z, getElementPosition(vehicle))
            if d <= maxDist and (not bestDist or d < bestDist) then best, bestId, bestDist = vehicle, id, d end
        end
    end
    return best, bestId
end

local function respawnVehicle(session, entry)
    local scene = session.scene
    local old = scene.vehicles[entry.id]
    Interact.remove(session, "vehicle", entry.id)
    if isElement(old) then destroyElement(old) end
    scene.vehicles[entry.id] = nil
    Editor.spawnVehicle(session, entry)
    -- seat the peds again
    for _, ped in ipairs(scene.data.peds) do
        if ped.vehicle == entry.id and isElement(scene.peds[ped.id]) then
            if not Builder.seatPed(scene.peds[ped.id], ped, scene.vehicles) then
                ped.vehicle, ped.seat = nil, nil
                setElementFrozen(scene.peds[ped.id], true)
                Builder.applyPedPose(scene.peds[ped.id], ped)
            end
            Editor.refreshElement(session, "ped", ped)
        end
    end
end

local function takePedOut(session, pedEntry, vehicle)
    local ped = session.scene.peds[pedEntry.id]
    local x, y, z = getElementPosition(vehicle or ped)
    pedEntry.vehicle, pedEntry.seat = nil, nil
    pedEntry.pos = { msmRound(x + 2), msmRound(y), msmRound(z + 0.3) }
    if isElement(ped) then
        Builder.seatPed(ped, pedEntry)
        setElementFrozen(ped, true)
        Builder.applyPedPose(ped, pedEntry)
    end
end

local VEHICLE = {
    save = function(session, entry) Editor.saveVehicle(session, entry); return true end,
    enter = function(session, entry, vehicle)
        local occupant = getVehicleOccupant(vehicle, 0)
        if occupant and occupant ~= session.player then
            msmNotify(session.player, "Scene editor", "A ped sits in the driver seat.")
            return true
        end
        warpPedIntoVehicle(session.player, vehicle, 0)
        return true
    end,
    damage = function(session, entry, vehicle, value)
        if not Builder.damagePreset(entry, value.v) then return true end
        Builder.applyVehicle(vehicle, entry)
    end,
    color = function(session, entry, vehicle, value)
        local c = MSM_COLORS[tonumber(value.i) or 0]
        if not c then return true end
        local colors = { getVehicleColor(vehicle, true) }
        colors[1], colors[2], colors[3] = c[2], c[3], c[4]
        setVehicleColor(vehicle, unpack(colors))
        entry.colors = colors
    end,
    toggle = function(session, entry, vehicle, value)
        local key = value.k
        if key ~= "engine" and key ~= "lightsOn" and key ~= "sirens" and key ~= "locked" and key ~= "frozen" then return true end
        entry[key] = not entry[key]
        Builder.applyVehicleOptions(vehicle, entry)
    end,
    plate = function(session, entry)
        Editor.askText(session.player, "Licence plate (max 8)", 8, entry.plate or "", function(text)
            local vehicle = session.scene and session.scene.vehicles[entry.id]
            if not isElement(vehicle) then return end
            entry.plate = text:sub(1, 8)
            setVehiclePlateText(vehicle, entry.plate)
            Editor.refreshElement(session, "vehicle", entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    model = function(session, entry)
        Editor.askText(session.player, "Vehicle model (ID or name)", 30, tostring(entry.model), function(text)
            local vehicle = session.scene and session.scene.vehicles[entry.id]
            if not isElement(vehicle) then return end
            local model = tonumber(text) or getVehicleModelFromName(text)
            local name = model and getVehicleNameFromModel(model)
            if not name or name == "" then
                msmNotify(session.player, "Scene editor", "Unknown vehicle model: " .. text)
                return
            end
            entry.model = model
            entry.upgrades, entry.variant, entry.paintjob = {}, nil, 3
            respawnVehicle(session, entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    delete = function(session, entry, vehicle)
        local scene = session.scene
        for _, ped in ipairs(scene.data.peds) do
            if ped.vehicle == entry.id then
                takePedOut(session, ped, vehicle)
                Editor.refreshElement(session, "ped", ped)
            end
        end
        if getPedOccupiedVehicle(session.player) == vehicle then removePedFromVehicle(session.player) end
        local _, index = Editor.findEntry(scene, "vehicle", entry.id)
        if index then table.remove(scene.data.vehicles, index) end
        Interact.remove(session, "vehicle", entry.id)
        scene.vehicles[entry.id] = nil
        if isElement(vehicle) then destroyElement(vehicle) end
        Editor.markDirty(session)
        return true
    end,
}

---------------------------------------------------------------- ped actions

local PED = {
    move = function(session, entry, ped)
        if entry.vehicle then return true end
        local x, y, z = getElementPosition(session.player)
        local _, _, rz = getElementRotation(session.player)
        entry.pos, entry.rot = { msmRound(x), msmRound(y), msmRound(z) }, msmRound(rz, 1)
        local a = math.rad(rz)
        setElementPosition(session.player, x + math.sin(a) * 1.2, y - math.cos(a) * 1.2, z)
        Builder.seatPed(ped, entry)
        Builder.applyPedPose(ped, entry)
    end,
    face = function(session, entry, ped)
        if entry.vehicle then return true end
        local px, py = getElementPosition(session.player)
        local x, y = getElementPosition(ped)
        entry.rot = msmRound(-math.deg(math.atan2(px - x, py - y)), 1)
        setElementRotation(ped, 0, 0, entry.rot, "default", true)
        Builder.applyPedPose(ped, entry)
    end,
    anim = function(session, entry, ped, value)
        if not msmAnimById(value.v) then return true end
        entry.anim = value.v
        Builder.applyPedPose(ped, entry)
    end,
    injury = function(session, entry, ped, value)
        local sev = tonumber(value.s)
        if not sev or sev < 1 or sev > 3 then return true end
        entry.injuries[#entry.injuries + 1] = { type = tostring(value.t), severity = sev }
    end,
    uninjure = function(session, entry, ped, value)
        local i = tonumber(value.i)
        if i == 0 then
            entry.injuries = {}
        elseif i and entry.injuries[i] then
            table.remove(entry.injuries, i)
        end
    end,
    state = function(session, entry, ped, value)
        local def = MSM_STATE[value.k]
        if not def then return true end
        if value.clear then
            entry.state[value.k] = nil
        else
            local preset = def.presets[tonumber(value.i) or 0]
            if not preset then return true end
            entry.state[value.k] = preset[2]
        end
    end,
    skin = function(session, entry)
        Editor.askText(session.player, "Ped skin ID", 3, tostring(entry.skin or 0), function(text)
            local ped = session.scene and session.scene.peds[entry.id]
            local skin = tonumber(text)
            if not isElement(ped) or not skin then return end
            if not setElementModel(ped, math.floor(skin)) then
                msmNotify(session.player, "Scene editor", "Invalid skin ID: " .. text)
                return
            end
            entry.skin = math.floor(skin)
            Builder.applyPedPose(ped, entry)
            Editor.refreshElement(session, "ped", entry)
            Editor.markDirty(session)
        end)
        return true
    end,
    seat = function(session, entry, ped, value)
        local scene = session.scene
        local vehicle, vehicleId = nearestSceneVehicle(scene, ped, 10)
        if not vehicle then
            msmNotify(session.player, "Scene editor", "No scene vehicle within 10 m of the ped.")
            return true
        end
        local seat = math.floor(tonumber(value.s) or 0)
        if seat > (getVehicleMaxPassengers(vehicle) or 0) then
            msmNotify(session.player, "Scene editor", "That vehicle has no such seat.")
            return true
        end
        local occupant = getVehicleOccupant(vehicle, seat)
        if occupant and occupant ~= ped then
            msmNotify(session.player, "Scene editor", "That seat is taken.")
            return true
        end
        local old = { entry.vehicle, entry.seat }
        entry.vehicle, entry.seat = vehicleId, seat
        setElementFrozen(ped, false)
        setPedAnimation(ped)
        if getPedOccupiedVehicle(ped) then removePedFromVehicle(ped) end
        if not Builder.seatPed(ped, entry, scene.vehicles) then
            entry.vehicle, entry.seat = old[1], old[2]
            setElementFrozen(ped, true)
            msmNotify(session.player, "Scene editor", "Could not seat the ped.")
        end
    end,
    unseat = function(session, entry, ped)
        if not entry.vehicle then return true end
        takePedOut(session, entry, getPedOccupiedVehicle(ped))
    end,
    delete = function(session, entry, ped)
        local scene = session.scene
        local _, index = Editor.findEntry(scene, "ped", entry.id)
        if index then table.remove(scene.data.peds, index) end
        Interact.remove(session, "ped", entry.id)
        scene.peds[entry.id] = nil
        if isElement(ped) then destroyElement(ped) end
        Editor.markDirty(session)
        return true
    end,
}

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    local info = menus[menuId]
    if not info or type(value) ~= "table" then return end
    local session = info.session
    if source ~= session.player or Editor.sessions[source] ~= session or not session.scene then return end
    local entry = Editor.findEntry(session.scene, info.kind, info.id)
    local element = entry and (info.kind == "vehicle" and session.scene.vehicles[entry.id] or session.scene.peds[entry.id])
    if not entry or not isElement(element) then return end

    local handler = (info.kind == "vehicle" and VEHICLE or PED)[value.a]
    if not handler then return end
    -- true = handled completely (own refresh / async text input)
    if handler(session, entry, element, value) then return end
    Editor.refreshElement(session, info.kind, entry)
    Editor.markDirty(session)
end)
