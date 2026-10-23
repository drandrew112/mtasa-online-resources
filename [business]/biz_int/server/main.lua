if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_int / server/main.lua
-- Entrances, insides (one per unit, created on the first visitor and removed
-- when empty), access control, radar blips of the places a player may enter,
-- and the computer of every inside.
--
-- Server exports:
--   getPlayerUnit(player)            -> unitId | false
--   getPlayersInUnit(unitId)         -> { players }
--   enterUnit(player, unitId)        -> bool (access checked)
--   exitUnit(player)                 -> bool
--   refreshUnitProps(unitId)         -> re-creates the flag dependent props
-- Events (source = player):
--   onPlayerEnterBizUnit (unitId, propertyId, kind, companyId, role)
--   onPlayerExitBizUnit  (unitId, reason)   reason: "exit" | "access" | "removed" | "quit" | "death" | "stop"
--   onBizComputerUse     (unitId)

local BUILD = {}     -- buildingId -> { id, name, x, y, z, rot, marker }
local INST  = {}     -- unitId -> { unitId, dim, template, players = {}, elements = {}, pc, menuId, emptyTimer }
local PU    = {}     -- player -> unitId
local busy  = {}     -- player -> tick of the last transfer
local BLIPS = {}     -- player -> { blips }
local POS   = {}     -- overrides from data/positions.json: POS.templates[id][field], POS.buildings[id]

addEvent("onPlayerEnterBizUnit", false)
addEvent("onPlayerExitBizUnit", false)
addEvent("onBizComputerUse", false)
addEvent("bizint:use", true)
addEvent("bizint:choose", true)
addEvent("biz_core:ready", false)
addEvent("onBizAccessChanged", false)
addEvent("onBizUnitRemoved", false)
addEvent("onInteractMenuSelect", false)

local function core() return exports.biz_core end
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

--------------------------------------------------------------------------------
-- position overrides (/bizpos)
--------------------------------------------------------------------------------

local function loadPositions()
    POS = { templates = {}, buildings = {} }
    if not fileExists(BINT.positionsFile) then return end
    local f = fileOpen(BINT.positionsFile, true)
    if not f then return end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    if type(data) == "table" then
        POS.templates = type(data.templates) == "table" and data.templates or {}
        POS.buildings = type(data.buildings) == "table" and data.buildings or {}
    end
end

local function savePositions()
    if fileExists(BINT.positionsFile) then fileDelete(BINT.positionsFile) end
    local f = fileCreate(BINT.positionsFile)
    if not f then return false end
    fileWrite(f, toJSON({ templates = POS.templates, buildings = POS.buildings }, false, "spaces"))
    fileClose(f)
    return true
end

--- template with the /bizpos overrides applied
local function template(id)
    id = BINT.TEMPLATE_ALIASES[id] or id
    local t = BINT.TEMPLATES[id]
    if not t then return nil end
    local o = POS.templates[id]
    if type(o) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    for _, f in ipairs({ "spawn", "exit", "computer" }) do
        if type(o[f]) == "table" and tonumber(o[f][1]) then copy[f] = o[f] end
    end
    return copy
end

--------------------------------------------------------------------------------
-- buildings (entrances)
--------------------------------------------------------------------------------

local function makeMarker(x, y, z, int, dim, color, kind, name, extra)
    local m = createMarker(x, y, z, BINT.markerType, BINT.markerSize, color[1], color[2], color[3], color[4])
    setElementInterior(m, int)
    setElementDimension(m, dim)
    setElementData(m, "bizint:kind", kind)
    setElementData(m, "bizint:name", name)
    setElementData(m, "bizint:color", { color[1], color[2], color[3] })   -- shader_markers hides the real colour
    for k, v in pairs(extra or {}) do setElementData(m, k, v) end
    return m
end

