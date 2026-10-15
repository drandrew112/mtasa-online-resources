-- bt_items: the cargo of the blood transport on v_inventory.
--   * one blood box in every blood transport ambulance (work_bloodtransport vehicles), taken out and
--     put back through an interact menu at the rear; no trunk panel
--   * one cargo item per task (amount = units), created on the pickup port, destroyed when delivered
--   * per-player port rules: only the own cargo, only from the pickup port into the own box, only into
--     the destination port out of it (no putting back)
--   * pickup / delivery detection -> bt_dispatch

addEvent("onBtItemsStart")
addEvent("onBtPortsReady")
addEvent("onBtCoreStart")
addEvent("onWorkVehicleSpawn")
addEvent("onInventoryItemMove")
addEvent("onInventoryItemMoved")

local BOX_TAG = "bt_box"       -- the box is stored in the vehicle under this tag (no v_inventory trunk panel)
local ANCHOR_MODEL = 1598      -- invisible prop the take / put menu hangs on
local TRUNK_OFFSET = { 0, -2.5, -0.2 }  -- vehicle-local: the rear
local WORK_ID = "bloodtransport"

local Boxes = {}                -- box uid -> { vehicle, owner }
local BoxOfVehicle = {}         -- vehicle -> box uid
local Cargo = {}                -- task id -> item uid
local TaskOf = {}               -- item uid -> task id

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function inv() return exports.v_inventory end
local function core() return exports.bt_core end

local function cfg() return core():getConfig() end

local function say(player, key, params)
    return L.forPlayer(player, key, params)
end

-- ---------------------------------------------------------------------------------------------
-- Cargo
-- ---------------------------------------------------------------------------------------------

