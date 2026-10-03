-- models: model discovery (vehicles, peds, objects) and measured model geometry.
--
-- Names: vehicles -> veh_manager:getModelName (authoritative, falls back to the
-- GTA name); peds / objects -> the model's dff name from the game client
-- (engineGetModelNameFromID, needs the probe). Nothing is invented: fields that
-- cannot be read are omitted.

Models = { measured = {}, catalog = nil, catalogAt = nil, pedNames = nil }

local VEHICLE_MIN, VEHICLE_MAX = 400, 611

function Models.isVehicle(model) return model >= VEHICLE_MIN and model <= VEHICLE_MAX end

local validPeds
function Models.validPeds()
    if not validPeds then
        validPeds = {}
        for _, id in ipairs(getValidPedModels()) do validPeds[id] = true end
    end
    return validPeds
end

function Models.typeOf(model)
    if Models.isVehicle(model) then return "vehicle" end
    if Models.validPeds()[model] then return "ped" end
    return "object"
end

local function handlingSummary(model)
    local h = getOriginalHandling(model)
    if not h then return nil end
    return {
        mass = h.mass, turnMass = h.turnMass, dragCoeff = h.dragCoeff,
        maxVelocity = h.maxVelocity, engineAcceleration = h.engineAcceleration,
        numberOfGears = h.numberOfGears, driveType = h.driveType, engineType = h.engineType,
        centerOfMass = h.centerOfMass, seatOffsetDistance = h.seatOffsetDistance,
        modelFlags = h.modelFlags, handlingFlags = h.handlingFlags,
    }
end

local function maxPassengers(model)
    local ok, n = pcall(getVehicleMaxPassengers, model)
    if ok and type(n) == "number" then return n end
    return nil
end

function Models.vehicleRecord(model, full)
    local name, source = Util.vehicleName(model)
    if not name then return nil end
    local r = {
        model = model, type = "vehicle", name = name, nameSource = source,
        gtaName = getVehicleNameFromModel(model),
        category = getVehicleType(model),
        maxPassengers = maxPassengers(model),
    }
    local m = Models.measured["vehicle:" .. model]
    if m then r.dimensions = m.size end
    if full then
        r.handling = handlingSummary(model)
        if m then r.measured = m end
    end
    return r
end

-- measured geometry (cached): bbox, size, base distance, dummies...
function Models.measure(typ, model, force)
    local key = typ .. ":" .. model
    if Models.measured[key] and not force then return Models.measured[key] end
    local r = Probe.call("measureModel", { type = typ, model = model }, 12000)
    Models.measured[key] = r
    return r
end

-- cached measure that does not wait: returns nil when unknown
function Models.cached(typ, model)
    return Models.measured[typ .. ":" .. model]
end