local function buildBuildings()
    for _, b in pairs(BUILD) do if isElement(b.marker) then destroyElement(b.marker) end end
    BUILD = {}
    if not running("biz_core") then return end
    local list = core():getBuildings() or {}
    for id, b in pairs(list) do
        local o = POS.buildings[id]
        if type(o) == "table" and tonumber(o[1]) then
            b.x, b.y, b.z, b.rot = tonumber(o[1]), tonumber(o[2]), tonumber(o[3]), tonumber(o[4]) or b.rot
            pcall(function() core():setBuildingPosition(id, b.x, b.y, b.z, b.rot) end)   -- catalog, web map, mission spawns
        end
        b.marker = makeMarker(b.x, b.y, b.z, 0, 0, BINT.enterColor, "enter", b.name, { ["bizint:building"] = id })
        BUILD[id] = b
    end
end

--------------------------------------------------------------------------------
-- insides
--------------------------------------------------------------------------------

local function rotOffset(x, y, rot, ox, oy)
    local a = math.rad(rot or 0)
    return x + ox * math.cos(a) - oy * math.sin(a), y + ox * math.sin(a) + oy * math.cos(a)
end

local function place(el, int, dim)
    setElementInterior(el, int)
    setElementDimension(el, dim)
    return el
end

local function flagOn(unitId, flag)
    if not flag then return true end
    return running("biz_core") and core():getUnitData(unitId, flag) == true
end

local function destroyProps(inst)
    for _, el in ipairs(inst.elements) do if isElement(el) then destroyElement(el) end end
    inst.elements = {}
    if inst.menuId and running("ui_interactobject") then exports.ui_interactobject:removeInteractMenu(inst.menuId) end
    inst.menuId, inst.pc = nil, nil
end

