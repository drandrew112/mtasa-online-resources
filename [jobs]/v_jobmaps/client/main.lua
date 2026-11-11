-- v_jobmaps (client): builds a job map when the server asks for it and removes it again on unload.
--
-- Load (one step per STEP_DELAY ms so the game does not freeze): every texture archive once, then per custom
-- model a new object model id (engineRequestModel) with its col / txd / dff, then the objects and the
-- world model removals, then the server is told the map is ready. Several dffs may share one txd: the
-- archive is loaded once and imported into every model.
-- Unload: objects destroyed, removals restored, model ids freed, files released. Nothing of a map is
-- in the game while it is not loaded, so the normal world is untouched.

local jobMaps = {}   -- name -> { token, ready, payload, txd = { key = element }, models = { name = { id, col, dff } }, objects, removed }

addEvent(EV_LOAD, true)
addEvent(EV_UNLOAD, true)
addEvent("onClientJobMapProgress")   -- (name, done, total)
addEvent("onClientJobMapReady")      -- (name)
addEvent("onClientJobMapFailed")     -- (name, reason)

local function resPath(p) return p end

---------------------------------------------------------------------------- freeing

local function destroyObjects(m)
    for _, o in ipairs(m.objects) do
        if isElement(o) then destroyElement(o) end
    end
    m.objects = {}
    for _, r in ipairs(m.removed) do
        restoreWorldModel(r[1], r[3], r[4], r[5], r[6], r[7])
        if r[2] and r[2] > 0 and r[2] ~= r[1] then restoreWorldModel(r[2], r[3], r[4], r[5], r[6], r[7]) end
    end
    m.removed = {}
end

-- minimap track image in v_radar (interiors/jobmaps.json, id = map name); silently nothing when the map has none
local function radarImage(name, enabled, opts)
    local radar = getResourceFromName("v_radar")
    if not radar or getResourceState(radar) ~= "running" then return end
    pcall(function() exports.v_radar:setJobMapImage(name, enabled, opts) end)
end

local function freeMap(name)
    local m = jobMaps[name]
    if not m then return end
    jobMaps[name] = nil
    radarImage(name, false)
    m.token = nil
    destroyObjects(m)
    for _, md in pairs(m.models) do
        if md.id then engineFreeModel(md.id) end
        if md.col and isElement(md.col) then destroyElement(md.col) end
        if md.dff and isElement(md.dff) then destroyElement(md.dff) end
    end
    for _, t in pairs(m.txd) do
        if isElement(t) then destroyElement(t) end
    end
end

local function fail(name, reason)
    outputDebugString("[v_jobmaps] " .. name .. ": " .. tostring(reason), 1)
    freeMap(name)
    triggerEvent("onClientJobMapFailed", localPlayer, name, tostring(reason))
    triggerServerEvent(EV_FAILED, resourceRoot, name, tostring(reason))
end

---------------------------------------------------------------------------- objects

