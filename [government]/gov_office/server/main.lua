-- gov_office / server/main.lua
-- The government office: a world_interiors interior (registered on start and on
-- world_interiors:ready) and the government computers inside it. A computer is a monitor object
-- with a ui_interactobject menu; "Use" opens the /gov panel (gov_core openGovPanel, which checks
-- the role). Ministers place / move / delete computers with the mouse editor (/govpcs,
-- client/editor.lua); every change is re-checked here.
--
-- gov_office_pcs  one row per computer (position + heading, always in the office interior)

loadstring(exports.gov_core:importLib())()

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS gov_office_pcs (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
        rz DOUBLE NOT NULL DEFAULT 0,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

addEvent("world_interiors:ready", false)
addEvent("onInteractMenuSelect", false)
addEvent("gov_office:place", true)    -- (id | false, x, y, z, rz)
addEvent("gov_office:delete", true)   -- (id)
addEvent("gov_office:stopEdit", true) -- the client closed the editor

local PCS = {}       -- id -> { obj, menu }
local editing = {}  -- player -> true while the editor is open

--------------------------------------------------------------------------------
-- interior
--------------------------------------------------------------------------------

local function registerOffice()
    if not isResourceRunning("world_interiors") then
        outputDebugString("[gov_office] world_interiors is not running, the office has no entrance", 2)
        return
    end
    local e, x = OFFICE.enter, OFFICE.exit
    exports.world_interiors:registerInterior(OFFICE.id, {
        name      = L.text("gov_office.name"),
        dimension = OFFICE.dimension,
        enter = { x = e.x, y = e.y, z = e.z, rot = e.rot, interior = 0, dimension = 0 },
        exit  = { x = x.x, y = x.y, z = x.z, rot = x.rot, interior = OFFICE.interior },
    })
end

addEventHandler("world_interiors:ready", root, registerOffice)

local function inOffice(player)
    if getElementInterior(player) ~= OFFICE.interior or getElementDimension(player) ~= OFFICE.dimension then return false end
    local px, py, pz = getElementPosition(player)
    local x = OFFICE.exit
    return getDistanceBetweenPoints3D(px, py, pz, x.x, x.y, x.z) <= OFFICE.editRange
end

--------------------------------------------------------------------------------
-- computers
--------------------------------------------------------------------------------

local function addMenu(rec)
    if not isResourceRunning("ui_interactobject") then return end
    rec.menu = exports.ui_interactobject:addInteractMenu(rec.obj, {
        title = L.msg("gov_office.pc.title"), range = OFFICE.pcRange, priority = 20, offset = OFFICE.pcMenuOffset,
        items = { { label = L.msg("gov_office.pc.use"), value = "gov_pc_use", desc = L.msg("gov_office.pc.use_desc") } },
    })
end

local function spawnPc(id, x, y, z, rz)
    local rec = PCS[id]
    if rec and isElement(rec.obj) then
        setElementPosition(rec.obj, x, y, z)
        setElementRotation(rec.obj, 0, 0, rz)
        return rec
    end
    local obj = createObject(OFFICE.pcModel, x, y, z, 0, 0, rz)
    if not obj then return false end
    setElementInterior(obj, OFFICE.interior)
    setElementDimension(obj, OFFICE.dimension)
    setElementFrozen(obj, true)
    setElementData(obj, "gov_office:pc", id)
    rec = { obj = obj }
    PCS[id] = rec
    addMenu(rec)
    return rec
end

local function removePc(id)
    local rec = PCS[id]
    if not rec then return end
    if isElement(rec.obj) then destroyElement(rec.obj) end   -- the menu goes with its element
    PCS[id] = nil
end

local function pcCount()
    local n = 0
    for _ in pairs(PCS) do n = n + 1 end
    return n
end

local function loadPcs()
    DB.query(function(rows)
        if rows == false then return end
        for _, r in ipairs(rows) do
            spawnPc(DB.int(r.id), tonumber(r.x), tonumber(r.y), tonumber(r.z), tonumber(r.rz) or 0)
        end
    end, "SELECT id, x, y, z, rz FROM gov_office_pcs ORDER BY id")
end

-- ui_interactobject restarted: the menus are gone, the objects are not
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "ui_interactobject" then return end
    setTimer(function()
        for _, rec in pairs(PCS) do if isElement(rec.obj) then addMenu(rec) end end
    end, 500, 1)
end)

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    if value ~= "gov_pc_use" or not isElement(target) or not getElementData(target, "gov_office:pc") then return end
    if isResourceRunning("gov_core") then exports.gov_core:openGovPanel(source) end
