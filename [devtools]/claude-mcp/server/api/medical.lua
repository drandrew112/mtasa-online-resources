-- medical: medical scene module on top of the generic workspace / entity /
-- placement / validation layers. A medical scene is a workspace of kind
-- "medical" whose meta holds the ERM task data. Patients are peds with
-- meta.role = "patient" and meta.medical = { anim, injuries, state }.
--
-- Catalog data (poses, injuries, state keys, damage presets) comes from
-- med_scenemanager (exports.med_scenemanager:getCatalog); export / save / live
-- spawning go through its exports as well. medsys is only touched when a
-- patient is explicitly simulated.

Medical = {}

local MSM = "med_scenemanager"

function Medical.catalog()
    if not Util.resourceRunning(MSM) then
        fail("DEPENDENCY_NOT_RUNNING", "med_scenemanager is not running.", { retryable = true, suggestion = "start med_scenemanager (it needs med_erm and medsys)" })
    end
    local ok, cat = pcall(function() return exports[MSM]:getCatalog() end)
    if not ok or type(cat) ~= "table" then
        fail("DEPENDENCY_OUTDATED", "med_scenemanager has no getCatalog export.", { suggestion = "Update med_scenemanager (exports.lua getCatalog / saveSceneData)." })
    end
    return cat
end

local function animDef(cat, id)
    for _, a in ipairs(cat.anims or {}) do if a.id == id then return a end end
    return nil
end

function Medical.applyAnim(ped, cat, id)
    if getPedOccupiedVehicle(ped) then return end
    local def = animDef(cat, id)
    if not def then fail("INVALID_PARAMS", "Unknown patient pose '" .. tostring(id) .. "'; see medical_get_catalog().anims.") end
    if def.anim then
        setPedAnimation(ped, def.anim[1], def.anim[2], -1, def.loop == true, false, false, true)
    else
        setPedAnimation(ped)
    end
end

