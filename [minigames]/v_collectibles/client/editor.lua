-- /collecteditor client.
--   R   menu (ui_inac temp menu): pick / create list, header (name, models, event, enabled, spin), items, delete
--   F4  add an item to the current list: the cursor appears, the ghost object follows it on the world surface,
--       wheel = next / previous model of the list header, Shift + wheel = rotate, left click = place
--       (Ctrl + left click = place and keep placing), right click / Backspace / F4 = cancel
-- Every change goes to the server at once (it writes the JSON file); the server pushes the new state back.
-- While the editor is open the gameplay objects are hidden and nothing can be picked up.

local uicore = exports.ui_core
local inac = exports.ui_inac
local sw, sh = guiGetScreenSize()

Editor = {
    active = false,
    lists = {},         -- from the server: { id, name, event, enabled, spin, models, items, active, eventOn }
    current = nil,      -- current list id
    menuId = nil,
    ghosts = {},        -- [itemId] = object of the current list
    place = nil,        -- { obj, modelIndex, rot, x, y, z, ok } while placing
    input = nil,        -- { token, kind }
}

local E = Editor

local function money(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return out .. " €"
end

local function listTotal(list) return (list.reward or 0) * #list.items end

local function notify(key, params)
    uicore:addNotification(L("v_collectibles.editor.title"), L(key, params))
end

local function currentList()
    if not E.current then return nil end
    for _, l in ipairs(E.lists) do
        if l.id == E.current then return l end
    end
    return nil
end

---------------------------------------------------------------------------- ghosts (all items of the current list)

local function clearGhosts()
    for _, o in pairs(E.ghosts) do
        if isElement(o) then destroyElement(o) end
    end
    E.ghosts = {}
end

local function buildGhosts()
    clearGhosts()
    local list = currentList()
    if not E.active or not list then return end
    for _, it in ipairs(list.items) do
        local o = createObject(it.model, it.x, it.y, it.z, it.rx, it.ry, it.rz)
        if o then
            setElementInterior(o, it.int)
            setElementDimension(o, it.dim)
            setElementCollisionsEnabled(o, false)
            E.ghosts[it.id] = o
        end
    end
end

---------------------------------------------------------------------------- placement (F4)

local function modelName(m)
    local ok, name = pcall(engineGetModelNameFromID, m)
    return ok and name or nil
end

-- the placement ghost shows the current model of the header
local function applyPlaceModel()
    local list = currentList()
    local p = E.place
    if not list or not p or not isElement(p.obj) then return end
    p.missing = not setElementModel(p.obj, list.models[p.modelIndex])
    setElementAlpha(p.obj, p.missing and 0 or 180)
end

local function stopPlacing()
    local p = E.place
    if not p then return end
    if isElement(p.obj) then destroyElement(p.obj) end
    E.place = nil
    showCursor(false)
    toggleControl("next_weapon", true)
    toggleControl("previous_weapon", true)
    toggleControl("fire", true)
    toggleControl("aim_weapon", true)
end

local function placeModel()
    local list = currentList()
    local p = E.place
    if not list or not p then return nil end
    return list.models[p.modelIndex]
end

local function startPlacing()
    local list = currentList()
    if not list then return notify("v_collectibles.editor.pick_list_first") end
    if #list.models == 0 then return notify("v_collectibles.editor.no_models") end
    if E.place then return stopPlacing() end
    local obj = createObject(1271, 0, 0, -50)
    if not obj then return notify("v_collectibles.editor.bad_model") end
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(localPlayer))
    setElementDimension(obj, getElementDimension(localPlayer))
    E.place = { obj = obj, modelIndex = 1, rot = 0, ok = false }
    applyPlaceModel()
    if E.place.missing then notify("v_collectibles.editor.bad_model") end
    showCursor(true)
    toggleControl("next_weapon", false)
    toggleControl("previous_weapon", false)
    toggleControl("fire", false)
    toggleControl("aim_weapon", false)
end

local function stepModel(dir)
    local list = currentList()
    local p = E.place
    if not list or not p or #list.models == 0 then return end
    p.modelIndex = (p.modelIndex - 1 + dir) % #list.models + 1
    applyPlaceModel()
end

local function updatePlacing()
    local p = E.place
    if not p or not isElement(p.obj) then return end
    p.ok = false
    if not isCursorShowing() then return end
    local cx, cy = getCursorPosition()
    if not cx then return end
    local camX, camY, camZ = getCameraMatrix()
    local tx, ty, tz = getWorldFromScreenPosition(cx * sw, cy * sh, 300)
    if not tx then return end
    local hit, hx, hy, hz = processLineOfSight(camX, camY, camZ, tx, ty, tz,
        true, true, false, true, false, false, false, false, p.obj)
    if not hit then return end
    local _, _, minZ = getElementBoundingBox(p.obj)
    local z = hz - (minZ or 0)
    setElementPosition(p.obj, hx, hy, z)
    setElementRotation(p.obj, 0, 0, p.rot)
    p.x, p.y, p.z, p.ok = hx, hy, z, true