end)

--------------------------------------------------------------------------------
-- editor (/govpcs)
--------------------------------------------------------------------------------

local function notify(player, key, params)
    triggerClientEvent(player, "gov_office:notify", resourceRoot, key, params or {})
end

--- the /govpcs editor: the office.edit right (gov_perms; admins always)
local function canEdit(player)
    return isResourceRunning("gov_core") and exports.gov_core:hasGovPerm(player, "office.edit") or false
end

addCommandHandler(OFFICE.command, function(player)
    if not canEdit(player) then return notify(player, "gov_office.err.no_right") end
    if editing[player] then
        editing[player] = nil
        return triggerClientEvent(player, "gov_office:editor", resourceRoot, false)
    end
    if not inOffice(player) then return notify(player, "gov_office.err.not_inside") end
    editing[player] = true
    triggerClientEvent(player, "gov_office:editor", resourceRoot, true)
end)

local function checkEdit(player)
    if not editing[player] then return false end
    if not canEdit(player) or not inOffice(player) then
        editing[player] = nil
        triggerClientEvent(player, "gov_office:editor", resourceRoot, false)
        return false
    end
    return true
end

addEventHandler("gov_office:place", resourceRoot, function(id, x, y, z, rz)
    local player = client
    if not checkEdit(player) then return end
    x, y, z, rz = tonumber(x), tonumber(y), tonumber(z), tonumber(rz)
    if not (x and y and z and rz) then return end
    rz = rz % 360
    local ex = OFFICE.exit
    if getDistanceBetweenPoints3D(x, y, z, ex.x, ex.y, ex.z) > OFFICE.editRange then
        return notify(player, "gov_office.err.too_far")
    end
    id = tonumber(id)
    if id then
        if not PCS[id] then return end
        spawnPc(id, x, y, z, rz)
        DB.exec("UPDATE gov_office_pcs SET x = ?, y = ?, z = ?, rz = ? WHERE id = ?", x, y, z, rz, id)
        GOV.log(GOV.accountOf(player) or "", "office.pc_move", { id = id })
        return notify(player, "gov_office.ed.moved")
    end
    if pcCount() >= OFFICE.pcMax then return notify(player, "gov_office.err.max", { max = OFFICE.pcMax }) end
    local actor = GOV.accountOf(player) or ""
    MYSQL.insert(function(newId)
        if not newId then return notify(player, "gov_office.err.db") end
        spawnPc(DB.int(newId), x, y, z, rz)
        GOV.log(actor, "office.pc_add", { id = DB.int(newId) })
        if isElement(player) then notify(player, "gov_office.ed.placed") end
    end, "INSERT INTO gov_office_pcs (x, y, z, rz, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        x, y, z, rz, actor, GOV.now())
end)

addEventHandler("gov_office:delete", resourceRoot, function(id)
    local player = client
    if not checkEdit(player) then return end
    id = tonumber(id)
    if not id or not PCS[id] then return end
    removePc(id)
    DB.exec("DELETE FROM gov_office_pcs WHERE id = ?", id)
    GOV.log(GOV.accountOf(player) or "", "office.pc_delete", { id = id })
    notify(player, "gov_office.ed.deleted")
end)

addEventHandler("gov_office:stopEdit", resourceRoot, function() editing[client] = nil end)
addEventHandler("onPlayerQuit", root, function() editing[source] = nil end)

--------------------------------------------------------------------------------
-- start
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    registerOffice()
    DB.start(SCHEMA, loadPcs)
end)
