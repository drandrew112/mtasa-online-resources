-- ER world interaction: the stretcher point (request / remove a hospital stretcher) and the
-- ui_interactobject menu on every ER patient (triage, treating, patient info). Only the hospital's
-- staff on duty see them.

local PC_MODEL = 2190  -- PC_1 (monitor + keyboard), as in gov_office / biz_int
-- PC_1 is modelled off its pivot (bounding box x -0.711..-0.167, y -0.745..-0.298, measured live):
-- the footprint centre from the pivot at rotation 0. Its bounding box bottom (z 0.279) is wrong: the
-- visible case reaches down to the pivot (screenshot 2026-11-06), so the pivot sits on the desk top.
local PC_CENTRE = { -0.439, -0.5215, 0.0 }
local menus = {}       -- [ped] = menu id
local menuCase = {}    -- [menu id] = ped

local function io() return ER.running("ui_interactobject") and exports.ui_interactobject or nil end

---------------------------------------------------------------- stretcher point

-- the computers on the HIS desks (er.pcs: point on the desk top = middle of the PC, rot = the
-- heading the screen faces)
local function buildPcs(e)
    local h = e.h
    for _, pc in ipairs(e.cfg.pcs or {}) do
        local rz = ((pc.rot or 0) + 180) % 360   -- the PC_1 screen faces the model's -y
        local r = math.rad(rz)
        local cx, cy = PC_CENTRE[1], PC_CENTRE[2]
        local ox, oy = cx * math.cos(r) - cy * math.sin(r), cx * math.sin(r) + cy * math.cos(r)
        local obj = ER.track(createObject(PC_MODEL, pc.x - ox, pc.y - oy, pc.z - PC_CENTRE[3], 0, 0, rz))
        if obj then
            setElementInterior(obj, h.interior)
            setElementDimension(obj, h.dimension)
            setElementFrozen(obj, true)
            setObjectBreakable(obj, false)
            -- synced: the clients find the PCs by this (the [E] hint and HIS.show("pc"))
            setElementData(obj, "hosp.er.pc", h.id)
        end
    end
end

-- Stretcher point (no menu): E inside the marker. Not pushing -> a new hospital stretcher that the
-- player pushes at once; pushing an empty hospital stretcher -> it is handed back (removed).
function ER.buildHospital(e)
    buildPcs(e)
    local p = e.cfg.stretcherPoint
    if not p then return end
    local h = e.h
    local marker = ER.track(createMarker(p.x, p.y, p.z - 0.05, "cylinder", 1.4, 70, 150, 220, ER.MARKER_ALPHA))
    setElementInterior(marker, h.interior)
    setElementDimension(marker, h.dimension)
    setElementData(marker, "hosp.er.stretcherPoint", h.id)
    if ER.running("work_core") then exports.work_core:setElementVisibleToWork(marker, "hospital") end
    e.stretcherMarker = marker
    ER.markerCard(marker, h.id .. ":stretchers", {
        name = h.name or "", title = L.msg("med_hospitals.er.stretcher_point"),
        hint = L.msg("med_hospitals.er.stretcher_point_hint"),
    })
    addEventHandler("onMarkerHit", marker, function(hit, dim)
        if not dim or getElementType(hit) ~= "player" or getPedOccupiedVehicle(hit) then return end
        if not ER.isStaff(hit, h.id) then return end
        triggerClientEvent(hit, "hosp:er:stretcherPoint", resourceRoot, h.id, true)
    end)
    addEventHandler("onMarkerLeave", marker, function(hit)
        if isElement(hit) and getElementType(hit) == "player" then
            triggerClientEvent(hit, "hosp:er:stretcherPoint", resourceRoot, h.id, false)
        end
    end)
end

addEvent("hosp:er:stretcherKey", true)
addEventHandler("hosp:er:stretcherKey", resourceRoot, function(hospitalId)
    local player = client
    local e = ER.byHospital[hospitalId]
    if not e or not ER.isStaff(player, hospitalId) or not isElement(e.stretcherMarker) then return end
    if not isElementWithinMarker(player, e.stretcherMarker) or getPedOccupiedVehicle(player) then return end
    local m = ER.running("med_equipments") and exports.med_equipments
    if not m then return end
    local h = e.h
    local pushed = m:getPusherStretcher(player)
    if pushed then
        -- hand back the pushed stretcher (only an empty hospital one)
        if not m:isHospitalStretcher(pushed) then
            return ER.notify(player, L.forPlayer(player, "med_hospitals.er.stretcher_not_hospital"), true)
        end
        if ER.patientOfStretcher(pushed) then
            return ER.notify(player, L.forPlayer(player, "med_hospitals.er.stretcher_has_patient"), true)
        end
        local ok = m:destroyHospitalStretcher(pushed, true)
        return ER.notify(player, L.forPlayer(player, ok and "med_hospitals.er.stretcher_removed" or "med_hospitals.er.stretcher_failed"), not ok)
    end
    local s = e.cfg.stretcherSpawn or e.cfg.stretcherPoint
    local obj, err = m:createHospitalStretcher(hospitalId, s.x, s.y, s.z, s.rot or 0, h.dimension, h.interior)
    if not obj then
        return ER.notify(player, L.forPlayer(player, err == "limit" and "med_hospitals.er.stretcher_limit" or "med_hospitals.er.stretcher_failed"), true)
    end
    -- the new stretcher settles first (its menu, the clients), then the player takes it
    setTimer(function()
        if not isElement(obj) or not isElement(player) then return end
        if not m:pushHospitalStretcher(obj, player) then
            ER.notify(player, L.forPlayer(player, "med_hospitals.er.stretcher_ready"))
        end
    end, 150, 1)
end)