end

local function placeNow(keep)
    local p = E.place
    if not p then return end
    if p.missing then return notify("v_collectibles.editor.bad_model") end
    if not p.ok then return notify("v_collectibles.editor.no_surface") end
    triggerServerEvent("v_collectibles:editorAddItem", resourceRoot, E.current, placeModel(), p.x, p.y, p.z, p.rot)
    if not keep then stopPlacing() end
end

addEventHandler("onClientClick", root, function(button, state)
    if not E.place or state ~= "down" then return end
    if inac:isTempMenuOpen() then return end
    if button == "left" then
        placeNow(getKeyState("lctrl") or getKeyState("rctrl"))
    elseif button == "right" then
        stopPlacing()
    end
end)

addEventHandler("onClientKey", root, function(button, press)
    if not E.active or not press then return end
    if E.place then
        if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
            local dir = button == "mouse_wheel_up" and 1 or -1
            if getKeyState("lshift") or getKeyState("rshift") then
                E.place.rot = (E.place.rot + dir * 15) % 360
            else
                stepModel(dir)
            end
            cancelEvent()
        elseif button == "backspace" then
            stopPlacing()
            cancelEvent()
        end
    end
end)

---------------------------------------------------------------------------- menu (R)

local function onOff(v) return v and L("v_collectibles.editor.yes") or L("v_collectibles.editor.no") end

