-- ============================================================
--  v_admin / server/id_manager.lua
--  Unique, recycled server-side player IDs.
--  Element data key: "ID"  (number)
-- ============================================================

local nextId  = 0
local usedIds = {}

local function assignId(player)
    if not isElement(player) then return end
    if getElementData(player, "ID") then return end   -- already has an ID

    repeat
        nextId = nextId + 1
    until not usedIds[nextId]

    usedIds[nextId] = true
    setElementData(player, "ID", nextId)
    outputServerLog("[v_admin] ID " .. nextId .. " -> " .. getPlayerName(player))
end

local function releaseId(player)
    local id = tonumber(getElementData(player, "ID"))
    if id then
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
    adminAlert(player, "#FFFFFFYour ID: #CCFFCC" .. tostring(getElementData(player, "ID") or "none"))
end)
