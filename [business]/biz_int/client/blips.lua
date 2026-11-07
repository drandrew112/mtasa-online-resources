-- biz_int / client/blips.lua
-- Minimap blips inside the organization interiors (v_radar interior blips): a door icon on the exit
-- marker and a computer icon on the office PC. They belong to the interior map "biz_<template id>";
-- v_radar only shows them once such a map exists (until then nothing is drawn).

local MAP_PREFIX = "biz_"
local signature = ""
local created = false

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function collect()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local list = {}
    if dim == 0 then return list end
    local function inside(el) return getElementDimension(el) == dim and getElementInterior(el) == int end
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        local tpl = getElementData(m, "bizint:template")
        if tpl and getElementData(m, "bizint:kind") == "exit" and inside(m) then
            local x, y, z = getElementPosition(m)
            list[#list + 1] = { MAP_PREFIX .. tpl, x, y, z, "door", "Exit" }
        end
    end
    for _, o in ipairs(getElementsByType("object", resourceRoot)) do
        local tpl = getElementData(o, "bizint:template")
        if tpl and getElementData(o, "bizint:computer") and inside(o) then
            local x, y, z = getElementPosition(o)
            list[#list + 1] = { MAP_PREFIX .. tpl, x, y, z, "computer", "Computer" }
        end
    end
    return list
end

local function sync()
    if not running("v_radar") then
        created = false
        signature = ""
        return
    end
    local list = collect()
    local parts = {}
    for _, b in ipairs(list) do parts[#parts + 1] = b[1] .. ":" .. b[5] .. ":" .. math.floor(b[2]) .. ":" .. math.floor(b[3]) end
    table.sort(parts)
    local sig = table.concat(parts, "|")
    if sig == signature and created then return end
    signature, created = sig, true
    exports.v_radar:clearInteriorBlips()
    for _, b in ipairs(list) do
        exports.v_radar:addInteriorBlip(b[1], b[2], b[3], b[4], b[5], b[6])
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function() setTimer(sync, 500, 0) end)
addEventHandler("onClientResourceStart", root, function(res)
    if getResourceName(res) == "v_radar" then created = false end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if running("v_radar") then exports.v_radar:clearInteriorBlips() end
end)
