-- Scene editor, client side: top banner, the R menu (ui_inac temp menu), text input
-- bridge (ui_core) and 3D labels over the scene elements. All decisions are made by
-- the server (server/editor.lua); this file only shows the state and sends actions.

local sw, sh = guiGetScreenSize()
local scale = math.max(0.75, sh / 1080)

local state = false      -- editor state from the server, false = editor off
local menuId = nil       -- our ui_inac temp menu
local pendingText = {}   -- [ui_core token] = server request id

addEvent("msm:editorState", true)
addEvent("msm:askText", true)
addEvent("msm:notify", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")

local function send(action, arg)
    triggerServerEvent("msm:editorAction", resourceRoot, action, arg)
end

local function item(label, action, arg, desc, extra)
    local it = { label = label, desc = desc, value = { a = action, v = arg } }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end

local function short(text, max)
    text = tostring(text or "")
    if #text > max then return text:sub(1, max - 3) .. "..." end
    return text
end

---------------------------------------------------------------- menu

local function sceneMenu(scene)
    local name = scene.file or "unsaved scene"
    local erm = scene.erm

    local priorities = {}
    for p = 1, 4 do
        priorities[p] = item("P" .. p, "priority", p, nil, { checked = erm.priority == p })
    end
    local ermItems = {
        item("Title: " .. short(erm.title, 28), "title", nil, erm.title),
        item("Description ...", "description", nil, erm.description ~= "" and erm.description or "(empty)"),
        item("Caller: " .. short(erm.caller, 24), "caller", nil, erm.caller),
        { label = "Priority: P" .. erm.priority, title = "Priority", items = priorities,
          desc = "Sent as meta.priority (med_erm_auto uses it)" },
        item("Set centre to my position", "center", nil,
            ("Current: %.1f, %.1f, %.1f"):format(scene.center[1], scene.center[2], scene.center[3])),
    }

    local pedItems = { item("Add ped here", "addped", nil, "Created on your position, facing your direction") }
    for _, p in ipairs(scene.peds) do
        pedItems[#pedItems + 1] = item(short(p.label, 46), "gotoped", p.id, "Teleport next to it. Edit it with X.")
    end

    local vehItems = {
        item("Add vehicle (model) ...", "addveh", nil, "Created on your position, you get in. Drive it into place, then save its position."),
        item("Save my vehicle position & state", "savevehicle", nil, "The scene vehicle you sit in"),
    }
    for _, v in ipairs(scene.vehicles) do
        vehItems[#vehItems + 1] = item(short(v.label, 46), "gotoveh", v.id, "Teleport next to it. Edit it with X.")
    end

    local weights = {}
    for _, w in ipairs({ 0, 0.5, 1, 2, 3, 5 }) do
        weights[#weights + 1] = item(tostring(w), "weight", w, nil, { checked = scene.weight == w })
    end
    local genItems = {
        item("Enabled: " .. (scene.enabled and "yes" or "no"), "enabled", nil, "Disabled scenes are never picked at random"),
        { label = "Weight: " .. tostring(scene.weight), title = "Random weight", items = weights,
          desc = "Higher = picked more often" },
    }

    local categories = { item("None", "category", "", "No category subfolder", { checked = scene.category == "" }) }
    for _, c in ipairs(MSM_CATEGORIES) do
        categories[#categories + 1] = item(c.label, "category", c.id, "Subfolder: " .. c.id, { checked = scene.category == c.id })
    end
    local categoryLabel = "None"
    for _, c in ipairs(MSM_CATEGORIES) do
        if c.id == scene.category then categoryLabel = c.label end
    end

    local function confirm(label, action, desc)
        if not scene.dirty then return item(label, action, nil, desc) end
        return { label = label, title = "Unsaved changes", desc = "There are unsaved changes", items = {
            item("Discard changes and continue", action),
            item("Cancel", "noop"),
        } }
    end

    return {
        title = "Scene: " .. name .. (scene.dirty and " *" or ""),
        items = {
            { label = "ERM task", title = "ERM task", items = ermItems },
            { label = ("Peds (%d)"):format(#scene.peds), title = "Peds", items = pedItems },
            { label = ("Vehicles (%d)"):format(#scene.vehicles), title = "Vehicles", items = vehItems },
            { label = "Random generator", title = "Random generator", items = genItems },
            { label = "Category: " .. categoryLabel, title = "Category", items = categories,
              desc = "Folder: scenes/<settlement>/<category>/. The settlement comes from the centre." },
            item("Teleport to scene", "teleport", nil, "To the ERM task centre"),
            item("Save", "save", nil, scene.file and scene.target or "Never saved - use Save as"),
            item("Save as ...", "saveas", nil, "Saved as " .. scene.target),
            confirm("Leave scene", "leave", "Back to the main menu"),
            confirm("Exit editor", "exit"),
        },
    }
end

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

-- Load scene menu following the folders: settlement -> scenes + category subfolders
local function sceneTree()
    local root = { folders = {}, scenes = {}, count = 0 }
    for _, s in ipairs(state.scenes) do
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
            items[#items + 1] = item(s.name .. (s.locked and " (in use)" or ""), "load", s.name,
                ("%s - %d ped(s), %d vehicle(s)"):format(s.title or "", s.peds or 0, s.vehicles or 0))
        end
        return items
    end
    return build(root)
end

local function mainMenu()
    local list = sceneTree()
    if #list == 0 then list[1] = item("No scenes yet", "noop") end
    return {
        title = "Med Scene Editor",
        items = {
            item("New scene", "new", nil, "Empty scene, centred on your position"),
            { label = ("Load scene (%d)"):format(#state.scenes), title = "Load scene", items = list },
            item("Exit editor", "exit"),
        },
    }
end

local function openMenu()
    if not state then return end
    local def = state.scene and sceneMenu(state.scene) or mainMenu()
    menuId = exports.ui_inac:createTempMenu(def)
end

local function keysUsable()
    return not (isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isCursorShowing())
end

local function onMenuKey()
    if not state or not keysUsable() then return end
    if exports.ui_core:isTextInputOpen() then return end
    if menuId and exports.ui_inac:isTempMenuOpen() then
        exports.ui_inac:closeTempMenu()
        return
    end
    if exports.ui_interactobject:isInteractMenuOpen() then return end
    openMenu()
end

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if rootId ~= menuId or type(value) ~= "table" or value.a == "noop" then return end
    send(value.a, value.v)
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if rootId == menuId then menuId = nil end
end)

---------------------------------------------------------------- server events

addEventHandler("msm:editorState", resourceRoot, function(newState)
    local wasOn = state ~= false
    state = newState or false
    if state and not wasOn then
        bindKey(MSM.KEY_MENU, "down", onMenuKey)
    elseif not state and wasOn then
        unbindKey(MSM.KEY_MENU, "down", onMenuKey)
        if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
        menuId = nil
    end
end)

addEventHandler("msm:askText", resourceRoot, function(id, title, maxLen, default)
    if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    local token = exports.ui_core:openTextInput(title, maxLen, default)
    if token then
        pendingText[token] = id
    else
        triggerServerEvent("msm:textResult", resourceRoot, id, false)
    end
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    local id = pendingText[token]
    if not id then return end
    pendingText[token] = nil
    triggerServerEvent("msm:textResult", resourceRoot, id, text)
end)

addEventHandler("msm:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(title, text)
end)

---------------------------------------------------------------- drawing

local function drawBanner()
    local w, h = 420 * scale, 62 * scale
    local x, y = (sw - w) / 2, 18 * scale
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 16, 190))
    dxDrawRectangle(x, y, w, 3 * scale, tocolor(229, 72, 77, 255))
    dxDrawText("Med Scene Editor", x, y + 6 * scale, x + w, y + 34 * scale,
        tocolor(255, 255, 255), 1.6 * scale, "default-bold", "center", "center")
    local sub = "Press " .. MSM.KEY_MENU:upper() .. " to show menu"
    if state.scene then
        sub = sub .. "   |   " .. (state.scene.file or "unsaved scene") .. (state.scene.dirty and " *" or "")
    end
    dxDrawText(sub, x, y + 34 * scale, x + w, y + h - 4 * scale,
        tocolor(200, 205, 215), 1.05 * scale, "default", "center", "center")
end

local function drawLabels()
    local px, py, pz = getElementPosition(localPlayer)
    local dim = getElementDimension(localPlayer)
    for _, kind in ipairs({ "vehicle", "ped" }) do
        for _, element in ipairs(getElementsByType(kind, root, true)) do
            local label = getElementDimension(element) == dim and getElementData(element, "msm.label")
            if label then
                local x, y, z = getElementPosition(element)
                local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                if dist <= MSM.LABEL_RANGE then
                    local sx, sy = getScreenFromWorldPosition(x, y, z + (kind == "ped" and 1.1 or 1.4), 0.06)
                    if sx then
                        local s = math.max(0.6, 1.1 - dist / MSM.LABEL_RANGE * 0.5) * scale
                        local color = kind == "ped" and tocolor(255, 120, 120) or tocolor(120, 190, 255)
                        dxDrawText(label, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), s, "default-bold", "center", "bottom")
                        dxDrawText(label, sx, sy, sx, sy, color, s, "default-bold", "center", "bottom")
                    end
                end
            end
        end
    end
end

addEventHandler("onClientRender", root, function()
    if not state then return end
    drawLabels()
    drawBanner()
end)
