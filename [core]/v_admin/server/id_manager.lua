if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/id_manager.lua
--  Unique, recycled server-side player IDs.
--  Element data key: "ID"  (number)
-- ============================================================

local nextId  = 0
local usedIds = {}   -- [id] = player
-- The "ID" element data outlives a restart of this resource, so the start
-- re-registers the kept IDs first; a duplicate (two players, one ID) gets a new one.

local function assignId(player)
    if not isElement(player) then return end
    local current = tonumber(getElementData(player, "ID"))
    if current and usedIds[current] == player then return end   -- already has an ID
    if current and not usedIds[current] then                     -- kept over a resource restart
        usedIds[current] = player
        return
    end

    repeat
        nextId = nextId + 1
    until not usedIds[nextId]

    usedIds[nextId] = player
    setElementData(player, "ID", nextId)
    outputServerLog("[v_admin] ID " .. nextId .. " -> " .. getPlayerName(player))
end

local function releaseId(player)
    local id = tonumber(getElementData(player, "ID"))
    if id and usedIds[id] == player then
        usedIds[id] = nil
    end
end

addEventHandler("onPlayerJoin", root, function()
    assignId(source)
end)

addEventHandler("onPlayerQuit", root, function()
    releaseId(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        assignId(player)
    end
end)

addCommandHandler("myid", function(player)
    adminAlert(player, L.msg("v_admin.id_manager.your_id", { player = tostring(getElementData(player, "ID") or "none") }))
end)
