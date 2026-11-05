-- biz_missions / server/editor.lua
-- /bizmissioneditor (admin_level >= MIS.EDITOR_ADMIN): the client shows every
-- mission position as local previews (supply crate, vans, guards, buyer
-- circles) where the mission would spawn them, and edits a copy of the lists.
-- Positions are taken from the admin (on foot or in a vehicle); Save sends the
-- whole doc, which POS.save validates, applies and writes. Every request
-- re-checks the permission. Running missions keep their old positions.

local editors = {}   -- player -> true

local function isAdmin(player)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return false end
    local ok, lvl = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(lvl) or 0) >= MIS.EDITOR_ADMIN
end

local function tell(player, text, saveFailed)
    triggerClientEvent(player, "bizmis:editorNotify", resourceRoot, text, saveFailed == true)
end

--- buildings of the sell missions (properties with product to sell)
local function sellBuildings()
    local out = {}
    if not M.running("biz_core") then return out end
    local buildings = M.core():getBuildings() or {}
    for _, p in ipairs(M.core():getCatalog() or {}) do
        local b = buildings[p.building]
        if p.kind == "weed" and b and not out[p.building] then
            out[p.building] = { id = p.building, name = b.name, x = b.x, y = b.y, z = b.z, rot = b.rot }
        end
    end
    return out
end

local function constants()
    return {
        supplyVan = MIS.SUPPLY_VAN, sellVan = MIS.SELL_VAN, guardSkin = MIS.GUARD_SKINS[1],
        guards = MIS.GUARDS, buyerRadius = MIS.BUYER_RADIUS, deliverRadius = MIS.DELIVER_RADIUS,
        stealRadius = MIS.STEAL_AREA_RADIUS, buyerMinDist = MIS.BUYER_MIN_DIST,
        key = MIS.EDITOR_KEY, labelDist = MIS.EDITOR_LABEL_DIST,
    }
end

local function open(player)
    editors[player] = true
    triggerClientEvent(player, "bizmis:editorStart", resourceRoot, POS.snapshot(), sellBuildings(), constants())
end

local function close(player, tellClient)
    editors[player] = nil
    if tellClient and isElement(player) then triggerClientEvent(player, "bizmis:editorStop", resourceRoot) end
end

addCommandHandler("bizmissioneditor", function(player)
    if not isAdmin(player) then return tell(player, "You have no permission for this (admin level " .. MIS.EDITOR_ADMIN .. "+).") end
    if editors[player] then return close(player, true) end
    open(player)
end)

local function guard(player)
    if client ~= player then return false end
    if not editors[player] then return false end
    if not isAdmin(player) then
        close(player, true)
        return false
    end
    return true
end

-- the client closed the editor
addEvent("bizmis:editorClosed", true)
addEventHandler("bizmis:editorClosed", resourceRoot, function()
    if client then editors[client] = nil end
end)

-- teleport (on foot: the player, in a vehicle: the vehicle) to the open world
addEvent("bizmis:editorTeleport", true)
addEventHandler("bizmis:editorTeleport", resourceRoot, function(x, y, z, rot)
    if not guard(client) then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return end
    local el = getPedOccupiedVehicle(client)
    if el and getVehicleOccupant(el, 0) ~= client then
        removePedFromVehicle(client)
        el = nil
    end
    el = el or client
    setElementInterior(client, 0)
    setElementDimension(client, 0)
    if el ~= client then
        setElementInterior(el, 0)
        setElementDimension(el, 0)
        setElementVelocity(el, 0, 0, 0)
    end
    setElementPosition(el, x, y, z + (el == client and 1 or 1.5))
    if tonumber(rot) then setElementRotation(el, 0, 0, tonumber(rot), "default", true) end
end)

addEvent("bizmis:editorSave", true)
addEventHandler("bizmis:editorSave", resourceRoot, function(doc)
    if not guard(client) then return end
    local ok, err = POS.save(doc)
    if not ok then
        local why = { no_supply = "at least one supply spot is needed", no_buyers = "at least one buyer is needed",
            file = "the file could not be written", invalid = "invalid data" }
        return tell(client, "Not saved: " .. (why[err] or tostring(err)) .. ".", true)
    end
    outputServerLog(("[biz_missions] %s saved the mission positions (%s)"):format(getPlayerName(client), MIS.POSITIONS_FILE))
    tell(client, "Saved. New missions use these positions.")
    -- every open editor gets the saved lists
    for p in pairs(editors) do
        if isElement(p) then triggerClientEvent(p, "bizmis:editorData", resourceRoot, POS.snapshot()) end
    end
end)

addEventHandler("onPlayerQuit", root, function() editors[source] = nil end)
