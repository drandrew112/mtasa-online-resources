-- /medscenesummon, client side: a ui_inac temp menu listing every scene in its
-- folder tree (same layout as the editor's "Load scene" list), picking one just
-- spawns it instead of opening it for editing.

addEvent("msm:summonOpen", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local menuId = nil

-- "ls_heartattack2" before "ls_heartattack10"
local function naturalKey(text)
    return (tostring(text):lower():gsub("%d+", function(d) return ("%08d"):format(tonumber(d)) end))
end

local function folderLabel(folder)
    for _, c in ipairs(MSM_CATEGORIES) do
        if c.id == folder then return c.label end
    end
    return (folder:gsub("_", " "))
end

-- Builds the menu following the folders: settlement -> scenes + category subfolders
local function sceneTree(scenes)
    local root = { folders = {}, scenes = {}, count = 0 }
    for _, s in ipairs(scenes) do
        local node = root
        local parts = {}
        for part in tostring(s.path or s.name):gmatch("[^/]+") do parts[#parts + 1] = part end
        root.count = root.count + 1
        for i = 1, #parts - 1 do
            local name = parts[i]
            node.folders[name] = node.folders[name] or { folders = {}, scenes = {}, count = 0 }
            node = node.folders[name]
            node.count = node.count + 1
        end
        node.scenes[#node.scenes + 1] = s
    end

    local function build(node)
        local items = {}
        local folders = {}
        for name in pairs(node.folders) do folders[#folders + 1] = name end
        table.sort(folders, function(a, b) return naturalKey(folderLabel(a)) < naturalKey(folderLabel(b)) end)
        for _, name in ipairs(folders) do
            local sub = node.folders[name]
            local label = folderLabel(name)
            items[#items + 1] = { label = ("%s/  (%d)"):format(label, sub.count), title = label, items = build(sub) }
        end
        table.sort(node.scenes, function(a, b) return naturalKey(a.name) < naturalKey(b.name) end)
        for _, s in ipairs(node.scenes) do
            items[#items + 1] = {
                label = s.name .. (s.active and " (active)" or ""),
                desc = ("%s - %d ped(s), %d vehicle(s)"):format(s.title or "", s.peds or 0, s.vehicles or 0),
                value = s.name, checked = s.active or nil,
            }
        end
        return items
    end
    return build(root)
end

addEventHandler("msm:summonOpen", resourceRoot, function(scenes)
    if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    local items = sceneTree(scenes)
    if #items == 0 then items[1] = { label = "No scenes yet" } end
    menuId = exports.ui_inac:createTempMenu({ title = "Summon scene", items = items })
end)

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if rootId ~= menuId or type(value) ~= "string" then return end
    triggerServerEvent("msm:summonPick", resourceRoot, value)
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if rootId == menuId then menuId = nil end
end)