local function buildMenu()
    local list = currentList()
    local items = {}

    -- list picker
    local picks = {}
    for _, l in ipairs(E.lists) do
        picks[#picks + 1] = {
            label = l.name,
            desc = L("v_collectibles.editor.list_desc", { id = l.id, count = #l.items,
                state = l.active and L("v_collectibles.editor.state_active") or L("v_collectibles.editor.state_inactive") }),
            value = { "pick", l.id },
            checked = l.id == E.current,
        }
    end
    picks[#picks + 1] = { label = L("v_collectibles.editor.new_list"), desc = L("v_collectibles.editor.new_list_desc"), value = { "new" } }
    items[#items + 1] = {
        label = L("v_collectibles.editor.current", { name = list and list.name or "—" }),
        desc = L("v_collectibles.editor.current_desc"),
        title = L("v_collectibles.editor.lists"),
        items = picks,
    }

    if list then
        items[#items + 1] = { label = L("v_collectibles.editor.add_item"), desc = L("v_collectibles.editor.add_item_desc"), value = { "place" } }

        -- items
        local rows = {}
        local px, py, pz = getElementPosition(localPlayer)
        local sorted = {}
        for _, it in ipairs(list.items) do sorted[#sorted + 1] = it end
        table.sort(sorted, function(a, b)
            return getDistanceBetweenPoints3D(px, py, pz, a.x, a.y, a.z) < getDistanceBetweenPoints3D(px, py, pz, b.x, b.y, b.z)
        end)
        for _, it in ipairs(sorted) do
            local dist = math.floor(getDistanceBetweenPoints3D(px, py, pz, it.x, it.y, it.z))
            rows[#rows + 1] = {
                label = L("v_collectibles.editor.item_row", { id = it.id, model = it.model, dist = dist }),
                title = L("v_collectibles.editor.item_title", { id = it.id }),
                items = {
                    { label = L("v_collectibles.editor.teleport"), value = { "tp", it.id } },
                    { label = L("v_collectibles.editor.delete_item"), value = { "delitem", it.id } },
                },
            }
        end
        if #rows == 0 then rows[1] = { label = L("v_collectibles.editor.no_items"), value = { "none" }, closeOnSelect = false } end
        items[#items + 1] = {
            label = L("v_collectibles.editor.items", { count = #list.items }),
            desc = L("v_collectibles.editor.items_desc"),
            title = L("v_collectibles.editor.items", { count = #list.items }),
            items = rows,
        }

        items[#items + 1] = {
            label = L("v_collectibles.editor.reward", { reward = money(list.reward or 0), total = money(listTotal(list)) }),
            desc = L("v_collectibles.editor.reward_desc", { count = #list.items }),
            value = { "reward" },
        }
        items[#items + 1] = { label = L("v_collectibles.editor.rename", { name = list.name }), value = { "rename" } }

        -- header models
        local models = {}
        for _, m in ipairs(list.models) do
            models[#models + 1] = {
                label = L("v_collectibles.editor.model_row", { model = m, name = modelName(m) or "?" }),
                title = tostring(m),
                items = { { label = L("v_collectibles.editor.remove_model"), value = { "modeldel", m } } },
            }
        end
        models[#models + 1] = { label = L("v_collectibles.editor.add_model"), desc = L("v_collectibles.editor.add_model_desc"), value = { "modeladd" } }
        items[#items + 1] = {
            label = L("v_collectibles.editor.models", { count = #list.models }),
            desc = L("v_collectibles.editor.models_desc"),
            title = L("v_collectibles.editor.models", { count = #list.models }),
            items = models,
        }

        items[#items + 1] = { label = L("v_collectibles.editor.enabled"), desc = L("v_collectibles.editor.enabled_desc"),
            value = { "toggle", "enabled" }, checked = list.enabled, closeOnSelect = false }
        items[#items + 1] = { label = L("v_collectibles.editor.event"),
            desc = L("v_collectibles.editor.event_desc", { state = onOff(list.eventOn) }),
            value = { "toggle", "event" }, checked = list.event, closeOnSelect = false }
        items[#items + 1] = { label = L("v_collectibles.editor.spin"), desc = L("v_collectibles.editor.spin_desc"),
            value = { "toggle", "spin" }, checked = list.spin, closeOnSelect = false }

        items[#items + 1] = {
            label = L("v_collectibles.editor.delete_list"),
            title = L("v_collectibles.editor.delete_list_confirm", { name = list.name }),
            items = {
                { label = L("v_collectibles.editor.no"), value = { "none" } },
                { label = L("v_collectibles.editor.delete_list_yes"), value = { "dellist", list.id } },
            },
        }
    end

    items[#items + 1] = { label = L("v_collectibles.editor.close"), value = { "close" } }
    return {
        title = list and L("v_collectibles.editor.title_list", { name = list.name }) or L("v_collectibles.editor.title"),
        items = items,
    }
end

local function openMenu()
    if not E.active or E.place or E.input then return end
    if inac:isTempMenuOpen() then return end
    E.menuId = inac:createTempMenu(buildMenu())
    if not E.menuId then notify("v_collectibles.editor.menu_busy") end
end

local function ask(kind, titleKey, default, placeholderKey, maxLen)
    local token = uicore:openTextInput(L(titleKey), maxLen or COLLECT.NAME_MAX, default or "", placeholderKey and L(placeholderKey) or "")
    if token then E.input = { token = token, kind = kind } end
end

local function setField(field, value)
    triggerServerEvent("v_collectibles:editorSet", resourceRoot, E.current, field, value)
end

addEvent("ui_inac:tempMenuSelect")
addEventHandler("ui_inac:tempMenuSelect", root, function(menuId, value, path)
    if not E.active or menuId ~= E.menuId or type(value) ~= "table" then return end
    local act, arg = value[1], value[2]
    local list = currentList()
    if act == "pick" then
        E.current = arg
        buildGhosts()
    elseif act == "new" then
        ask("newlist", "v_collectibles.editor.new_list", "", "v_collectibles.editor.name_placeholder")
    elseif act == "place" then
        startPlacing()
    elseif act == "tp" then
        triggerServerEvent("v_collectibles:editorTeleport", resourceRoot, E.current, arg)
    elseif act == "delitem" then
        triggerServerEvent("v_collectibles:editorDeleteItem", resourceRoot, E.current, arg)
    elseif act == "rename" and list then
        ask("rename", "v_collectibles.editor.rename_title", list.name, "v_collectibles.editor.name_placeholder")
    elseif act == "reward" and list then
        ask("reward", "v_collectibles.editor.reward_title", tostring(list.reward or 0), "v_collectibles.editor.reward_placeholder", 7)
    elseif act == "modeladd" then
        ask("model", "v_collectibles.editor.add_model", "", "v_collectibles.editor.model_placeholder", 5)
    elseif act == "modeldel" then
        setField("removeModel", arg)
    elseif act == "toggle" and list then
        local v = not list[arg]
        list[arg] = v       -- the server confirms with editorData
        setField(arg, v)
        inac:updateTempMenuItem(path, { checked = v })
    elseif act == "dellist" then
        triggerServerEvent("v_collectibles:editorDeleteList", resourceRoot, arg)
    elseif act == "close" then
        triggerServerEvent("v_collectibles:editorClose", resourceRoot)
    end
end)

addEvent("ui_inac:tempMenuClose")
addEventHandler("ui_inac:tempMenuClose", root, function(menuId)
    if menuId == E.menuId then E.menuId = nil end
end)

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    local inp = E.input
    if not inp or inp.token ~= token then return end
    E.input = nil
    if not E.active or not text or text == "" then return end
    if inp.kind == "newlist" then
        triggerServerEvent("v_collectibles:editorCreateList", resourceRoot, text)
    elseif inp.kind == "rename" then
        setField("name", text)
    elseif inp.kind == "reward" then
        local r = tonumber((text:gsub("[%s€]", "")))
        if not r then return notify("v_collectibles.editor.bad_reward", { max = COLLECT.MAX_REWARD }) end
        setField("reward", math.floor(r))
    elseif inp.kind == "model" then
        local m = tonumber(text)
        if not m then return notify("v_collectibles.editor.bad_model") end
        setField("addModel", math.floor(m))
    end
end)

---------------------------------------------------------------------------- labels

addEventHandler("onClientRender", root, function()
    if not E.active then return end
    updatePlacing()
    local list = currentList()
    local px, py, pz = getElementPosition(localPlayer)
    if list then
        for _, it in ipairs(list.items) do
            local d = getDistanceBetweenPoints3D(px, py, pz, it.x, it.y, it.z)
            if d < COLLECT.EDITOR_LABEL_RANGE then
                local sx, sy = getScreenFromWorldPosition(it.x, it.y, it.z + 1.0)
                if sx then
                    dxDrawText("#" .. it.id, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), 1.2, "default-bold", "center", "center")
                    dxDrawText("#" .. it.id, sx, sy, sx, sy, tocolor(255, 210, 60, 255), 1.2, "default-bold", "center", "center")
                end
            end
        end
    end
    -- hint bar
    local text
    if E.place then
        local m = placeModel()
        text = L("v_collectibles.editor.hint_place", { model = tostring(m or "?"), name = m and modelName(m) or "?", rot = E.place.rot })
    else
        text = L("v_collectibles.editor.hint", { name = list and list.name or "—", count = list and #list.items or 0 })
        if list then text = text .. " - " .. L("v_collectibles.editor.hint_total", { total = money(listTotal(list)) }) end
    end
    dxDrawText(text, 1, sh - 39, sw + 1, sh - 9, tocolor(0, 0, 0, 220), 1.1, "default-bold", "center", "center")
    dxDrawText(text, 0, sh - 40, sw, sh - 10, tocolor(255, 255, 255, 255), 1.1, "default-bold", "center", "center")
end)

---------------------------------------------------------------------------- keys, state

local function keyMenu()
    if E.active then openMenu() end
end

local function keyPlace()
    if not E.active or E.input then return end
    if inac:isTempMenuOpen() then return end
    startPlacing()
end

local function setActive(on, data)
    if on then
        E.active = true
        E.lists = type(data) == "table" and data or {}
        if not currentList() then E.current = E.lists[1] and E.lists[1].id or nil end
        bindKey("r", "down", keyMenu)
        bindKey("F4", "down", keyPlace)
        Collect.suspend(true)
        buildGhosts()
        notify("v_collectibles.editor.opened")
    else
        if not E.active then return end
        E.active = false
        stopPlacing()
        clearGhosts()
        if E.menuId and inac:isTempMenuOpen() then inac:closeTempMenu() end
        E.menuId = nil
        unbindKey("r", "down", keyMenu)
        unbindKey("F4", "down", keyPlace)
        Collect.suspend(false)
        notify("v_collectibles.editor.closed")
    end
end

addEvent("v_collectibles:editorState", true)
addEventHandler("v_collectibles:editorState", resourceRoot, function(on, data)
    setActive(on == true, data)
end)

addEvent("v_collectibles:editorData", true)
addEventHandler("v_collectibles:editorData", resourceRoot, function(data)
    if not E.active then return end
    E.lists = type(data) == "table" and data or {}
    if not currentList() then E.current = E.lists[1] and E.lists[1].id or nil end
    buildGhosts()
    -- a placement whose model left the header
    local list = currentList()
    if E.place and list then
        if #list.models == 0 then
            stopPlacing()
        elseif E.place.modelIndex > #list.models then
            E.place.modelIndex = 1
            stepModel(0)
        end
    elseif E.place then
        stopPlacing()
    end
end)

addEvent("v_collectibles:editorSelect", true)
addEventHandler("v_collectibles:editorSelect", resourceRoot, function(listId)
    if not E.active then return end
    E.current = listId
    buildGhosts()
end)

addEvent("v_collectibles:editorNotify", true)
addEventHandler("v_collectibles:editorNotify", resourceRoot, function(key, params)
    notify(key, params)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if E.place then stopPlacing() end
end)
