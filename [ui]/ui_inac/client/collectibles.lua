if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_collectibles lists inside the Collectibles menu.
--
-- v_collectibles keeps the LOCAL element data "collectibles.lists" = { { id, name, event, count, total }, ... }
-- on the local player: only the ACTIVE lists (event lists only while their event runs). The Collectibles menu
-- has no fixed rows (stunt jumps / UFO parts removed): v_collectibles is its only source, rows are regenerated
-- whenever that data changes (join, pickup, event on / off).

local DATA_KEY = "collectibles.lists"
local ITEM_KEY = "_vcol"

local function findList(raw, id)
    if type(raw) ~= "table" then return nil end
    for _, l in ipairs(raw) do
        if l.id == id then return l end
    end
    return nil
end

local function progressText(id)
    return function(raw)
        local l = findList(raw, id)
        if not l then return "—" end
        return L("ui_inac.collectibles.progress", { count = tonumber(l.count) or 0, total = tonumber(l.total) or 0 })
    end
end

function syncCollectibleLists()
    local menu = MenuRegistry:get("collectibles")
    if not menu then return end
    local items = {}
    for _, item in ipairs(menu.items) do
        if not item[ITEM_KEY] then items[#items + 1] = item end
    end
    local raw = getElementData(localPlayer, DATA_KEY)
    for _, l in ipairs(type(raw) == "table" and raw or {}) do
        items[#items + 1] = {
            [ITEM_KEY] = true,
            label = tostring(l.name or l.id),
            type = "data",
            source = localPlayer,
            key = DATA_KEY,
            format = progressText(l.id),
            desc = l.event and L("ui_inac.collectibles.event_desc") or nil,
        }
    end
    menu.items = items
    if MenuState.current == "collectibles" then
        MenuState.selected = math.max(1, math.min(MenuState.selected, #items))
    end
end

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == DATA_KEY then syncCollectibleLists() end
end)
