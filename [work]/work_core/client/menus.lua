-- Marker menus (ui_inac temp menus): outfit selector / off duty at duty markers, vehicle
-- list / return at vehicle markers. Hovering an outfit previews it on the local player.

local menu = nil                   -- { id, marker, kind, previewFrom }

addEvent("ui_inac:tempMenuHover")
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local function notify(text, workId)
    local w = workId and Works[workId]
    exports.ui_core:addNotification(w and w.name or "Work", text)
end

---------------------------------------------------------------- outfit preview

-- Local-only model change while scrolling the outfits. It is always reverted when the menu
-- closes; a chosen outfit then arrives from the server (so a refused request leaves no trace).
local function preview(model)
    if not menu or not menu.previewFrom then return end
    setElementModel(localPlayer, model or menu.previewFrom)
end

local function endPreview()
    if menu and menu.previewFrom then
        if getElementModel(localPlayer) ~= menu.previewFrom then
            setElementModel(localPlayer, menu.previewFrom)
        end
    end
end

---------------------------------------------------------------- open / close

local function closeMenu()
    if not menu then return end
    endPreview()
    if exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    menu = nil
end

local function open(def, marker, kind, withPreview)
    local id = exports.ui_inac:createTempMenu(def)
    if not id then return end
    menu = { id = id, marker = marker, kind = kind,
             previewFrom = withPreview and getElementModel(localPlayer) or nil }
end

local function skinItems(work, action, desc)
    local items = {}
    local lv = getPlayerWorkLevel(localPlayer, work.id)
    for i, s in ipairs(work.skins) do
        if (s.level or 1) > lv then
            items[i] = { label = s.name .. " (level " .. s.level .. ")", desc = "Unlocks at " .. work.name .. " level " .. s.level,
                         value = { a = "locked" } }
        else
            items[i] = { label = s.name, desc = desc, value = { a = action, skin = s.model } }
        end
    end
    return items
end

local function openDutyMenu(marker)
    local workId = getElementData(marker, WORK_DATA.MARKER_WORK)
    local work = Works[workId]
    if not work then return end
    local mine = getPlayerWork(localPlayer)

    if mine and mine ~= workId then
        local other = Works[mine]
        notify(("You are already working as %s. Go off duty first."):format(other and other.name or mine), workId)
        return
    end

    if mine == workId then
        local items = {}
        if #work.skins > 1 then
            items[#items + 1] = { label = "Change outfit", desc = "Pick another work outfit",
                                  title = "OUTFIT", items = skinItems(work, "outfit", "Wear this outfit") }
        end
        items[#items + 1] = { label = "Go off duty", desc = "Finish work and put your own clothes back on",
                              value = { a = "off" } }
        open({ title = work.name:upper(), items = items }, marker, "duty", #work.skins > 1)
    else
        local desc = "Go on duty in this outfit"
        local lvName = getPlayerWorkLevelName(localPlayer, workId)
        desc = ("Level %d%s · %s"):format(getPlayerWorkLevel(localPlayer, workId), lvName and (" " .. lvName) or "", desc)
        if work.description ~= "" then desc = work.description .. " · " .. desc end
        open({ title = work.name:upper() .. " · ON DUTY", items = skinItems(work, "on", desc) },
            marker, "duty", true)
    end
end

local function openVehicleMenu(marker)
    local workId = getElementData(marker, WORK_DATA.MARKER_WORK)
    local work = Works[workId]
    if not work then return end
    local title = work.name:upper() .. " · VEHICLES"

    if getPedOccupiedVehicle(localPlayer) then
        open({ title = title, items = {
            { label = "Return vehicle", desc = "Hand the work vehicle back", value = { a = "return" } },
        } }, marker, "vehicle")
        return
    end

    local items = {}
    for i, v in ipairs(getElementData(marker, WORK_DATA.MARKER_VEHICLES) or {}) do
        items[i] = { label = v.name, desc = "Request this work vehicle", value = { a = "spawn", i = i } }
    end
    if #items == 0 then return end
    open({ title = title, items = items }, marker, "vehicle")
end

local function onKey()
    if menu then closeMenu() return end
    local marker = CurrentMarker
    if not isElement(marker) or isCursorShowing() or isChatBoxInputActive() then return end
    local kind = getElementData(marker, WORK_DATA.MARKER_KIND)
    if kind == "duty" then openDutyMenu(marker)
    elseif kind == "vehicle" then openVehicleMenu(marker) end
end

-- called by state.lua whenever the usable marker changes (nil = left it)
function onCurrentMarkerChange(marker)
    if menu and menu.marker ~= marker then closeMenu() end
    if marker then
        bindKey(WORK.KEY, "down", onKey)
    else
        unbindKey(WORK.KEY, "down", onKey)
    end
end

---------------------------------------------------------------- ui_inac events

addEventHandler("ui_inac:tempMenuHover", root, function(id, value)
    if not menu or id ~= menu.id then return end
    preview(type(value) == "table" and value.skin or nil)
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if not menu or id ~= menu.id or type(value) ~= "table" then return end
    local marker = menu.marker
    if value.a == "locked" then return end
    if value.a == "on" or value.a == "outfit" then
        triggerServerEvent(value.a == "on" and "work:dutyOn" or "work:outfit", resourceRoot, marker, value.skin)
    elseif value.a == "off" then
        triggerServerEvent("work:dutyOff", resourceRoot, marker)
    elseif value.a == "spawn" then
        triggerServerEvent("work:vehicleSpawn", resourceRoot, marker, value.i)
    elseif value.a == "return" then
        triggerServerEvent("work:vehicleReturn", resourceRoot, marker)
    end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if not menu or id ~= menu.id then return end
    endPreview()
    menu = nil
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeMenu()
end)
