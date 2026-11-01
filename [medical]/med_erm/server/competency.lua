if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Crew competencies (work_core, registered by work_ems: Config.COMPETENCY_WORK).
--   which unit types a crew may sign in as: at least one member with Config.UNIT_COMPETENCY[type]
--   the unit loses the member that qualified it: "unqualified", it takes no new case until it signs in again
--   the equipment level of the unit's vehicle (med_equipments, Config.UNIT_EQUIPMENT) at sign-in / sign-out

Competency = {}

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function defs()
    if not running("work_core") then return nil end
    local d = exports.work_core:getCompetencyDefs(Config.COMPETENCY_WORK)
    return type(d) == "table" and d or nil
end

-- Display name of a competency id (the id itself without work_core)
function Competency.name(id)
    local d = defs()
    return d and d[id] and d[id].name or tostring(id)
end

-- Does any member qualify the crew for the unit type -> true | false, needed competency name
function Competency.crewAllows(members, unitType)
    local need = Config.UNIT_COMPETENCY[unitType]
    if not need or not defs() then return true end
    for _, p in ipairs(members) do
        if isElement(p) and exports.work_core:hasCompetency(p, Config.COMPETENCY_WORK, need) then return true end
    end
    return false, Competency.name(need)
end

-- The highest rank in the crew: short name (dispatcher list) | ""
function Competency.crewBest(members)
    local d = defs()
    if not d then return "" end
    local best, bestOrder = "", 0
    for _, p in ipairs(members) do
        if isElement(p) then
            local id, order = exports.work_core:getPlayerCompetency(p, Config.COMPETENCY_WORK)
            if id and (order or 0) > bestOrder and d[id] then best, bestOrder = d[id].short, order end
        end
    end
    return best
end

-- After a member left: is the unit still qualified for its type?
function Competency.recheck(u)
    if u.unqualified then return end
    local ok, need = Competency.crewAllows(u.members, u.type)
    if ok then return end
    u.unqualified = true
    Units.notify(u, L.msg("med_erm.competency.unit_not_qualified_title"),
        L.msg("med_erm.competency.unit_not_qualified", { type = u.type, need = need }), true)
end

---------------------------------------------------------------- equipment

local function setLevel(vehicle, level)
    if not isElement(vehicle) or not running("med_equipments") then return end
    -- only vehicles that carry EMS equipment at all (work_ems duty vehicles, the tutorial ambulance)
    if not exports.med_equipments:getVehicleEquipment(vehicle) then return end
    exports.med_equipments:setVehicleEquipment(vehicle, level)
end

function Competency.equip(u)
    local level = Config.UNIT_EQUIPMENT[u.type]
    if level then setLevel(u.vehicle, level) end
end

function Competency.unequip(u)
    setLevel(u.vehicle, Config.EQUIPMENT_SIGNED_OUT)
end
