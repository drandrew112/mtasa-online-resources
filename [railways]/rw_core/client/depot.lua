-- Depot menu (ui_inac temp menu). The server sends the options when the player presses the
-- depot key inside a depot marker, and re-checks every pick.

local inMarker = nil
local menuId = nil
local sw, sh = guiGetScreenSize()

local function hint()
    if not inMarker or menuId then return end
    if isChatBoxInputActive() or isCursorShowing() then return end
    local s = sh / 1080
    local text = ("Press %s - %s depot"):format(RW.DEPOT_KEY:upper(), RW.COMPANY)
    dxDrawText(text, 0, sh * 0.82 + 2 * s, sw + 2 * s, 0, tocolor(0, 0, 0, 200), 1.4 * s, "default-bold", "center")
    dxDrawText(text, 0, sh * 0.82, sw, 0, tocolor(255, 255, 255, 255), 1.4 * s, "default-bold", "center")
end

addEventHandler("onClientMarkerHit", root, function(el, dim)
    if el ~= localPlayer or not dim or not getElementData(source, "rw.depot") then return end
    if isPedInVehicle(localPlayer) then return end
    inMarker = source
    addEventHandler("onClientRender", root, hint)
end)

addEventHandler("onClientMarkerLeave", root, function(el)
    if el ~= localPlayer or source ~= inMarker then return end
    inMarker = nil
    removeEventHandler("onClientRender", root, hint)
    if menuId then exports.ui_inac:closeTempMenu() menuId = nil end
end)

bindKey(RW.DEPOT_KEY, "down", function()
    if not inMarker or menuId or isChatBoxInputActive() or isCursorShowing() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    triggerServerEvent("rw:depot:open", resourceRoot)
end)

addEvent("rw:depot:menu", true)
addEventHandler("rw:depot:menu", resourceRoot, function(data)
    if not inMarker then return end
    local spawnItems = {}
    for _, s in ipairs(data.spawns) do
        local presets = {}
        for _, p in ipairs(data.presets) do
            presets[#presets + 1] = { label = p.name, value = { "spawn", s.id, p.id } }
        end
        spawnItems[#spawnItems + 1] = { label = s.name, title = s.name, items = presets }
    end

    local trainItems = {}
    for _, c in ipairs(data.consists) do
        local sub = {}
        for _, t in ipairs(data.carriageTypes) do
            sub[#sub + 1] = { label = "Add " .. t.name:lower(), value = { "add", c.id, t.id }, desc = "Coupled to the end of the train" }
        end
        if c.carriages > 0 then
            sub[#sub + 1] = { label = "Uncouple last carriage", value = { "remove", c.id } }
        end
        sub[#sub + 1] = { label = "Send to the shed (remove)", value = { "despawn", c.id } }
        trainItems[#trainItems + 1] = { label = c.label, title = c.number, items = sub }
    end
    if #trainItems == 0 then
        trainItems[1] = { label = "No train at this depot", value = { "none" } }
    end

    menuId = exports.ui_inac:createTempMenu({
        title = data.depot,
        items = {
            { label = "New train", title = "Spawn point", desc = "Assemble a new train on a free track", items = spawnItems },
            { label = "Trains at the depot", title = "Assembly", desc = "Couple / uncouple carriages", items = trainItems },
        },
    })
end)

addEvent("ui_inac:tempMenuSelect", false)
addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "table" then return end
    if value[1] ~= "none" then
        triggerServerEvent("rw:depot:action", resourceRoot, value[1], value[2], value[3])
    end
end)

addEvent("ui_inac:tempMenuClose", false)
addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id == menuId then menuId = nil end
end)