---------------------------------------------------------------- patient menu

local function menuDef(c)
    local tri = {}
    for level = 1, 4 do
        tri[#tri + 1] = { label = L.msg("med_hospitals.er.triage_level_" .. level), value = "triage" .. level }
    end
    local items = {
        { label = L.msg("med_hospitals.er.menu_exam"), value = "exam", desc = L.msg("med_hospitals.er.menu_exam_desc") },
        { label = L.msg("med_hospitals.er.menu_triage"), title = L.msg("med_hospitals.er.menu_triage"), items = tri },
        { label = L.msg("med_hospitals.er.menu_take_over"), value = "treat", desc = L.msg("med_hospitals.er.menu_take_over_desc") },
        { label = L.msg("med_hospitals.er.menu_info"), value = "info" },
    }
    if c.bed then
        table.insert(items, 1, { label = L.msg("med_hospitals.er.menu_retake"), value = "retake", desc = L.msg("med_hospitals.er.menu_retake_desc") })
    end
    return { title = L.msg("med_hospitals.er.menu_title"), range = 3.0, priority = 15, lineOfSight = false, items = items }
end

local function ensureMenu(c)
    local api = io()
    if not api or not isElement(c.ped) then return end
    local staff = ER.staff(c.hospital)
    if menus[c.ped] then
        api:updateInteractMenu(menus[c.ped], menuDef(c))
        api:setInteractMenuVisibleTo(menus[c.ped], staff)
        return
    end
    local id = api:addInteractMenu(c.ped, menuDef(c), staff)
    if id then menus[c.ped], menuCase[id] = id, c.ped end
end

local function dropMenu(ped)
    local id = menus[ped]
    if not id then return end
    menus[ped], menuCase[id] = nil, nil
    local api = io()
    if api then api:removeInteractMenu(id) end
end

ER.onCaseChanged = function(c) ensureMenu(c) end
ER.onCaseClosed = function(c) dropMenu(c.ped) end

local function refreshVisibility()
    local api = io()
    if not api then return end
    for ped, id in pairs(menus) do
        local c = ER.cases[ped]
        if c then api:setInteractMenuVisibleTo(id, ER.staff(c.hospital)) end
    end
end

addEvent("onPlayerWorkDutyStart")
addEventHandler("onPlayerWorkDutyStart", root, function(workId) if workId == "hospital" then setTimer(refreshVisibility, 100, 1) end end)
addEventHandler("onPlayerWorkDutyEnd", root, function(workId) if workId == "hospital" then setTimer(refreshVisibility, 100, 1) end end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "ui_interactobject" then return end
    menus, menuCase = {}, {}
    for _, c in pairs(ER.cases) do ensureMenu(c) end
end)

addEvent("onInteractMenuSelect")
addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local ped = menuCase[menuId]
    local c = ped and ER.cases[ped]
    local player = source
    if not c or not ER.isStaff(player, c.hospital) then return end
    local level = tostring(value):match("^triage(%d)$")
    if level then
        ER.setTriage(c, tonumber(level), player)
        ER.notify(player, L.forPlayer(player, "med_hospitals.er.triage_set", { name = c.name or "?", level = level }))
    elseif value == "treat" then
        local ok, need = ER.can(player, "er.treat")
        if not ok then return ER.notify(player, L.forPlayer(player, "med_hospitals.er.rank_needed", { rank = need or "?" }), true) end
        if c.triage == 0 then return ER.notify(player, L.forPlayer(player, "med_hospitals.er.triage_first"), true) end
        if c.treating == player then return end
        local first = not c.treating
        ER.setTreating(c, player)
        if c.status == "triaged" or c.status == "waiting" then c.status = "treating" ER.syncCase(c) end
        if first then ER.points(player, "HK-A02", 2, L.forPlayer(player, "med_hospitals.er.code_a02"), c) end
        ER.notify(player, L.forPlayer(player, "med_hospitals.er.you_treat", { name = c.name or "?" }))
    elseif value == "exam" then
        triggerClientEvent(player, "his:openExam", resourceRoot, c.id)
    elseif value == "retake" then
        if ER.retake then ER.retake(c, player) end
    elseif value == "info" then
        local a = c.arrival or {}
        local how = a.kind == "ems" and L.forPlayer(player, "med_hospitals.er.arrived_ems", { unit = a.unit or "?" })
            or L.forPlayer(player, "med_hospitals.er.arrived_" .. tostring(a.kind or "brought"))
        triggerClientEvent(player, "hosp:er:caseInfo", resourceRoot, {
            name = c.name, age = c.age, gender = c.gender, triage = c.triage, treating = c.treatingName,
            arrival = how, text = a.text or "", location = c.location,
        })
    end
end)

-- a ped that got a case while ui_interactobject was not running gets its menu once it runs
addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function() for _, c in pairs(ER.cases) do ensureMenu(c) end end, 1000, 1)
end)