-- dff names of every model id (one probe round trip, cached)
function Models.loadCatalog(force)
    if Models.catalog and not force then return Models.catalog end
    local r = Probe.call("modelNames", { from = 0, to = 19999 }, 30000)
    local cat = { byId = {}, objects = {}, peds = {}, weapons = {} }
    local peds = Models.validPeds()
    for _, entry in ipairs(r.names or {}) do
        local id, name = entry[1], entry[2]
        cat.byId[id] = name
        if peds[id] then
            cat.peds[#cat.peds + 1] = id
        elseif id >= 321 and id <= 372 then
            cat.weapons[#cat.weapons + 1] = id
        elseif not Models.isVehicle(id) then
            cat.objects[#cat.objects + 1] = id
        end
    end
    Models.catalog = cat
    Models.catalogAt = getRealTime().timestamp
    return cat
end

function Models.dffName(model)
    if Models.catalog then return Models.catalog.byId[model] end
    return nil
end

function Models.pedRecord(model)
    local r = { model = model, type = "ped", sex = pedSex(model), sexSource = PED_SEX_SOURCE }
    local dff = Models.dffName(model)
    if dff then r.dffName = dff end
    local m = Models.measured["ped:" .. model]
    if m then r.dimensions = m.size end
    return r
end

---------------------------------------------------------------- API

Api.register("models", "vehicles", function(p)
    local out = {}
    local q = p.search and tostring(p.search):lower()
    local cat = p.category and tostring(p.category):lower()
    for model = VEHICLE_MIN, VEHICLE_MAX do
        local r = Models.vehicleRecord(model, false)
        if r then
            local ok = true
            if q and not (r.name:lower():find(q, 1, true) or (r.gtaName or ""):lower():find(q, 1, true) or tostring(model) == q) then ok = false end
            if cat and (r.category or ""):lower() ~= cat then ok = false end
            if ok then out[#out + 1] = r end
        end
    end
    local cats = {}
    for model = VEHICLE_MIN, VEHICLE_MAX do
        local c = getVehicleType(model)
        if c then cats[c] = (cats[c] or 0) + 1 end
    end
    return { count = #out, vehicles = out, categories = cats, nameSource = Util.resourceRunning("veh_manager") and "veh_manager:getModelName" or "getVehicleNameFromModel (veh_manager not running)" }
end, { desc = "Vehicle models with names (veh_manager), category, seats; filter by search/category." })

Api.register("models", "peds", function(p)
    local sex = p.sex and P.str(p, "sex", nil, { "male", "female" })
    if p.withNames ~= false and Probe.get() and not Models.catalog then Models.loadCatalog() end
    local ids = {}
    for id in pairs(Models.validPeds()) do ids[#ids + 1] = id end
    table.sort(ids)
    local male, female = {}, {}
    for _, id in ipairs(ids) do
        local r = Models.pedRecord(id)
        if r.sex == "female" then female[#female + 1] = r else male[#male + 1] = r end
    end
    local out = { sexSource = PED_SEX_SOURCE, namesAvailable = Models.catalog ~= nil }
    if sex == "male" then out.male = male out.count = #male
    elseif sex == "female" then out.female = female out.count = #female
    else out.male, out.female, out.count = male, female, #male + #female end
    return out
end, { async = true, desc = "Valid ped models split into male / female, with dff names." })

Api.register("models", "objects", function(p)
    local cat = Models.loadCatalog(p.refresh == true)
    local q = p.search and tostring(p.search):lower()
    local limit = P.int(p, "limit", 100, 1, 2000)
    local from, to = P.int(p, "from", 0), P.int(p, "to", 19999)
    local out, total = {}, 0
    for _, id in ipairs(cat.objects) do
        local name = cat.byId[id]
        if id >= from and id <= to and (not q or name:lower():find(q, 1, true)) then
            total = total + 1
            if #out < limit then
                out[#out + 1] = { model = id, type = "object", dffName = name, kind = modelKind(name), kindSource = "name_heuristic" }
            end
        end
    end
    return { total = total, returned = #out, objects = out, catalogSize = #cat.objects }
end, { async = true, desc = "Object models by dff-name search / id range." })

Api.register("models", "search", function(p)
    local q = tostring(P.str(p, "query")):lower()
    local typ = p.type and P.str(p, "type", nil, { "vehicle", "ped", "object", "any" }) or "any"
    local limit = P.int(p, "limit", 40, 1, 500)
    local out = {}
    if typ == "any" or typ == "vehicle" then
        for model = VEHICLE_MIN, VEHICLE_MAX do
            local r = Models.vehicleRecord(model, false)
            if r and (r.name:lower():find(q, 1, true) or (r.gtaName or ""):lower():find(q, 1, true) or (r.category or ""):lower() == q) then
                out[#out + 1] = r
            end
        end
    end
    if (typ ~= "vehicle") and Probe.get() then
        local cat = Models.loadCatalog()
        if typ == "any" or typ == "ped" then
            for _, id in ipairs(cat.peds) do
                local name = cat.byId[id]
                if name:lower():find(q, 1, true) or pedSex(id) == q then out[#out + 1] = Models.pedRecord(id) end
            end
        end
        if typ == "any" or typ == "object" then
            for _, id in ipairs(cat.objects) do
                local name = cat.byId[id]
                if name:lower():find(q, 1, true) then
                    out[#out + 1] = { model = id, type = "object", dffName = name, kind = modelKind(name), kindSource = "name_heuristic" }
                end
                if #out >= limit * 3 then break end
            end
        end
    end
    local total = #out
    while #out > limit do table.remove(out) end
    return { query = q, total = total, returned = #out, results = out,
        note = (typ ~= "vehicle" and not Probe.get()) and "Ped/object names need a probe client; only vehicles were searched." or nil }
end, { async = true, desc = "Search vehicle names, ped / object dff names." })

-- info: { model, type?, measure = true }
Api.register("models", "info", function(p)
    local model = P.int(p, "model")
    local typ = p.type and P.str(p, "type", nil, { "vehicle", "ped", "object" }) or Models.typeOf(model)
    local r
    if typ == "vehicle" then
        r = Models.vehicleRecord(model, true)
        if not r then fail("MODEL_NOT_FOUND", "Vehicle model " .. model .. " could not be resolved.", { suggestion = "Valid vehicle ids are 400-611; see get_vehicle_models." }) end
    elseif typ == "ped" then
        if not Models.validPeds()[model] then fail("MODEL_NOT_FOUND", "Ped model " .. model .. " is not a valid skin.", { suggestion = "See get_ped_models." }) end
        if Probe.get() and not Models.catalog then Models.loadCatalog() end
        r = Models.pedRecord(model)
    else
        if Probe.get() and not Models.catalog then Models.loadCatalog() end
        local name = Models.dffName(model)
        if Models.catalog and not name then
            fail("MODEL_NOT_FOUND", "Object model " .. model .. " has no model name in the game (not a valid model id).", { suggestion = "Search with search_models." })
        end
        r = { model = model, type = "object", dffName = name, kind = name and modelKind(name) or nil, kindSource = name and "name_heuristic" or nil }
    end
    if p.measure ~= false and Probe.get() then
        r.measured = Models.measure(typ, model, p.refresh == true)
        r.dimensions = r.measured.size
    elseif not Probe.get() then
        r.measured = nil
        r.note = "Dimensions need a probe client."
    end
    return r
end, { async = true, desc = "One model: names, category, handling, measured bounds / size / dummies." })

Api.register("models", "measure", function(p)
    local model = P.int(p, "model")
    local typ = p.type and P.str(p, "type", nil, { "vehicle", "ped", "object" }) or Models.typeOf(model)
    return Models.measure(typ, model, p.refresh == true)
end, { async = true, desc = "Measured bounding box of a model (cached)." })
