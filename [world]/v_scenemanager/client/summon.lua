if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /scenesummon, client side: a ui_inac temp menu listing every scene in its
-- folder tree (same layout as the editor's "Load scene" list), picking one just
-- spawns it instead of opening it for editing.

addEvent("vsm:summonOpen", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local menuId = nil

-- "ls_heartattack2" before "ls_heartattack10"
local function naturalKey(text)
    return (tostring(text):lower():gsub("%d+", function(d) return ("%08d"):format(tonumber(d)) end))
end

local function folderLabel(folder)
    for _, c in ipairs(VSM_CATEGORIES) do
        if c.id == folder then return L(c.label) end
    end
    return (folder:gsub("_", " "))
end

local function needsText(needs)
    if type(needs) ~= "table" then return "" end
    return ("EMS %d · PD %d"):format(needs.ems or 0, needs.pd or 0)
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
                label = s.name .. (s.active and (" " .. L("v_scenemanager.summon.active_mark")) or "") .. (s.valid == false and " ✖" or ""),
                desc = L("v_scenemanager.editor.scene_row", { title = s.title or "", peds = s.peds or 0, vehicles = s.vehicles or 0,
                    needs = needsText(s.needs) }),
                value = s.name, checked = s.active or nil,
            }
        end
        return items
    end
    return build(root)
end

local pending = nil

addEventHandler("vsm:summonOpen", resourceRoot, function(part, chunk, chunks, total)
    if chunk == 1 or not pending then pending = {} end
    for _, s in ipairs(part or {}) do pending[#pending + 1] = s end
    if chunk < chunks then return end
    local scenes = pending
    pending = nil
    if total and #scenes ~= total then
        outputDebugString(("v_scenemanager: summon list incomplete (%d of %d)"):format(#scenes, total), 2)
    end
    if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    local items = sceneTree(scenes)
    if #items == 0 then items[1] = { label = L("v_scenemanager.editor.no_scenes") } end
    menuId = exports.ui_inac:createTempMenu({ title = L("v_scenemanager.summon.title"), items = items })
end)

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if rootId ~= menuId or type(value) ~= "string" then return end
    triggerServerEvent("vsm:summonPick", resourceRoot, value)
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if rootId == menuId then menuId = nil end
end)