-- task: { id, type, product, group, units, from, to } (institution ids) -> uid | false
function spawnCargo(task)
    if type(task) ~= "table" or not task.id then return false end
    if Cargo[task.id] then return Cargo[task.id] end
    local c = cfg()
    local defId
    if task.type == "lab_sample" then defId = "bt_lab_sample"
    elseif task.type == "urgent_medicine" then defId = "bt_urgent_medicine"
    else defId = c.PRODUCTS[task.product] and c.PRODUCTS[task.product].item end
    if not defId then return false end
    local portId = core():getPortId(task.from)
    if not portId then return false end
    local from, to = core():getInstitution(task.from), core():getInstitution(task.to)
    local display = {
        { label = L.msg("bt_items.meta.task"), value = "T-" .. task.id },
        { label = L.msg("bt_items.meta.from"), value = from and from.name or "?" },
        { label = L.msg("bt_items.meta.to"), value = to and to.name or "?" },
    }
    if task.group and task.group ~= "" then
        display[#display + 1] = { label = L.msg("bt_items.meta.group"), value = task.group }
    end
    local uid, err = inv():createItem(defId, { task = task.id, group = task.group, display = display },
        { type = "port", port = portId },
        { amount = task.units or 1, access = { dataKey = c.RIGHT_KEY, dataValue = true } })
    if not uid then
        outputDebugString("[bt_items] cargo of task " .. tostring(task.id) .. ": " .. tostring(err), 1)
        return false
    end
    Cargo[task.id], TaskOf[uid] = uid, task.id
    return uid
end

function destroyCargo(taskId)
    local uid = Cargo[taskId]
    if not uid then return false end
    Cargo[taskId], TaskOf[uid] = nil, nil
    pcall(inv().destroyInventoryItem, inv(), uid)
    return true
end

function getCargoItem(taskId) return Cargo[taskId] or false end

-- ---------------------------------------------------------------------------------------------
-- Vehicle box
-- ---------------------------------------------------------------------------------------------

local function isOwnBox(player, vehicle)
    local uid = BoxOfVehicle[vehicle]
    local box = uid and Boxes[uid]
    return box and box.owner == player, uid
end

local function tell(player, text)
    local res = getResourceFromName("v_inventory")
    if res and isElement(player) then
        triggerClientEvent(player, "inv:notify", getResourceRootElement(res), text, true)
    end
end

-- The menu shows "take" while the box is in the vehicle, "put back" while somebody carries it
local function menuItems(box)
    local inCar = box.inVehicle
    return {
        { label = L.msg("bt_items.menu.take"), value = "take", disabled = not inCar },
        { label = L.msg("bt_items.menu.put"), value = "put", disabled = inCar },
    }
end

local function updateMenu(vehicle)
    local uid = BoxOfVehicle[vehicle]
    local box = uid and Boxes[uid]
    if not box or not box.menuId then return end
    local item = inv():getItem(uid)
    box.inVehicle = item and item.loc.type == "vehicle" or false
    exports.ui_interactobject:updateInteractMenu(box.menuId, { items = menuItems(box) })
end

local function createBox(vehicle, owner)
    local c = cfg()
    local plate = (getVehiclePlateText(vehicle) or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local uid = inv():createItem("bt_blood_box", {
        display = { { label = L.msg("bt_items.box.unit"), value = plate } },
    }, { type = "vehicle", vehicle = vehicle, tag = BOX_TAG }, { access = { dataKey = c.RIGHT_KEY, dataValue = true } })
    if not uid then return end
    local box = { vehicle = vehicle, owner = owner, inVehicle = true }
    Boxes[uid] = box
    BoxOfVehicle[vehicle] = uid
    if isRunning("ui_interactobject") then
        local x, y, z = getElementPosition(vehicle)
        local anchor = createObject(ANCHOR_MODEL, x, y, z)
        if anchor then
            setElementAlpha(anchor, 0)
            setElementCollisionsEnabled(anchor, false)
            setElementDimension(anchor, getElementDimension(vehicle))
            setElementInterior(anchor, getElementInterior(vehicle))
            attachElements(anchor, vehicle, TRUNK_OFFSET[1], TRUNK_OFFSET[2], TRUNK_OFFSET[3])
            box.anchor = anchor
            box.menuId = exports.ui_interactobject:addInteractMenu(anchor, {
                title = L.msg("bt_items.trunk.title", { plate = plate }),
                range = 2.0, priority = 8, lineOfSight = false,
                selfDataKey = c.RIGHT_KEY,
                items = menuItems(box),
            }, owner)
        end
    end
end

local function dropBox(vehicle)
    local uid = BoxOfVehicle[vehicle]
    if not uid then return end
    local box = Boxes[uid]
    BoxOfVehicle[vehicle], Boxes[uid] = nil, nil
    if box and box.menuId and isRunning("ui_interactobject") then
        exports.ui_interactobject:removeInteractMenu(box.menuId)
    end
    if box and isElement(box.anchor) then destroyElement(box.anchor) end
    pcall(inv().destroyInventoryItem, inv(), uid)
end

addEventHandler("onWorkVehicleSpawn", root, function(player, workId)
    if workId ~= WORK_ID then return end
    createBox(source, player)
end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) == "vehicle" and BoxOfVehicle[source] then dropBox(source) end
end)

-- Menu: take the box out of the vehicle / put it back
addEvent("onInteractMenuSelect")
addEventHandler("onInteractMenuSelect", root, function(menuId, value)
    local player = source
    local vehicle, box, uid
    for u, b in pairs(Boxes) do
        if b.menuId == menuId then vehicle, box, uid = b.vehicle, b, u break end
    end
    if not box or (value ~= "take" and value ~= "put") then return end
    if isPedDead(player) or isPedInVehicle(player) or box.owner ~= player or not isElement(box.anchor) then return end
    local ax, ay, az = getElementPosition(box.anchor)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(ax, ay, az, px, py, pz) > 3.5 then return end
    if value == "take" then
        local item = inv():getItem(uid)
        if not item or item.loc.type ~= "vehicle" then return end
        local ok, why = inv():giveItemToPlayer(player, uid)
        if not ok then return tell(player, why or L.forPlayer(player, "bt_items.msg.cannot_take")) end
    else
        local slots = inv():getPlayerSlots(player)
        if slots.left ~= uid and slots.right ~= uid and slots.back ~= uid then
            return tell(player, L.forPlayer(player, "bt_items.msg.no_box_in_hand"))
        end
        local ok, why = inv():moveInventoryItem(uid, { type = "vehicle", vehicle = vehicle, tag = BOX_TAG })
        if not ok then return tell(player, why or L.forPlayer(player, "bt_items.msg.cannot_take")) end
    end
    updateMenu(vehicle)
end)

-- The box leaves / enters the vehicle by other ways too (script, inventory): keep the menu right
addEventHandler("onInventoryItemMoved", root, function(uid)
    local box = Boxes[uid]
    if box then setTimer(updateMenu, 0, 1, box.vehicle) end
end)

-- The box of a vehicle (or of a player's work vehicle) -> uid | false
function getBox(who)
    if isElement(who) and getElementType(who) == "player" then
        local veh = isRunning("work_core") and exports.work_core:getPlayerWorkVehicle(who)
        who = veh
    end
    return who and BoxOfVehicle[who] or false
end

-- Destroys everything in the box of the vehicle
function clearBox(vehicle)
    local uid = BoxOfVehicle[vehicle]
    if not uid then return false end
    return inv():clearContainer(uid)
end

-- ---------------------------------------------------------------------------------------------
-- Port rules (per player, recomputed from bt_dispatch's view of the player's tasks)
-- ---------------------------------------------------------------------------------------------

function refreshPlayer(player)
    if not isElement(player) or not isRunning("v_inventory") then return end
    local c = cfg()
    local tasks = isRunning("bt_dispatch") and exports.bt_dispatch:getPlayerTasks(player) or {}
    for _, inst in ipairs(c.INSTITUTIONS) do
        local port = core():getPortId(inst.id)
        if port then
            local out, into, suggest = {}, {}, {}
            for _, t in ipairs(tasks) do
                local uid = Cargo[t.id]
                if uid then
                    if t.status == "waiting" and t.from == inst.id then
                        out[#out + 1] = uid; suggest[uid] = "out"
                    elseif t.status == "transit" and t.to == inst.id then
                        into[#into + 1] = uid; suggest[uid] = "in"
                    end
                end
            end
            inv():setPortRules(port, player, {
                allowIn = #into > 0 and into or false, allowOut = #out > 0 and out or false })
            local banner
            if #out > 0 then banner = L.msg("bt_items.port.banner_take")
            elseif #into > 0 then banner = L.msg("bt_items.port.banner_deliver")
            else banner = L.msg("bt_items.port.banner_none") end
            inv():setPortSuggestions(port, player, suggest, banner)
        end
    end
end

local function refreshAll()
    for _, p in ipairs(getElementsByType("player")) do
        if core():hasRight(p) then refreshPlayer(p) end
    end
end

addEventHandler("onBtPortsReady", root, function() setTimer(refreshAll, 200, 1) end)
addEventHandler("onElementDataChange", root, function(key)
    if getElementType(source) == "player" and key == "bt.right" and getElementData(source, key) == true then
        setTimer(refreshPlayer, 100, 1, source)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Move control + pickup / delivery detection
-- ---------------------------------------------------------------------------------------------

local function taskOf(uid)
    local id = TaskOf[uid]
    if not id or not isRunning("bt_dispatch") then return nil end
    return exports.bt_dispatch:getTask(id)
end

-- Players may only carry the cargo of their own tasks: port -> own box at the pickup port,
-- own box -> destination port. Moves made by scripts (player = false) always pass.
addEventHandler("onInventoryItemMove", root, function(uid, defId, from, to, player, amount)
    if not TaskOf[uid] or not player then return end
    local task = taskOf(uid)
    local function deny(key)
        cancelEvent(true, say(player, key))
    end
    if not task or task.player ~= player then return deny("bt_items.msg.not_yours") end
    local item = inv():getItem(uid)
    if item and amount and amount < item.amount then return deny("bt_items.msg.whole_only") end
    if from.type == "port" and to.type == "container" then
        local box = Boxes[to.container]
        if not box or box.owner ~= player then return deny("bt_items.msg.own_box") end
        if task.status ~= "waiting" or from.port ~= core():getPortId(task.from) then return deny("bt_items.msg.not_yours") end
    elseif from.type == "container" and to.type == "port" then
        local box = Boxes[from.container]
        if not box or box.owner ~= player then return deny("bt_items.msg.own_box") end
        if task.status ~= "transit" or to.port ~= core():getPortId(task.to) then return deny("bt_items.msg.wrong_port") end
    else
        return deny("bt_items.msg.not_allowed")
    end
end)

addEventHandler("onInventoryItemMoved", root, function(uid, defId, from, to, player)
    local id = TaskOf[uid]
    if not id or not player then return end
    if from.type == "port" and to.type == "container" then
        setTimer(function()
            if isRunning("bt_dispatch") then exports.bt_dispatch:onPickedUp(id, player) end
        end, 0, 1)
    elseif from.type == "container" and to.type == "port" then
        setTimer(function()
            if isRunning("bt_dispatch") then exports.bt_dispatch:onDelivered(id, player) end
        end, 0, 1)
    end
end)

-- An item destroyed from outside (v_inventory restart cannot happen here, but a script can) -> forget it
addEvent("onInventoryItemDestroyed")
addEventHandler("onInventoryItemDestroyed", root, function(uid)
    local id = TaskOf[uid]
    if id then Cargo[id], TaskOf[uid] = nil, nil end
    Boxes[uid] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    -- every player with the right gets "nothing may be taken" rules until a task changes that
    setTimer(refreshAll, 1000, 1)
    setTimer(function() triggerEvent("onBtItemsStart", resourceRoot) end, 500, 1)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, uid in pairs(Cargo) do pcall(inv().destroyInventoryItem, inv(), uid) end
    for uid in pairs(Boxes) do pcall(inv().destroyInventoryItem, inv(), uid) end
end)