local function validateInjuries(cat, injuries)
    local out = {}
    local known = {}
    for _, i in ipairs(cat.injuries or {}) do known[i.id] = true end
    for _, inj in ipairs(type(injuries) == "table" and injuries or {}) do
        local typ = inj.type or inj[1]
        local sev = math.floor(tonumber(inj.severity or inj[2]) or 0)
        if not known[typ] then fail("INVALID_PARAMS", "Unknown injury type '" .. tostring(typ) .. "'; see medical_get_catalog().injuries.") end
        if sev < 1 or sev > 3 then fail("INVALID_PARAMS", "Injury severity must be 1 (minor), 2 (serious) or 3 (critical).") end
        out[#out + 1] = { type = typ, severity = sev }
    end
    return out
end

local function validateState(cat, state)
    if state == nil then return {} end
    if type(state) ~= "table" then fail("INVALID_PARAMS", "state must be an object of medsys keys.") end
    local out = {}
    for k, v in pairs(state) do
        local def = cat.state and cat.state[k]
        if not def then fail("INVALID_PARAMS", "Unknown state key '" .. tostring(k) .. "'; valid: " .. table.concat(cat.stateOrder or {}, ", ")) end
        if def.min and tonumber(v) and (tonumber(v) < def.min or tonumber(v) > def.max) then
            fail("INVALID_PARAMS", string.format("state.%s = %s is outside %s..%s.", k, tostring(v), def.min, def.max))
        end
        out[k] = v
    end
    return out
end

local function sceneWorkspace(name)
    local ws = Registry.requireWorkspace(name)
    if ws.kind ~= "medical" then
        fail("NOT_A_MEDICAL_SCENE", "Workspace '" .. ws.name .. "' is not a medical scene (kind " .. ws.kind .. ").", { suggestion = "Create one with medical_create_scene." })
    end
    return ws
end

local function pickSkin(cat, sex)
    local pool = {}
    for _, s in ipairs(cat.pedSkins or {}) do
        if not sex or pedSex(s) == sex then pool[#pool + 1] = s end
    end
    if #pool == 0 then
        for id in pairs(Models.validPeds()) do
            if id > 0 and (not sex or pedSex(id) == sex) then pool[#pool + 1] = id end
        end
    end
    return pool[math.random(#pool)]
end

---------------------------------------------------------------- API

Api.register("medical", "catalog", function()
    local cat = Medical.catalog()
    cat.medsys = Util.resourceRunning("medsys") and "running" or "not running"
    cat.med_erm = Util.resourceRunning("med_erm") and "running" or "not running"
    cat.genericPoses = CMCP.POSES
    return cat
end, { desc = "Injuries, severities, patient poses, medsys state keys + presets, damage presets (from med_scenemanager)." })

-- createScene: { name, center, radius, erm = { title, description, caller, priority }, dimension, enabled, weight }
Api.register("medical", "createScene", function(p)
    local cat = Medical.catalog()
    local x, y, z = Resolve.point(p.center, "center")
    local erm = type(p.erm) == "table" and p.erm or {}
    local defaults = cat.defaultErm or {}
    local ws = Registry.createWorkspace({
        name = P.str(p, "name"), kind = "medical", dimension = p.dimension, interior = p.interior,
        center = M.vec(x, y, z), radius = P.num(p, "radius", 40, 5, 300),
        description = erm.description or p.description,
        meta = {
            erm = {
                title = tostring(erm.title or defaults.title or "Medical emergency"),
                description = tostring(erm.description or defaults.description or ""),
                caller = tostring(erm.caller or defaults.caller or "SceneManager"),
                priority = math.max(1, math.min(4, math.floor(tonumber(erm.priority) or defaults.priority or 2))),
            },
            enabled = p.enabled ~= false, weight = tonumber(p.weight) or 1,
        },
    })
    return { success = true, scene = Registry.workspaceSummary(ws), zone = Util.zone(x, y, z) }
end, { mutates = true, desc = "Creates a medical scene workspace with ERM task data." })

-- addPatient: { scene, id, skin, sex, placement | position + heading, anim, injuries, state, vehicle, seat }
Api.register("medical", "addPatient", function(p)
    local cat = Medical.catalog()
    local ws = sceneWorkspace(p.scene)
    local skin = p.skin and P.int(p, "skin") or pickSkin(cat, p.sex and P.str(p, "sex", nil, { "male", "female" }))
    local injuries = validateInjuries(cat, p.injuries)
    local state = validateState(cat, p.state)
    local anim = p.anim or "ko_back"
    if not animDef(cat, anim) then fail("INVALID_PARAMS", "Unknown patient pose '" .. tostring(anim) .. "'.") end

    local placement = p.placement
    if type(placement) ~= "table" then
        local x, y, z = Resolve.point(p.position or ws.center, "position")
        placement = { mode = "ground", position = { x = x, y = y, z = z }, heading = tonumber(p.heading) or 0 }
    end
    local r = Placement.compute(placement, "ped", skin, nil, ws)
    local entity = Registry.spawn(ws, {
        type = "ped", model = skin, id = p.id, x = r.position.x, y = r.position.y, z = r.position.z, rz = r.rotation.z,
        frozen = p.frozen, placement = r.summary,
        meta = { role = "patient", medical = { anim = anim, injuries = injuries, state = state } },
    })
    local warnings = r.warnings or {}
    if p.vehicle then
        local _, w = Props.apply(entity.element, { seat = { vehicle = p.vehicle, seat = p.seat or 0 } }, entity)
        for _, x in ipairs(w) do warnings[#warnings + 1] = x end
        entity.meta.medical.vehicle = p.vehicle
        entity.meta.medical.seat = tonumber(p.seat) or 0
    else
        Medical.applyAnim(entity.element, cat, anim)
    end
    local out = { success = true, patient = Props.describe(entity.element, "medium"), sex = pedSex(skin), warnings = warnings, placement = r.details }
    if Probe.get() and p.verify ~= false then
        local info = Entities.probeInfo({ entity.element })
        out.patient.live = info and info[1] or nil
    end
    return out
end, { mutates = true, async = true, desc = "Adds an injured ped (pose, injuries, vitals) to a medical scene." })

-- setPatient: { id, anim, injuries (replace), addInjuries, state (merge), clearState }
Api.register("medical", "setPatient", function(p)
    local cat = Medical.catalog()
    local el, entity = Refs.require(P.str(p, "id"))
    if not entity or entity.type ~= "ped" then fail("INVALID_PARAMS", "'" .. p.id .. "' is not a workspace ped.") end
    entity.meta.role = "patient"
    local med = entity.meta.medical or { anim = "ko_back", injuries = {}, state = {} }
    entity.meta.medical = med
    if p.anim then
        Medical.applyAnim(el, cat, p.anim)
        med.anim = p.anim
    end
    if p.injuries then med.injuries = validateInjuries(cat, p.injuries) end
    if p.addInjuries then for _, i in ipairs(validateInjuries(cat, p.addInjuries)) do med.injuries[#med.injuries + 1] = i end end
    if p.clearState then med.state = {} end
    if p.state then for k, v in pairs(validateState(cat, p.state)) do med.state[k] = v end end
    return { success = true, id = entity.id, medical = med }
end, { mutates = true, desc = "Changes a patient's pose / injuries / vitals preset." })

-- addVehicle: { scene, model, placement | position + heading, damage, colors / color, plate, engine, lightsOn, sirens, locked, liveFrozen, role }
Api.register("medical", "addVehicle", function(p)
    local ws = sceneWorkspace(p.scene)
    local model = P.int(p, "model")
    local placement = p.placement
    if type(placement) ~= "table" then
        local x, y, z = Resolve.point(p.position or ws.center, "position")
        placement = { mode = "ground", position = { x = x, y = y, z = z }, heading = tonumber(p.heading) or 0 }
    end
    local r = Placement.compute(placement, "vehicle", model, nil, ws)
    local entity = Registry.spawn(ws, {
        type = "vehicle", model = model, id = p.id, x = r.position.x, y = r.position.y, z = r.position.z,
        rx = r.rotation.x, ry = r.rotation.y, rz = r.rotation.z, placement = r.summary,
        meta = { role = p.role or "involved", liveFrozen = p.liveFrozen == true },
    })
    local props = {
        damage = p.damage or "heavy", engine = p.engine == true, lightsOn = p.lightsOn == true,
        sirens = p.sirens, locked = p.locked == true, plate = p.plate, colors = p.colors, color = p.color,
    }
    local applied, warnings = Props.apply(entity.element, props, entity)
    for _, w in ipairs(r.warnings or {}) do warnings[#warnings + 1] = w end
    local out = { success = true, vehicle = Props.describe(entity.element, "high"), applied = applied, warnings = warnings, placement = r.details }
    if Probe.get() and p.verify ~= false then
        local info = Entities.probeInfo({ entity.element })
        out.vehicle.live = info and info[1] or nil
    end
    return out
end, { mutates = true, async = true, desc = "Adds a (damaged) vehicle to a medical scene." })

-- simulate: { id, enable } applies injuries + state through medsys (starts the simulation on that ped)
Api.register("medical", "simulate", function(p)
    if not Util.resourceRunning("medsys") then fail("DEPENDENCY_NOT_RUNNING", "medsys is not running.") end
    local cat = Medical.catalog()
    local el, entity = Refs.require(P.str(p, "id"))
    local med = entity and entity.meta.medical
    if not med then fail("INVALID_PARAMS", "'" .. p.id .. "' has no medical data (add it with medical_add_patient / medical_set_patient).") end
    if p.enable == false then
        exports.medsys:healCompletely(el)
        return { success = true, id = entity.id, simulated = false }
    end
    for _, inj in ipairs(med.injuries or {}) do exports.medsys:applyInjury(el, inj.type, inj.severity) end
    local resting = cat.stateResting or {}
    for _, key in ipairs(cat.stateOrder or {}) do
        if med.state and med.state[key] ~= nil then exports.medsys:setMedicalState(el, resting[key] or key, med.state[key]) end
    end
    Async.sleep(600)
    return { success = true, id = entity.id, simulated = true, state = Util.jsonSafe(exports.medsys:getMedicalState(el)) }
end, { mutates = true, async = true, desc = "Starts the medsys simulation on a patient (live vitals)." })

Api.register("medical", "patientState", function(p)
    if not Util.resourceRunning("medsys") then fail("DEPENDENCY_NOT_RUNNING", "medsys is not running.") end
    local el, entity = Refs.require(P.str(p, "id"))
    return { id = Refs.of(el), preset = entity and entity.meta.medical, medsys = Util.jsonSafe(exports.medsys:getMedicalState(el)) }
end, { desc = "medsys state of a ped plus its scene preset." })

---------------------------------------------------------------- export / load

local function round(v, d) return M.round(v, d or 3) end

function Medical.toScene(ws, name)
    local vehicles, peds, vehIds = {}, {}, {}
    local sumX, sumY, sumZ, n = 0, 0, 0, 0
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e and isElement(e.element) and e.type == "vehicle" then
            local el = e.element
            local x, y, z = getElementPosition(el)
            local rx, ry, rz = getElementRotation(el)
            local vid = "v" .. (#vehicles + 1)
            vehIds[el] = vid
            local entry = {
                id = vid, model = getElementModel(el),
                pos = { round(x), round(y), round(z) }, rot = { round(rx, 2), round(ry, 2), round(rz, 2) },
                frozen = e.meta.liveFrozen == true, locked = isVehicleLocked(el), engine = getVehicleEngineState(el),
                lightsOn = getVehicleOverrideLights(el) == 2, sirens = getVehicleSirensOn(el) or nil,
                health = math.max(300, math.floor(getElementHealth(el))),
                colors = { getVehicleColor(el, true) }, paintjob = getVehiclePaintjob(el), plate = getVehiclePlateText(el),
                variant = { getVehicleVariant(el) }, upgrades = getVehicleUpgrades(el) or {},
                doors = {}, panels = {}, lights = {}, wheels = { getVehicleWheelStates(el) },
            }
            for i = 0, 5 do entry.doors[i + 1] = getVehicleDoorState(el, i) end
            for i = 0, 6 do entry.panels[i + 1] = getVehiclePanelState(el, i) end
            for i = 0, 3 do entry.lights[i + 1] = getVehicleLightState(el, i) end
            vehicles[#vehicles + 1] = entry
        end
    end
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e and isElement(e.element) and e.type == "ped" then
            local el = e.element
            local x, y, z = getElementPosition(el)
            local _, _, rz = getElementRotation(el)
            local med = e.meta.medical or {}
            local entry = {
                id = "p" .. (#peds + 1), skin = getElementModel(el),
                pos = { round(x), round(y), round(z) }, rot = round(rz, 1),
                anim = med.anim or "none",
                injuries = med.injuries or {}, state = med.state or {},
            }
            local veh = getPedOccupiedVehicle(el)
            if veh and vehIds[veh] then
                entry.vehicle, entry.seat = vehIds[veh], getPedOccupiedVehicleSeat(el)
            end
            if e.meta.role ~= "patient" then entry.injuries, entry.state = {}, {} end
            peds[#peds + 1] = entry
            sumX, sumY, sumZ, n = sumX + x, sumY + y, sumZ + z, n + 1
        end
    end
    local c = ws.center
    if not c and n > 0 then c = { x = sumX / n, y = sumY / n, z = sumZ / n } end
    c = c or { x = 0, y = 0, z = 0 }
    local erm = ws.meta.erm or {}
    return {
        format = 1, name = name, enabled = ws.meta.enabled ~= false, weight = ws.meta.weight or 1,
        center = { round(c.x), round(c.y), round(c.z) }, interior = ws.interior, dimension = 0,
        erm = { title = erm.title, description = erm.description, caller = erm.caller, priority = erm.priority },
        vehicles = vehicles, peds = peds,
    }
end

-- export: { scene, name, save, overwrite }
Api.register("medical", "export", function(p)
    local ws = sceneWorkspace(p.scene)
    local name = P.str(p, "name", ws.name)
    if not name:match("^[%w_%-]+$") or #name > 40 then fail("INVALID_PARAMS", "Scene name: letters, digits, _ and -, max 40.") end
    local scene = Medical.toScene(ws, name)
    local out = { scene = scene, name = name, vehicles = #scene.vehicles, peds = #scene.peds,
        note = "Values read back from the live elements. dimension is exported as 0 (live scenes spawn in the main world)." }
    if ws.dimension ~= 0 then
        out.warnings = { { type = "dimension", message = "The workspace is in dimension " .. ws.dimension .. "; the exported scene uses dimension 0." } }
    end
    if p.save then
        if not Util.resourceRunning(MSM) then fail("DEPENDENCY_NOT_RUNNING", "med_scenemanager is not running.") end
        local ok, saved, err = pcall(function() return exports[MSM]:saveSceneData(name, scene, p.overwrite == true) end)
        if not ok then fail("DEPENDENCY_OUTDATED", "med_scenemanager saveSceneData export failed: " .. tostring(saved)) end
        if not saved then
            fail(err == "exists" and "SCENE_EXISTS" or "SAVE_FAILED", err == "exists" and ("Scene '" .. name .. "' already exists.") or tostring(err),
                { suggestion = err == "exists" and "Pass overwrite = true or another name." or nil })
        end
        out.saved = true
        out.file = "[medical]/med_scenemanager/scenes/" .. name .. ".json"
    end
    return out
end, { desc = "Exports a medical scene in the med_scenemanager JSON format (optionally saves it)." })

-- load: { name, workspace } loads an existing med_scenemanager scene into a medical workspace
Api.register("medical", "load", function(p)
    Medical.catalog()
    local name = P.str(p, "name")
    local data = exports[MSM]:getSceneData(name)
    if not data then fail("SCENE_NOT_FOUND", "med_scenemanager has no scene '" .. name .. "'.", { suggestion = "List scenes with medical_live_scene action 'list'." }) end
    local wsName = p.workspace or ("msm_" .. name)
    if Registry.workspaces[wsName] then fail("WORKSPACE_EXISTS", "Workspace '" .. wsName .. "' already exists.", { suggestion = "clear_workspace it or pass another workspace name." }) end
    local cat = Medical.catalog()
    local c = data.center or { 0, 0, 0 }
    local ws = Registry.createWorkspace({ name = wsName, kind = "medical", dimension = p.dimension, interior = data.interior,
        center = M.vec(c[1], c[2], c[3]), radius = 40, description = data.erm and data.erm.description,
        meta = { erm = data.erm, enabled = data.enabled, weight = data.weight, loadedFrom = name } })
    local vehById, created = {}, {}
    for _, v in ipairs(data.vehicles or {}) do
        local e = Registry.spawn(ws, { type = "vehicle", model = v.model, id = wsName .. "_" .. v.id, x = v.pos[1], y = v.pos[2], z = v.pos[3],
            rx = v.rot[1], ry = v.rot[2], rz = v.rot[3], variant = v.variant, plate = v.plate,
            meta = { role = "involved", liveFrozen = v.frozen == true, sceneId = v.id }, placement = { mode = "loaded" } })
        Props.apply(e.element, { colors = v.colors, health = v.health, doors = v.doors, panels = v.panels, lights = v.lights, wheels = v.wheels,
            engine = v.engine, lightsOn = v.lightsOn, sirens = v.sirens, locked = v.locked, paintjob = v.paintjob ~= 3 and v.paintjob or nil }, e)
        vehById[v.id] = e
        created[#created + 1] = e.id
    end
    for _, pd in ipairs(data.peds or {}) do
        local e = Registry.spawn(ws, { type = "ped", model = pd.skin, id = wsName .. "_" .. pd.id, x = pd.pos[1], y = pd.pos[2], z = pd.pos[3], rz = pd.rot,
            meta = { role = "patient", sceneId = pd.id, medical = { anim = pd.anim, injuries = pd.injuries or {}, state = pd.state or {} } }, placement = { mode = "loaded" } })
        if pd.vehicle and vehById[pd.vehicle] then
            Props.apply(e.element, { seat = { vehicle = vehById[pd.vehicle].id, seat = pd.seat or 0 } }, e)
        else
            Util.try(Medical.applyAnim, e.element, cat, pd.anim or "none")
        end
        created[#created + 1] = e.id
    end
    return { success = true, scene = Registry.workspaceSummary(ws), created = created }
end, { mutates = true, desc = "Loads a med_scenemanager scene file into a medical workspace for editing." })

-- live: { action = list|spawn|remove|files, name, id }
Api.register("medical", "live", function(p)
    if not Util.resourceRunning(MSM) then fail("DEPENDENCY_NOT_RUNNING", "med_scenemanager is not running.") end
    local action = P.str(p, "action", "list", { "list", "files", "spawn", "remove" })
    local msm = exports[MSM]
    if action == "list" then return { active = msm:getActiveScenes() } end
    if action == "files" then return { scenes = msm:getSceneList() } end
    if action == "spawn" then
        local id, warn = msm:spawnScene(P.str(p, "name"))
        if not id then fail("SPAWN_FAILED", tostring(warn)) end
        return { success = true, instanceId = id, warning = warn or nil, note = "A live scene creates a real ERM task." }
    end
    return { success = msm:removeScene(P.int(p, "id")) == true }
end, { mutates = true, desc = "med_scenemanager live scenes: list / files / spawn (creates an ERM task) / remove." })

-- validate: generic validation + medical checks
Api.register("medical", "validate", function(p)
    local cat = Medical.catalog()
    local ws = sceneWorkspace(p.scene)
    local items, patients, vehicles = {}, {}, {}
    for _, id in ipairs(ws.entities) do
        local e = Registry.entities[id]
        if e then
            items[#items + 1] = e
            if e.type == "ped" and e.meta.role == "patient" then patients[#patients + 1] = e end
            if e.type == "vehicle" then vehicles[#vehicles + 1] = e end
        end
    end
    local r = Validation.run(items, ws, { tolerance = p.tolerance })
    local errors, warnings, info = r.errors, r.warnings, r.info
    local erm = ws.meta.erm or {}
    if #patients == 0 then errors[#errors + 1] = { type = "no_patients", message = "The scene has no patient (ped with medical data)." } end
    if not erm.title or erm.title == "" then warnings[#warnings + 1] = { type = "erm_title", message = "ERM task title is empty." } end
    if not erm.description or erm.description == "" then warnings[#warnings + 1] = { type = "erm_description", message = "ERM task description is empty (dispatchers see it)." } end
    for _, e in ipairs(patients) do
        local med = e.meta.medical or {}
        if #(med.injuries or {}) == 0 and next(med.state or {}) == nil then
            warnings[#warnings + 1] = { entity = e.id, type = "no_injuries", message = "Patient has neither injuries nor a medical state; medsys discharges such a patient." }
        end
    end
    -- centre vs patients
    if ws.center and #patients > 0 then
        for _, e in ipairs(patients) do
            if isElement(e.element) then
                local x, y = getElementPosition(e.element)
                local d = M.dist2D(ws.center.x, ws.center.y, x, y)
                if d > 60 then warnings[#warnings + 1] = { entity = e.id, type = "far_from_center", message = string.format("Patient is %.0f m from the ERM centre; units navigate to the centre.", d) } end
            end
        end
    end
    -- EMS access checks on the probe
    local access
    if Probe.get() and #patients > 0 then
        local list = {}
        for _, e in ipairs(patients) do
            if isElement(e.element) and not getPedOccupiedVehicle(e.element) then list[#list + 1] = { element = e.element, id = e.id } end
        end
        if #list > 0 then
            access = Probe.call("medicalAccess", { patients = list, ambulanceModel = tonumber(p.ambulanceModel) or 416 }, 20000)
            for _, d in ipairs(access.errors or {}) do errors[#errors + 1] = d end
            for _, d in ipairs(access.warnings or {}) do warnings[#warnings + 1] = d end
            for _, d in ipairs(access.info or {}) do info[#info + 1] = d end
        end
    end
    r.valid = #errors == 0
    r.errorCount, r.warningCount = #errors, #warnings
    r.medical = { patients = #patients, vehicles = #vehicles, erm = erm, access = access and access.patients or nil }
    r.workspace = ws.name
    return r
end, { async = true, desc = "Generic + medical validation (patients, ERM data, stretcher clearance, access)." })
