-- bt_core: the blood transporter right, the institutions and their v_inventory ports.

addEvent("onBtCoreStart")
addEvent("onBtPortsReady")
addEvent("onInventoryReady")

local PortOf = {}      -- institution id -> port id
local InstOf = {}      -- port id -> institution id
local ById = {}
for _, inst in ipairs(BT.INSTITUTIONS) do ById[inst.id] = inst end

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- ---------------------------------------------------------------------------------------------
-- Right
-- ---------------------------------------------------------------------------------------------

function hasRight(player)
    if not BT.REQUIRE_RIGHT then return isElement(player) end
    return isElement(player) and getElementData(player, BT.RIGHT_KEY) == true
end

function setRight(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if enabled then
        setElementData(player, BT.RIGHT_KEY, true)
    elseif not BT.REQUIRE_RIGHT then
        return true                    -- test mode: everybody keeps it
    else
        removeElementData(player, BT.RIGHT_KEY)
    end
    return true
end

local function grantAllIfTesting()
    if BT.REQUIRE_RIGHT then return end
    for _, p in ipairs(getElementsByType("player")) do setElementData(p, BT.RIGHT_KEY, true) end
end
addEventHandler("onPlayerJoin", root, function()
    if not BT.REQUIRE_RIGHT then setElementData(source, BT.RIGHT_KEY, true) end
end)

-- ---------------------------------------------------------------------------------------------
-- Ports
-- ---------------------------------------------------------------------------------------------

-- The v_inventory port of an institution (dimension / visibleTo: the tutorial copies)
local function makePort(inst, dimension, visibleTo)
    return exports.v_inventory:createPort({
        x = inst.x, y = inst.y, z = inst.z, name = inst.name,
        title = L.msg(inst.kind == "bank" and "bt_core.port.bank_title" or "bt_core.port.hospital_title"),
        icon = BT.PORT_ICONS[inst.kind], color = BT.PORT_COLORS[inst.kind],
        dataKey = BT.RIGHT_KEY, dataValue = true, dimension = dimension, visibleTo = visibleTo,
    })
end

local function createPorts()
    if not isRunning("v_inventory") then return end
    local inv = exports.v_inventory
    for instId, portId in pairs(PortOf) do pcall(inv.destroyPort, inv, portId) end
    PortOf, InstOf = {}, {}
    for _, inst in ipairs(BT.INSTITUTIONS) do
        local id, err = makePort(inst)
        if id then
            PortOf[inst.id], InstOf[id] = id, inst.id
        else
            outputDebugString("[bt_core] port of " .. inst.id .. ": " .. tostring(err), 1)
        end
    end
    triggerEvent("onBtPortsReady", resourceRoot)
end

addEventHandler("onInventoryReady", root, createPorts)

-- ---------------------------------------------------------------------------------------------
-- Tutorial ports: copies of some institutions' ports in a private dimension (work_bloodtransport
-- tutorial). They are not in PortOf / InstOf; the tutorial tasks carry their port ids.
-- ---------------------------------------------------------------------------------------------

local TutorialPorts = {}   -- port id -> true

-- instIds: { "ls_bank", ... }, player: the only one who sees them -> { [instId] = portId } | false, reason
function createTutorialPorts(dimension, instIds, player)
    if not isRunning("v_inventory") then return false, "v_inventory" end
    local out = {}
    for _, instId in ipairs(type(instIds) == "table" and instIds or {}) do
        local inst = ById[instId]
        local id = inst and makePort(inst, tonumber(dimension) or 0, isElement(player) and { player } or nil)
        if not id then
            destroyTutorialPorts(out)
            return false, "port of " .. tostring(instId)
        end
        out[instId], TutorialPorts[id] = id, true
    end
    return out
end

function destroyTutorialPorts(ports)
    if type(ports) ~= "table" then return false end
    for _, id in pairs(ports) do
        if TutorialPorts[id] then
            TutorialPorts[id] = nil
            if isRunning("v_inventory") then pcall(exports.v_inventory.destroyPort, exports.v_inventory, id) end
        end
    end
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    grantAllIfTesting()
    createPorts()
    triggerEvent("onBtCoreStart", resourceRoot)
end)

-- ---------------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------------

function getConfig() return BT end
function getInstitutions() return BT.INSTITUTIONS end
function getInstitution(id) return ById[id] or false end
function getPortId(instId) return PortOf[instId] or false end
function getInstitutionByPort(portId) return InstOf[portId] or false end
