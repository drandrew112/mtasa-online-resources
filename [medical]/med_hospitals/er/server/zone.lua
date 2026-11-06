-- ER zone (hospitals.json er.zone, a colshape): patients brought in by somebody (not handed over by an
-- EMS crew) and left there are "not registered" until a staff member admits them (K6). They show in
-- the HIS patient list and get a "Felvétel" item in their interaction menu.

local zones = {}      -- [hospitalId] = colshape
local regMenus = {}   -- [ped] = menu id
local regPed = {}     -- [menu id] = ped
local tokens = {}     -- [token] = ped (HIS rows)
local nextToken = 1

local function io() return ER.running("ui_interactobject") and exports.ui_interactobject or nil end
local function eq() return ER.running("med_equipments") and exports.med_equipments or nil end

local oldBuild = ER.buildHospital
ER.buildHospital = function(e)
    if oldBuild then oldBuild(e) end
    local z = e.cfg.zone
    if not z then return end
    local x1, y1, z1 = math.min(z.from.x, z.to.x), math.min(z.from.y, z.to.y), math.min(z.from.z, z.to.z)
    local col = ER.track(createColCuboid(x1, y1, z1, math.abs(z.to.x - z.from.x), math.abs(z.to.y - z.from.y), math.abs(z.to.z - z.from.z)))
    if col then
        setElementInterior(col, e.h.interior)
        setElementDimension(col, e.h.dimension)
        zones[e.h.id] = col
    end
end

-- a ped that may be registered: a medical patient (medsys status), not a case yet, not on an EMS stretcher
-- (an ambulance crew is still bringing it to the handover point), not a player
local function candidate(ped)
    if not isElement(ped) or getElementType(ped) ~= "ped" or ER.cases[ped] then return false end
    if not getElementData(ped, "medic.status") then return false end
    local m = eq()
    local st = m and m:getPatientStretcher(ped)
    if st and not m:isHospitalStretcher(st) then return false end
    return true
end

function ER.unregistered(hid)
    local col = zones[hid]
    local out = {}
    if not isElement(col) then return out end
    for _, ped in ipairs(getElementsWithinColShape(col, "ped")) do
        if candidate(ped) then out[#out + 1] = ped end
    end
    return out
end

-- HIS rows of the not registered patients (token = what the client sends back to admit one)
function ER.unregisteredRows(hid)
    local rows = {}
    for _, ped in ipairs(ER.unregistered(hid)) do
        local token
        for t, p in pairs(tokens) do if p == ped then token = t end end
        if not token then token = "u" .. nextToken nextToken = nextToken + 1 tokens[token] = ped end
        local m = ER.running("medsys") and exports.medsys:getMedicalState(ped) or {}
        rows[#rows + 1] = { token = token, dead = m.dead or false, consciousness = m.consciousness,
                            gender = (ER.running("police_system") and exports.police_system:getSkinGender(getElementModel(ped)) == "f") and "female" or "male" }
    end
    return rows
end

function ER.register(hid, player, ped)
    if not candidate(ped) or not isElement(zones[hid]) or not isElementWithinColShape(ped, zones[hid]) then return false end
    local c = ER.createCase(ped, hid, { kind = "brought", at = getRealTime().timestamp })
    local m = eq()
    local st = m and m:getPatientStretcher(ped)
    c.location = st and "corridor" or "floor"
    ER.points(player, "HK-A02", 2, L.forPlayer(player, "med_docs.code.hk_a02"), c)
    ER.log(c, "register", "", player)
    ER.syncCase(c)
    ER.notify(player, L.forPlayer(player, "med_hospitals.er.registered"))
    return c
end

function ER.registerToken(hid, player, token)
    local ped = tokens[token]
    tokens[token] = nil
    return ped and ER.register(hid, player, ped)
end

-- interaction menus on the not registered patients (every 3 s)
setTimer(function()
    local api = io()
    if not api then return end
    local seen = {}
    for hid, col in pairs(zones) do
        local staff = ER.staff(hid)
        if isElement(col) and #staff > 0 then
            for _, ped in ipairs(ER.unregistered(hid)) do
                seen[ped] = true
                local def = { title = L.msg("med_hospitals.er.unregistered_title"), range = 3.0, priority = 14, lineOfSight = false,
                              items = { { label = L.msg("med_hospitals.er.register"), value = "register:" .. hid, desc = L.msg("med_hospitals.er.register_desc") } } }
                if regMenus[ped] then
                    api:setInteractMenuVisibleTo(regMenus[ped], staff)
                else
                    local id = api:addInteractMenu(ped, def, staff)
                    if id then regMenus[ped], regPed[id] = id, ped end
                end
            end
        end
    end
    for ped, id in pairs(regMenus) do
        if not seen[ped] then
            regMenus[ped], regPed[id] = nil, nil
            api:removeInteractMenu(id)
        end
    end
    for t, ped in pairs(tokens) do if not isElement(ped) or ER.cases[ped] then tokens[t] = nil end end
end, 3000, 0)

addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local ped = regPed[menuId]
    if not ped then return end
    local hid = tostring(value):match("^register:(.+)$")
    if not hid or not ER.isStaff(source, hid) then return end
    if ER.register(hid, source, ped) then
        regMenus[ped], regPed[menuId] = nil, nil
        local api = io()
        if api then api:removeInteractMenu(menuId) end
    end
end)

-- export (read only, tests / admin tools): a summary of an ER
function getERState(hospitalId)
    local cases = {}
    for _, c in pairs(ER.cases) do
        if c.hospital == hospitalId then
            cases[#cases + 1] = { id = c.id, name = c.name, triage = c.triage, status = c.status, location = c.location,
                                  outcome = c.outcome or false, orders = #(c.orders or {}), results = #(c.results or {}),
                                  findings = #(c.findings or {}), ped = c.ped }
        end
    end
    local stock = ER.stockView and ER.stockView(hospitalId) or {}
    return { active = ER.active(hospitalId), staff = #ER.staff(hospitalId), cases = cases,
             unregistered = #ER.unregistered(hospitalId), corridorFree = ER.freeCorridorCount(hospitalId),
             stockCost = stock.cost, dbReady = ERDB and ERDB.ready or false, nextId = ER.nextId }
end