local function buildObjects(m)
    destroyObjects(m)
    local p = m.payload
    local o = p.opts
    local ox, oy, oz = o.offset[1], o.offset[2], o.offset[3]

    for _, r in ipairs(p.removes) do
        removeWorldModel(r[1], r[3], r[4] + ox, r[5] + oy, r[6] + oz, r[7])
        if r[2] and r[2] > 0 and r[2] ~= r[1] then removeWorldModel(r[2], r[3], r[4] + ox, r[5] + oy, r[6] + oz, r[7]) end
        m.removed[#m.removed + 1] = { r[1], r[2], r[3], r[4] + ox, r[5] + oy, r[6] + oz, r[7] }
    end

    for _, rec in ipairs(p.objects) do
        local model = rec[1]
        local def = nil
        if type(model) == "string" then
            def = m.models[model]
            model = def and def.id
        end
        if model then
            local obj = createObject(model, rec[2] + ox, rec[3] + oy, rec[4] + oz, rec[5], rec[6], rec[7])
            if obj then
                local interior = rec[8] ~= 0 and rec[8] or o.interior
                if interior ~= 0 then setElementInterior(obj, interior) end
                if o.dimension ~= 0 then setElementDimension(obj, o.dimension) end
                if rec[9] ~= 1 then setObjectScale(obj, rec[9]) end
                if rec[10] ~= 255 then setElementAlpha(obj, rec[10]) end
                if rec[11] == 0 then setElementCollisionsEnabled(obj, false) end
                local double = rec[12] == 1 or (rec[12] == -1 and def and def.doublesided)
                if double then setElementDoubleSided(obj, true) end
                if def then setObjectBreakable(obj, false) end
                if rec[13] == 1 or def then setElementFrozen(obj, true) end
                m.objects[#m.objects + 1] = obj
            end
        end
    end
end

---------------------------------------------------------------------------- load steps

local function startLoad(payload)
    local name = payload.name
    local existing = jobMaps[name]
    if existing then
        -- asked again: only the options change, the models stay
        existing.payload.opts = payload.opts
        if existing.ready then
            buildObjects(existing)
            radarImage(name, true, payload.opts)
            triggerServerEvent(EV_READY, resourceRoot, name)
        end
        return
    end

    local m = { token = {}, ready = false, payload = payload, txd = {}, models = {}, objects = {}, removed = {} }
    jobMaps[name] = m

    -- the steps: { "txd", key } ... { "model", modelName } ... { "objects" }
    local steps = {}
    local txdKeys, modelNames = {}, {}
    for key in pairs(payload.txds) do txdKeys[#txdKeys + 1] = key end
    for mn in pairs(payload.models) do modelNames[#modelNames + 1] = mn end
    table.sort(txdKeys)
    table.sort(modelNames)
    for _, k in ipairs(txdKeys) do steps[#steps + 1] = { "txd", k } end
    for _, mn in ipairs(modelNames) do steps[#steps + 1] = { "model", mn } end
    steps[#steps + 1] = { "objects" }

    local token = m.token
    local index = 0

    local function run()
        if jobMaps[name] ~= m or m.token ~= token then return end   -- unloaded meanwhile
        index = index + 1
        local s = steps[index]
        if not s then return end

        if s[1] == "txd" then
            local txd = engineLoadTXD(resPath(("maps/%s/%s"):format(name, payload.txds[s[2]])))
            if not txd then return fail(name, "texture archive " .. payload.txds[s[2]] .. " could not be loaded") end
            m.txd[s[2]] = txd
        elseif s[1] == "model" then
            local d = payload.models[s[2]]
            local base = ("maps/%s/"):format(name)
            local md = {}
            m.models[s[2]] = md   -- registered first so a failure frees what exists
            md.id = engineRequestModel("object", JOBMAPS.PARENT_MODEL)
            if not md.id then return fail(name, "no free object model id for " .. s[2]) end
            md.col = engineLoadCOL(resPath(base .. d.col))
            md.dff = engineLoadDFF(resPath(base .. d.dff))
            if not md.col or not md.dff then return fail(name, "files of model " .. s[2] .. " could not be loaded") end
            md.doublesided = d.doublesided
            engineReplaceCOL(md.col, md.id)
            engineImportTXD(m.txd[d.txd], md.id)
            engineReplaceModel(md.dff, md.id, d.alpha)
            pcall(engineSetModelLODDistance, md.id, d.distance)
        else
            buildObjects(m)
            radarImage(name, true, payload.opts)
            m.ready = true
            triggerEvent("onClientJobMapProgress", localPlayer, name, #steps, #steps)
            triggerEvent("onClientJobMapReady", localPlayer, name)
            triggerServerEvent(EV_READY, resourceRoot, name)
            return
        end
        triggerEvent("onClientJobMapProgress", localPlayer, name, index, #steps)
        setTimer(run, JOBMAPS.STEP_DELAY, 1)
    end

    setTimer(run, JOBMAPS.STEP_DELAY, 1)
end

addEventHandler(EV_LOAD, resourceRoot, function(payload)
    if type(payload) ~= "table" or not payload.name then return end
    startLoad(payload)
end)

addEventHandler(EV_UNLOAD, resourceRoot, function(name)
    freeMap(tostring(name))
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent(EV_REQUEST, resourceRoot)
end)

-- v_radar (re)started: give it the images of the maps that are built
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) ~= "v_radar" then return end
    for name, m in pairs(jobMaps) do
        if m.ready then radarImage(name, true, m.payload.opts) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    local names = {}
    for name in pairs(jobMaps) do names[#names + 1] = name end
    for _, name in ipairs(names) do freeMap(name) end
end)

---------------------------------------------------------------------------- exports

-- -> { name, ... } of the maps asked for (also those still loading)
function getLoadedJobMaps()
    local out = {}
    for name in pairs(jobMaps) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function isJobMapReady(name)
    return jobMaps[name] ~= nil and jobMaps[name].ready == true
end
