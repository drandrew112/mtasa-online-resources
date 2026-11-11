-- Agencies of a scene: one adapter per agency (VSM.AGENCY_ORDER), the rest of the resource only talks to these.
--   running()                         -> bool (its resource runs)
--   freeUnits()                       -> { { id, x, y, z, interior, accounts }, ... }
--   create(scene, block, links)       -> taskId | false, error   (block = Storage.agency, links = { ems = id, pd = id })
--   isOpen(taskId)                    -> bool
--   isPending(taskId)                 -> bool (no unit took it yet)
--   close(taskId, reason)
--   link(taskId, otherAgency, otherId)   the tasks of one scene know each other (inter-agency chat, tablet fields)
--   system(taskId, key, params)       system line in the inter-agency channel (v_locals key, resolved per reader)
-- A closed task calls Live.agencyClosed(agency, taskId); a unit taking a task calls Live.agencyTaken(...).
-- A future fire department is one more adapter here.

Agencies = { list = {} }

-- events of the agency resources (they may start after this one: the handlers must attach anyway)
for _, name in ipairs({ "onErmTaskClosed", "onErmTaskAssigned", "onErmUnitStatusChange",
        "onPoliceCallClosed", "onPoliceCallResponded" }) do
    addEvent(name, false)
end

local function register(id, adapter)
    adapter.id = id
    Agencies.list[id] = adapter
end

function Agencies.get(id) return Agencies.list[id] end

-- English texts + the other languages of a block -> title, description, locales (without en)
local function texts(block)
    local en = block.locales.en or {}
    local title, description = en.title or "", en.description or ""
    local others
    for code, e in pairs(block.locales) do
        if code ~= VSM.DEFAULT_LANG then
            others = others or {}
            others[code] = { title = e.title, description = e.description }
        end
    end
    return title, description, others
end

local function call(res, fn, ...)
    if not vsmResourceRunning(res) then return nil end
    local n, args = select("#", ...), { ... }
    local ok, a, b = pcall(function() return exports[res][fn](exports[res], unpack(args, 1, n)) end)
    if not ok then
        vsmLog("%s:%s failed: %s", res, fn, tostring(a))
        return nil
    end
    return a, b
end
Agencies.call = call

---------------------------------------------------------------- EMS (med_erm)

register("ems", {
    running = function() return vsmResourceRunning(VSM.ERM) end,
    freeUnits = function()
        local units = call(VSM.ERM, "getFreeUnits", VSM.AGENCIES.ems.UNIT_TYPES)
        local out = {}
        for _, u in ipairs(type(units) == "table" and units or {}) do
            out[#out + 1] = { id = u.id, x = u.x, y = u.y, z = u.z, accounts = u.accounts }
        end
        return out
    end,
    create = function(scene, block, links)
        local title, description, locales = texts(block)
        local c = scene.center
        local meta = {
            scene = scene.name, sceneInstance = scene.id, priority = block.priority, patients = scene.patients,
            locales = locales, police = links.pd and { call = links.pd } or nil,
            safety = scene.safety and Safety.ermField(scene) or nil,
        }
        return call(VSM.ERM, "createTask", title ~= "" and title or "Medical emergency", description,
            c[1], c[2], c[3], block.caller, nil, meta)
    end,
    isOpen = function(id)
        local t = call(VSM.ERM, "getTask", id)
        return t and t.status ~= "closed" or false
    end,
    isPending = function(id)
        local t = call(VSM.ERM, "getTask", id)
        return t and t.status ~= "closed" and #(t.units or {}) == 0 or false
    end,
    close = function(id, reason)
        local t = call(VSM.ERM, "getTask", id)
        if t and t.status ~= "closed" then call(VSM.ERM, "closeTask", id, reason) end
    end,
    link = function(id, other, otherId)
        if other == "pd" then call(VSM.ERM, "setTaskMetaField", id, "police", { call = otherId }) end
    end,
    setMeta = function(id, key, value) call(VSM.ERM, "setTaskMetaField", id, key, value) end,
    system = function(id, key, params) call(VSM.ERM, "postAgencyMessage", id, false, false, key, params) end,
    units = function(id)
        local t = call(VSM.ERM, "getTask", id)
        return t and t.units or {}
    end,
})

addEventHandler("onErmTaskClosed", root, function(taskId) Live.agencyClosed("ems", taskId) end)
addEventHandler("onErmTaskAssigned", root, function(taskId, unitId)
    local unit = call(VSM.ERM, "getUnitData", unitId)
    Live.agencyTaken("ems", taskId, unit and unit.accounts or {})
end)

---------------------------------------------------------------- PD (police_system)

register("pd", {
    running = function() return vsmResourceRunning(VSM.POLICE) end,
    freeUnits = function()
        local units = call(VSM.POLICE, "getFreeUnits")
        return type(units) == "table" and units or {}
    end,
    create = function(scene, block, links)
        local title, description, locales = texts(block)
        local c = scene.center
        return call(VSM.POLICE, "createSceneCall", {
            title = title, description = description, locales = locales,
            x = c[1], y = c[2], z = c[3], priority = block.priority, caller = VSM.DEFAULT_CALLER,
            meta = { scene = scene.name, instance = scene.id, ermTask = links.ems,
                     category = scene.data and scene.data.category or nil },   -- police_system radio_voice crime word
            safety = scene.safety and Safety.policeInfo(scene) or nil,
        })
    end,
    isOpen = function(id)
        local c = call(VSM.POLICE, "getCall", id)
        return c and c.status ~= "closed" or false
    end,
    isPending = function(id)
        local c = call(VSM.POLICE, "getCall", id)
        return c and c.status == "open" or false
    end,
    close = function(id, reason)
        local c = call(VSM.POLICE, "getCall", id)
        if c and c.status ~= "closed" then call(VSM.POLICE, "closeSceneCall", id, reason) end
    end,
    link = function(id, other, otherId)
        if other == "ems" then call(VSM.POLICE, "setCallLink", id, otherId) end
    end,
    system = function(id, key, params) call(VSM.POLICE, "postCallMessage", id, "agency", false, false, key, params) end,
    -- the officers of the units on the call (players)
    officers = function(id)
        local c = call(VSM.POLICE, "getCall", id)
        return c and c.officers or {}
    end,
    responded = function(id)
        local c = call(VSM.POLICE, "getCall", id)
        return c and #(c.units or {}) > 0 or false
    end,
    setSafety = function(id, info) call(VSM.POLICE, "setCallSafety", id, info) end,
})

addEventHandler("onPoliceCallClosed", root, function(callId) Live.agencyClosed("pd", callId) end)
addEventHandler("onPoliceCallResponded", root, function(callId, _, accounts)
    Live.agencyTaken("pd", callId, accounts or {})
end)

---------------------------------------------------------------- helpers

-- the free units of an agency within its MAX_UNIT_DISTANCE of a point -> nearest unit, distance | nil
function Agencies.nearestFree(id, center, interior, units)
    local a = Agencies.get(id)
    if not a or not a.running() then return nil end
    units = units or a.freeUnits()
    if #units == 0 then return nil end
    if (tonumber(interior) or 0) ~= 0 then return units[1], 0 end
    local maxDist = tonumber(VSM.AGENCIES[id].MAX_UNIT_DISTANCE) or 0
    local best, bestDist
    for _, u in ipairs(units) do
        if u.x and u.y then
            local d = getDistanceBetweenPoints2D(u.x, u.y, center[1], center[2])
            if not bestDist or d < bestDist then best, bestDist = u, d end
        end
    end
    if not best or (maxDist > 0 and bestDist > maxDist) then return nil end
    return best, bestDist
end