local function createProps(inst)
    local t, int, dim = inst.template, inst.template.interior, inst.dim
    local function add(el) if el then inst.elements[#inst.elements + 1] = place(el, int, dim) end return el end

    -- exit marker
    local e = t.exit or t.spawn
    add(makeMarker(e[1], e[2], e[3] - 1, int, dim, BINT.exitColor, "exit", inst.name, { ["bizint:unit"] = inst.unitId }))

    -- desk + PC + chair, the PC carries the menu
    local c = t.computer
    if c then
        local rot = c[4] or 0
        add(createObject(BINT.deskModel, c[1], c[2], c[3], 0, 0, rot))
        local px, py = rotOffset(c[1], c[2], rot, BINT.pcOffset[1], BINT.pcOffset[2])
        inst.pc = add(createObject(BINT.pcModel, px, py, c[3] + BINT.pcOffset[3], 0, 0, rot))
        local cx, cy = rotOffset(c[1], c[2], rot, BINT.chairOffset[1], BINT.chairOffset[2])
        add(createObject(BINT.chairModel, cx, cy, c[3] + BINT.chairOffset[3], 0, 0, rot + 180))
        setElementData(inst.pc, "bizint:computer", inst.unitId)
        if running("ui_interactobject") then
            inst.menuId = exports.ui_interactobject:addInteractMenu(inst.pc, {
                title = L.msg("biz_int.computer.title"), range = 2.5, priority = 20,
                items = { { label = L.msg("biz_int.computer.use"), value = "biz_pc_use", desc = L.msg("biz_int.computer.use_desc") } },
            })
        end
    end

    for _, o in ipairs(t.objects or {}) do
        if flagOn(inst.unitId, o.flag) then
            local obj = createObject(o[1], o[2], o[3], o[4], o[5] or 0, o[6] or 0, o[7] or 0)
            if obj then setElementFrozen(obj, true) end
            add(obj)
        end
    end
    for _, p in ipairs(t.peds or {}) do
        if flagOn(inst.unitId, p.flag) then
            local ped = add(createPed(p[1], p[2], p[3], p[4], p[5] or 0))
            if ped then
                setElementFrozen(ped, true)
                setElementData(ped, "bizint:staff", true)
                if p.anim then setPedAnimation(ped, p.anim[1], p.anim[2], -1, true, false, false, false) end
            end
        end
    end
end

local function destroyInstance(unitId)
    local inst = INST[unitId]
    if not inst then return end
    if isTimer(inst.emptyTimer) then killTimer(inst.emptyTimer) end
    destroyProps(inst)
    INST[unitId] = nil
end

local function ensureInstance(info)
    local inst = INST[info.unitId]
    if inst then
        if isTimer(inst.emptyTimer) then killTimer(inst.emptyTimer) end
        inst.emptyTimer = nil
        return inst
    end
    local t = template(info.template)
    if not t then return nil end
    inst = { unitId = info.unitId, dim = info.dimension, template = t, templateId = BINT.TEMPLATE_ALIASES[info.template] or info.template, name = info.name,
             building = info.building, players = {}, elements = {} }
    INST[info.unitId] = inst
    createProps(inst)
    return inst
end

local function scheduleEmpty(inst)
    if next(inst.players) then return end
    if isTimer(inst.emptyTimer) then killTimer(inst.emptyTimer) end
    inst.emptyTimer = setTimer(function()
        if INST[inst.unitId] == inst and not next(inst.players) then destroyInstance(inst.unitId) end
    end, BINT.emptyKeepMs, 1)
end

--------------------------------------------------------------------------------
-- transfers
--------------------------------------------------------------------------------

local function teleport(player, x, y, z, rot, int, dim)
    setElementPosition(player, x, y, z)
    setElementRotation(player, 0, 0, rot or 0)
    setElementInterior(player, int)
    setElementDimension(player, dim)
    setCameraTarget(player, player)
    setCameraInterior(player, int)
end

local function canTransfer(player)
    local now = getTickCount()
    if busy[player] and now - busy[player] < BINT.fadeMs + BINT.cooldownMs then return false end
    busy[player] = now
    return true
end

local function outsideOf(buildingId)
    local b = BUILD[buildingId]
    if not b then return nil end
    return b.x, b.y, b.z + 1, b.rot or 0   -- b.z is the ground
end

local function doEnter(player, info)
    if not isElement(player) then return end
    local inst = ensureInstance(info)
    if not inst then
        outputDebugString("biz_int: no template '" .. tostring(info.template) .. "' for unit " .. tostring(info.unitId), 2)
        triggerClientEvent(player, "bizint:fadeIn", resourceRoot)
        return
    end
    local s = inst.template.spawn
    teleport(player, s[1], s[2], s[3], s[4], inst.template.interior, inst.dim)
    PU[player] = info.unitId
    inst.players[player] = true
    setElementData(player, "biz:unit", {
        id = info.unitId, propertyId = info.propertyId, kind = info.kind, companyId = info.companyId,
        companyName = info.companyName, role = info.role,
    }, "local")
    -- acc_savesys saves this instead of the position inside (the inside may be gone next time)
    local x, y, z = outsideOf(info.building)
    if x then setElementData(player, "save.position", { x, y, z, 0, 0 }, false) end
    triggerClientEvent(player, "bizint:fadeIn", resourceRoot)
    triggerEvent("onPlayerEnterBizUnit", player, info.unitId, info.propertyId, info.kind, info.companyId, info.role)
end

local function enter(player, info)
    if not canTransfer(player) then return false end
    triggerClientEvent(player, "bizint:fadeOut", resourceRoot)
    setTimer(doEnter, BINT.fadeMs, 1, player, info)
    return true
end

--- takes a player out of his unit; instant = no fade (quit / removal)
local function leave(player, reason, instant)
    local unitId = PU[player]
    if not unitId then return false end
    local inst = INST[unitId]
    PU[player] = nil
    if isElement(player) then
        removeElementData(player, "biz:unit")
        -- on quit acc_savesys still has to save the outside position
        if reason ~= "quit" then removeElementData(player, "save.position") end
    end
    local building = inst and inst.building
    if inst then
        inst.players[player] = nil
        scheduleEmpty(inst)
    end
    triggerEvent("onPlayerExitBizUnit", player, unitId, reason or "exit")
    if reason == "quit" or reason == "death" or not isElement(player) then return true end

    local x, y, z, rot = outsideOf(building)
    if not x then x, y, z, rot = 0, 0, 3, 0 end
    if instant then
        teleport(player, x, y, z, rot, 0, 0)
        fadeCamera(player, true, 0.4)
    else
        busy[player] = getTickCount()
        triggerClientEvent(player, "bizint:fadeOut", resourceRoot)
        setTimer(function()
            if not isElement(player) then return end
            teleport(player, x, y, z, rot, 0, 0)
            triggerClientEvent(player, "bizint:fadeIn", resourceRoot)
        end, BINT.fadeMs, 1)
    end
    return true
end

--------------------------------------------------------------------------------
-- marker use (client key press)
--------------------------------------------------------------------------------

local function standsIn(player, marker)
    return isElement(marker) and getElementType(marker) == "marker"
        and getElementDimension(player) == getElementDimension(marker)
        and getElementInterior(player) == getElementInterior(marker)
        and isElementWithinMarker(player, marker)
end

local function notify(player, key, params)
    if running("biz_core") then core():notifyPlayer(player, L.msg(key, params)) end
end

addEventHandler("bizint:use", resourceRoot, function(marker)
    local player = client
    if not standsIn(player, marker) or isPedInVehicle(player) or isPedDead(player) then return end
    local kind = getElementData(marker, "bizint:kind")
    if kind == "exit" then
        if PU[player] == getElementData(marker, "bizint:unit") then leave(player, "exit") end
        return
    end
    local building = getElementData(marker, "bizint:building")
    if kind ~= "enter" or not BUILD[building] or not running("biz_core") then return end
    local units = core():getAccessibleUnits(player, building) or {}
    if #units == 0 then return notify(player, "biz_int.enter.no_property") end
    if #units == 1 then return enter(player, units[1]) end
    triggerClientEvent(player, "bizint:choose", resourceRoot, marker, units)
end)

addEventHandler("bizint:choose", resourceRoot, function(marker, unitId)
    local player = client
    if not standsIn(player, marker) or not running("biz_core") then return end
    local building = getElementData(marker, "bizint:building")
    for _, info in ipairs(core():getAccessibleUnits(player, building) or {}) do
        if info.unitId == tonumber(unitId) then return enter(player, info) end
    end
end)

--------------------------------------------------------------------------------
-- access changes
--------------------------------------------------------------------------------

local function refreshBlips(player)
    for _, b in ipairs(BLIPS[player] or {}) do if isElement(b) then destroyElement(b) end end
    BLIPS[player] = nil
    if not isElement(player) or not running("biz_core") then return end
    local list, seen = {}, {}
    for _, info in ipairs(core():getAccessibleUnits(player) or {}) do
        local b = BUILD[info.building]
        if b and not seen[info.building] then
            seen[info.building] = true
            local blip = createBlip(b.x, b.y, b.z, BINT.blipIcons[info.kind] or 31, 2, 255, 255, 255, 255, 0, BINT.blipDistance, player)
            setElementData(blip, "tooltipText", b.name)
            list[#list + 1] = blip
        end
    end
    BLIPS[player] = list
end

addEventHandler("onBizAccessChanged", root, function()
    local player = source
    if not isElement(player) or getElementType(player) ~= "player" then return end
    refreshBlips(player)
    local unitId = PU[player]
    if unitId and running("biz_core") and not core():canAccessUnit(player, unitId) then
        notify(player, "biz_int.enter.no_access_now")
        leave(player, "access", true)
    end
end)

addEventHandler("onBizUnitRemoved", root, function(unitId)
    local inst = INST[unitId]
    if not inst then return end
    local list = {}
    for p in pairs(inst.players) do list[#list + 1] = p end
    for _, p in ipairs(list) do leave(p, "removed", true) end
    destroyInstance(unitId)
end)

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    if value ~= "biz_pc_use" or not isElement(target) then return end
    local unitId = getElementData(target, "bizint:computer")
    if unitId and PU[source] == unitId then triggerEvent("onBizComputerUse", source, unitId) end
end)

addEventHandler("onPlayerQuit", root, function()
    leave(source, "quit", true)
    for _, b in ipairs(BLIPS[source] or {}) do if isElement(b) then destroyElement(b) end end
    BLIPS[source], busy[source] = nil, nil
end)

-- died inside: the spawn manager respawns him elsewhere
addEventHandler("onPlayerSpawn", root, function()
    local unitId = PU[source]
    local inst = unitId and INST[unitId]
    if unitId and (not inst or getElementDimension(source) ~= inst.dim) then leave(source, "death") end
end)

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getPlayerUnit(player) return PU[player] or false end

function getPlayersInUnit(unitId)
    local out = {}
    local inst = INST[tonumber(unitId)]
    for p in pairs(inst and inst.players or {}) do out[#out + 1] = p end
    return out
end

function enterUnit(player, unitId)
    if not running("biz_core") then return false end
    for _, info in ipairs(core():getAccessibleUnits(player) or {}) do
        if info.unitId == tonumber(unitId) then return enter(player, info) end
    end
    return false
end

function exitUnit(player)
    return leave(player, "exit")
end

function refreshUnitProps(unitId)
    local inst = INST[tonumber(unitId)]
    if not inst then return false end
    destroyProps(inst)
    createProps(inst)
    return true
end

--- inside position of a unit's template (spawn) - for scripts that place things
function getUnitInside(unitId)
    local inst = INST[tonumber(unitId)]
    if not inst then return false end
    local s = inst.template.spawn
    return s[1], s[2], s[3], inst.template.interior, inst.dim
end

--------------------------------------------------------------------------------
-- /bizpos <template> <spawn|exit|computer>   |   /bizpos building <id>
--------------------------------------------------------------------------------

local function isAdmin(player)
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= BINT.adminLevel
end

addCommandHandler("bizpos", function(player, _, a, b)
    if not isAdmin(player) then return end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local pos = { math.floor(x * 100 + 0.5) / 100, math.floor(y * 100 + 0.5) / 100, math.floor(z * 100 + 0.5) / 100, math.floor(rz) }
    if a == "building" and b and BUILD[b] then
        pos[3] = pos[3] - 1                               -- building z is the ground, the player stands 1 m higher
        POS.buildings[b] = pos
        savePositions()
        buildBuildings()
        for _, p in ipairs(getElementsByType("player")) do refreshBlips(p) end
        return notify(player, "biz_int.admin.saved", { what = "building " .. b })
    end
    if a and BINT.TEMPLATES[a] and (b == "spawn" or b == "exit" or b == "computer") then
        if b == "computer" then pos[3] = pos[3] - 1 end   -- desk origin on the floor, the player stands 1 m higher
        POS.templates[a] = POS.templates[a] or {}
        POS.templates[a][b] = pos
        savePositions()
        for id, inst in pairs(INST) do
            if inst.templateId == a then
                inst.template = template(a)
                destroyProps(inst)
                createProps(inst)
            end
        end
        return notify(player, "biz_int.admin.saved", { what = a .. " " .. b })
    end
    notify(player, "biz_int.admin.usage")
end)

--------------------------------------------------------------------------------

local function start()
    buildBuildings()
    for _, p in ipairs(getElementsByType("player")) do refreshBlips(p) end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadPositions()
    start()
end)
addEventHandler("biz_core:ready", root, start)

addEventHandler("onResourceStop", resourceRoot, function()
    local list = {}
    for p in pairs(PU) do list[#list + 1] = p end
    for _, p in ipairs(list) do leave(p, "stop", true) end
end)
