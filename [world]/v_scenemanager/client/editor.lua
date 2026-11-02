if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Scene editor, client side: top banner, the R menu (ui_inac temp menu), text input
-- bridge (ui_core) and 3D labels over the scene elements. All decisions are made by
-- the server (server/editor.lua); this file only shows the state and sends actions.
-- Every text comes from v_locals (v_scenemanager.*), in the player's language.

local sw, sh = guiGetScreenSize()
local scale = math.max(0.75, sh / 1080)

local state = false      -- editor state from the server, false = editor off
local menuId = nil       -- our ui_inac temp menu
local pendingText = {}   -- [ui_core token] = server request id

addEvent("vsm:editorState", true)
addEvent("vsm:askText", true)
addEvent("vsm:notify", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEvent("ui_core:textInputResult")

local function send(action, arg)
    triggerServerEvent("vsm:editorAction", resourceRoot, action, arg)
end

local function item(label, action, arg, desc, extra)
    local it = { label = label, desc = desc, value = { a = action, v = arg } }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end

local function short(text, max)
    text = tostring(text or "")
    if L.len(text) > max then return L.sub(text, 1, max - 3) .. "..." end
    return text
end

local function T(key, params) return L(key, params) end

local function folderLabel(folder)
    for _, c in ipairs(VSM_CATEGORIES) do
        if c.id == folder then return T(c.label) end
    end
    return (folder:gsub("_", " "))
end

local function needLabel(n)
    return T("v_scenemanager.need." .. tostring(n or 0))
end

local function dateText(ts)
    local t = getRealTime(tonumber(ts) or 0)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

---------------------------------------------------------------- menu: agencies

local function agencyMenu(scene, id)
    local b = scene.agencies[id]
    local cfg = VSM.AGENCIES[id]
    local needs = {}
    for n = 0, 2 do
        needs[#needs + 1] = item(needLabel(n), "agency_need", { agency = id, v = n }, T("v_scenemanager.need." .. n .. "_desc"),
            { checked = b.need == n })
    end
    local priorities = {}
    for p = 1, 4 do
        priorities[p] = item("P" .. p, "agency_priority", { agency = id, v = p }, nil, { checked = b.priority == p })
    end
    local texts = {}
    for _, lang in ipairs(VSM.LANGS) do
        local e = b.locales[lang]
        local L2 = lang:upper()
        texts[#texts + 1] = item(T("v_scenemanager.editor.text_title", { lang = L2 }) .. ": " .. short(e and e.title or "-", 26),
            "agency_title", { agency = id, lang = lang }, e and e.title ~= "" and e.title or T("v_scenemanager.common.empty"))
        texts[#texts + 1] = item(T("v_scenemanager.editor.text_description", { lang = L2 }) .. " ...",
            "agency_description", { agency = id, lang = lang }, e and (e.description or "") ~= "" and e.description or T("v_scenemanager.common.empty"))
    end
    local items = {
        { label = T("v_scenemanager.editor.need") .. ": " .. needLabel(b.need), title = T(cfg.label), items = needs,
          desc = T("v_scenemanager.editor.need_desc") },
        { label = T("v_scenemanager.editor.priority") .. ": P" .. b.priority, title = T("v_scenemanager.editor.priority"), items = priorities },
        { label = T("v_scenemanager.editor.texts"), title = T("v_scenemanager.editor.texts"), items = texts,
          desc = b.need > 0 and T("v_scenemanager.editor.texts_required") or T("v_scenemanager.editor.texts_optional") },
        item(T("v_scenemanager.editor.late_join") .. ": " .. T(b.lateJoin ~= false and "v_scenemanager.common.on" or "v_scenemanager.common.off"),
            "agency_latejoin", id, T("v_scenemanager.editor.late_join_desc")),
    }
    if id == "ems" then
        table.insert(items, 3, item(T("v_scenemanager.editor.caller") .. ": " .. short(b.caller, 24), "agency_caller", nil, b.caller))
    elseif id == "pd" then
        local close = {}
        for _, k in ipairs(VSM_PD_CLOSE) do
            close[#close + 1] = item(T("v_scenemanager.editor.pd_close_" .. k), "pd_close", k, T("v_scenemanager.editor.pd_close_" .. k .. "_desc"),
                { checked = b.close and b.close[k] == true })
        end
        items[#items + 1] = { label = T("v_scenemanager.editor.pd_close"), title = T("v_scenemanager.editor.pd_close"), items = close,
            desc = T("v_scenemanager.editor.pd_close_desc") }
    end
    return items
end

local function agenciesMenu(scene)
    local items = {}
    for _, id in ipairs(VSM.AGENCY_ORDER) do
        local b = scene.agencies[id]
        items[#items + 1] = { label = ("%s: %s"):format(T(VSM.AGENCIES[id].label), needLabel(b.need)), title = T(VSM.AGENCIES[id].label),
            items = agencyMenu(scene, id) }
    end
    local both = scene.agencies.ems.need == 2 and scene.agencies.pd.need == 2
    items[#items + 1] = item(T("v_scenemanager.editor.safe_start") .. ": " .. T(scene.safe and "v_scenemanager.common.yes" or "v_scenemanager.common.no"),
        "safe", nil, both and T("v_scenemanager.editor.safe_desc") or T("v_scenemanager.editor.safe_needs_both"))
    return items
end

---------------------------------------------------------------- menu: scene

local function validationItems(scene)
    local items = { item(T("v_scenemanager.editor.validate_now"), "validate") }
    for _, v in ipairs(scene.validation or {}) do
        items[#items + 1] = item((v.level == "error" and "✖ " or "! ") .. short(L(v.key, v.params), 48), "noop", nil, L(v.key, v.params))
    end
    return items
end

local function sceneIssueItems(scene)
    local items = {}
    for _, i in ipairs(scene.issues or {}) do
        local meta = T("v_scenemanager.editor.issue_meta", { by = i.byName or "?", at = dateText(i.at), source = T("v_scenemanager.flag.source_" .. tostring(i.source)) })
        items[#items + 1] = { label = "#" .. i.id .. "  " .. short(i.comment, 40), title = "#" .. i.id, desc = i.comment .. "\n" .. meta, items = {
            item(T("v_scenemanager.editor.issue_teleport"), "issue_tp", i.id, i.comment),
            item(T("v_scenemanager.editor.issue_resolve"), "issue_resolve", i.id, i.comment),
        } }
    end
    if #items > 1 then items[#items + 1] = item(T("v_scenemanager.editor.issue_resolve_all"), "issue_resolve_all") end
    return items
end

local function sceneMenu(scene)
    local name = scene.file or T("v_scenemanager.editor.unsaved")

    local pedItems = { item(T("v_scenemanager.editor.add_ped"), "addped", nil, T("v_scenemanager.editor.add_ped_desc")) }
    for _, p in ipairs(scene.peds) do
        pedItems[#pedItems + 1] = item(short(LabelText(p, true), 46), "gotoped", p.id, T("v_scenemanager.editor.goto_desc"))
    end

    local vehItems = {
        item(T("v_scenemanager.editor.add_vehicle"), "addveh", nil, T("v_scenemanager.editor.add_vehicle_desc")),
        item(T("v_scenemanager.editor.save_my_vehicle"), "savevehicle", nil, T("v_scenemanager.editor.save_my_vehicle_desc")),
    }
    for _, v in ipairs(scene.vehicles) do
        vehItems[#vehItems + 1] = item(short(LabelText(v, true), 46), "gotoveh", v.id, T("v_scenemanager.editor.goto_desc"))
    end

    local weights = {}
    for _, w in ipairs({ 0, 0.5, 1, 2, 3, 5 }) do
        weights[#weights + 1] = item(tostring(w), "weight", w, nil, { checked = scene.weight == w })
    end
    local genItems = {
        item(T("v_scenemanager.editor.enabled") .. ": " .. T(scene.enabled and "v_scenemanager.common.yes" or "v_scenemanager.common.no"),
            "enabled", nil, T("v_scenemanager.editor.enabled_desc")),
        { label = T("v_scenemanager.editor.weight") .. ": " .. tostring(scene.weight), title = T("v_scenemanager.editor.weight"), items = weights,
          desc = T("v_scenemanager.editor.weight_desc") },
    }

    local categories = { item(T("v_scenemanager.cat.none"), "category", "", nil, { checked = scene.category == "" }) }
    local categoryLabel = T("v_scenemanager.cat.none")
    for _, c in ipairs(VSM_CATEGORIES) do
        categories[#categories + 1] = item(T(c.label), "category", c.id, c.id, { checked = scene.category == c.id })
        if c.id == scene.category then categoryLabel = T(c.label) end
    end

    local locations = {}
    if scene.suggestedLocation and scene.suggestedLocation ~= "" then
        locations[#locations + 1] = item(T("v_scenemanager.editor.suggested", { location = scene.suggestedLocation }), "location",
            scene.suggestedLocation, T("v_scenemanager.editor.suggested_desc"), { checked = scene.location == scene.suggestedLocation })
    end
    for _, loc in ipairs(scene.locations or {}) do
        if loc ~= scene.suggestedLocation then
            locations[#locations + 1] = item(loc, "location", loc, nil, { checked = scene.location == loc })
        end
    end
    locations[#locations + 1] = item(T("v_scenemanager.editor.new_location"), "newlocation", nil, T("v_scenemanager.editor.new_location_desc"))

    local function confirm(label, action, desc)
        if not scene.dirty then return item(label, action, nil, desc) end
        return { label = label, title = T("v_scenemanager.editor.unsaved_changes"), desc = T("v_scenemanager.editor.unsaved_changes"), items = {
            item(T("v_scenemanager.editor.discard"), action),
            item(T("v_scenemanager.common.cancel"), "noop"),
        } }
    end

    local errors = 0
    for _, v in ipairs(scene.validation or {}) do if v.level == "error" then errors = errors + 1 end end

    local items = {
        { label = T("v_scenemanager.editor.agencies"), title = T("v_scenemanager.editor.agencies"), items = agenciesMenu(scene),
          desc = T("v_scenemanager.editor.agencies_desc") },
        { label = T("v_scenemanager.editor.peds", { count = #scene.peds }), title = T("v_scenemanager.editor.peds_title"), items = pedItems },
        { label = T("v_scenemanager.editor.vehicles", { count = #scene.vehicles }), title = T("v_scenemanager.editor.vehicles_title"), items = vehItems },
        { label = T("v_scenemanager.editor.generator"), title = T("v_scenemanager.editor.generator"), items = genItems },
        { label = T("v_scenemanager.editor.location") .. ": " .. scene.location, title = T("v_scenemanager.editor.location"), items = locations,
          desc = T("v_scenemanager.editor.location_desc") },
        { label = T("v_scenemanager.editor.category") .. ": " .. categoryLabel, title = T("v_scenemanager.editor.category"), items = categories,
          desc = T("v_scenemanager.editor.location_desc") },
        item(T("v_scenemanager.editor.set_centre"), "center", nil,
            T("v_scenemanager.editor.set_centre_desc", { x = ("%.1f"):format(scene.center[1]), y = ("%.1f"):format(scene.center[2]), z = ("%.1f"):format(scene.center[3]) })),
        { label = T("v_scenemanager.editor.validation", { count = #(scene.validation or {}) }) .. (errors > 0 and " ✖" or ""),
          title = T("v_scenemanager.editor.validation_title"), items = validationItems(scene) },
    }
    if #(scene.issues or {}) > 0 then
        items[#items + 1] = { label = T("v_scenemanager.editor.issues", { count = #scene.issues }), title = T("v_scenemanager.editor.issues_title"),
            items = sceneIssueItems(scene), desc = scene.issues[1].comment }
    end
    items[#items + 1] = item(T("v_scenemanager.editor.teleport"), "teleport", nil, T("v_scenemanager.editor.teleport_desc"))
    items[#items + 1] = item(T("v_scenemanager.editor.save"), "save", nil, scene.file and scene.target or T("v_scenemanager.editor.never_saved"))
    items[#items + 1] = item(T("v_scenemanager.editor.save_as"), "saveas", nil, T("v_scenemanager.editor.save_as_desc", { file = scene.target }))
    items[#items + 1] = confirm(T("v_scenemanager.editor.leave"), "leave", T("v_scenemanager.editor.leave_desc"))
    items[#items + 1] = confirm(T("v_scenemanager.editor.exit"), "exit")
    return { title = T("v_scenemanager.editor.scene_title", { name = name }) .. (scene.dirty and " *" or ""), items = items }
end

-- "ls_heartattack2" before "ls_heartattack10"
local function naturalKey(text)
    return (tostring(text):lower():gsub("%d+", function(d) return ("%08d"):format(tonumber(d)) end))
end

local function needsText(needs)
    if type(needs) ~= "table" then return "" end
    return ("EMS %d · PD %d"):format(needs.ems or 0, needs.pd or 0)
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
            items[#items + 1] = item(s.name .. (s.locked and (" " .. T("v_scenemanager.editor.in_use_mark")) or "") .. (s.valid == false and " ✖" or ""),
                "load", s.name, T("v_scenemanager.editor.scene_row", { title = s.title or "", peds = s.peds or 0, vehicles = s.vehicles or 0,
                    needs = needsText(s.needs) }))
        end
        return items
    end
    return build(root)
end

-- Check issues: one button per flagged scene, its description = the issue text
local function issuesMenu()
    local items = {}
    for _, row in ipairs(state.issues or {}) do
        local first = row.issues[1]
        local desc = first.comment .. "\n" .. T("v_scenemanager.editor.issue_meta", { by = first.byName or "?", at = dateText(first.at),
            source = T("v_scenemanager.flag.source_" .. tostring(first.source)) })
        if #row.issues > 1 then desc = desc .. "\n" .. T("v_scenemanager.editor.issue_more", { count = #row.issues - 1 }) end
        items[#items + 1] = item(row.name .. (#row.issues > 1 and (" (" .. #row.issues .. ")") or "")
            .. (row.locked and (" " .. T("v_scenemanager.editor.in_use_mark")) or ""), "issue_load", row.name, desc)
    end
    if #items == 0 then items[1] = item(T("v_scenemanager.editor.no_issues"), "noop") end
    return items
end

local function mainMenu()
    local list = sceneTree()
    if #list == 0 then list[1] = item(T("v_scenemanager.editor.no_scenes"), "noop") end
    return {
        title = T("v_scenemanager.editor.title"),
        items = {
            item(T("v_scenemanager.editor.new_scene_item"), "new", nil, T("v_scenemanager.editor.new_scene_desc")),
            { label = T("v_scenemanager.editor.load_scene", { count = #state.scenes }), title = T("v_scenemanager.editor.load_scene_title"), items = list },
            { label = T("v_scenemanager.editor.check_issues", { count = #(state.issues or {}) }), title = T("v_scenemanager.editor.check_issues_title"),
              items = issuesMenu(), desc = T("v_scenemanager.editor.check_issues_desc") },
            item(T("v_scenemanager.editor.exit"), "exit"),
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

local renderEditor -- onClientRender handler, attached only while the editor is on

addEventHandler("vsm:editorState", resourceRoot, function(newState)
    local wasOn = state ~= false
    state = newState or false
    if state and not wasOn then
        bindKey(VSM.KEY_MENU, "down", onMenuKey)
        addEventHandler("onClientRender", root, renderEditor)
    elseif not state and wasOn then
        unbindKey(VSM.KEY_MENU, "down", onMenuKey)
        removeEventHandler("onClientRender", root, renderEditor)
        if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
        menuId = nil
    end
end)

addEventHandler("vsm:askText", resourceRoot, function(id, title, maxLen, default)
    if menuId and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    local token = exports.ui_core:openTextInput(title, maxLen, default)
    if token then
        pendingText[token] = id
    else
        triggerServerEvent("vsm:textResult", resourceRoot, id, false)
    end
end)

addEventHandler("ui_core:textInputResult", root, function(token, text)
    local id = pendingText[token]
    if not id then return end
    pendingText[token] = nil
    triggerServerEvent("vsm:textResult", resourceRoot, id, text)
end)

addEventHandler("vsm:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(title, text)
end)

---------------------------------------------------------------- labels

-- text of a 3D label / list row from the label data of server/editor.lua (oneLine: " | " instead of new lines)
function LabelText(d, oneLine)
    local lines = {}
    if d.kind == "vehicle" then
        local opts = {}
        for _, k in ipairs({ "engine", "lightsOn", "sirens", "locked", "frozen", "tow", "stolen" }) do
            if d[k] then opts[#opts + 1] = T("v_scenemanager.label." .. k) end
        end
        lines[1] = ("%s  %s (%d hp)"):format(d.id, getVehicleNameFromModel(d.model) or tostring(d.model), d.health or 1000)
        if #opts > 0 then lines[2] = table.concat(opts, ", ") end
    else
        local head = ("%s  %s  %s"):format(d.id, T("v_scenemanager.label.skin", { skin = d.skin }), T("v_scenemanager.role." .. tostring(d.role)))
        local anim = vsmAnimById(d.anim)
        if d.vehicle then
            head = head .. "  " .. T("v_scenemanager.label.in_vehicle", { vehicle = d.vehicle, seat = d.seat or 0 })
        elseif anim and anim.id ~= "none" then
            head = head .. "  " .. T(anim.label)
        end
        lines[1] = head
        if d.ai then
            local a = d.ai
            if d.role == "fighter" then lines[#lines + 1] = T("v_scenemanager.label.fighter", { side = tostring(a.side):upper() })
            elseif d.role == "hostile" then lines[#lines + 1] = T("v_scenemanager.label.hostile", { targets = T("v_scenemanager.ai.targets_" .. tostring(a.targets)) }) end
        end
        if d.record then lines[#lines + 1] = T(d.warrant and "v_scenemanager.label.record_warrant" or "v_scenemanager.label.record") end
        for _, inj in ipairs(d.injuries or {}) do
            lines[#lines + 1] = ("%s (%s)"):format(T(vsmInjuryLabel(inj.type)), T(VSM_SEVERITY[inj.severity] or "?"))
        end
        for _, key in ipairs(VSM_STATE_ORDER) do
            if d.state and d.state[key] ~= nil then
                lines[#lines + 1] = ("%s: %s"):format(T(VSM_STATE[key].label), vsmStateValueLabel(key, d.state[key]))
            end
        end
        if #lines == 1 and d.role == "patient" then lines[2] = T("v_scenemanager.label.no_injuries") end
    end
    return table.concat(lines, oneLine and " | " or "\n")
end

---------------------------------------------------------------- drawing

local function drawBanner()
    local w, h = 460 * scale, 62 * scale
    local x, y = (sw - w) / 2, 18 * scale
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 16, 190))
    dxDrawRectangle(x, y, w, 3 * scale, tocolor(229, 72, 77, 255))
    dxDrawText(T("v_scenemanager.editor.title"), x, y + 6 * scale, x + w, y + 34 * scale,
        tocolor(255, 255, 255), 1.6 * scale, "default-bold", "center", "center")
    local sub = T("v_scenemanager.editor.banner_hint", { key = VSM.KEY_MENU:upper() })
    if state.scene then
        sub = sub .. "   |   " .. (state.scene.file or T("v_scenemanager.editor.unsaved")) .. (state.scene.dirty and " *" or "")
    end
    dxDrawText(sub, x, y + 34 * scale, x + w, y + h - 4 * scale,
        tocolor(200, 205, 215), 1.05 * scale, "default", "center", "center")
end

local function drawLabels()
    local px, py, pz = getElementPosition(localPlayer)
    local dim = getElementDimension(localPlayer)
    for _, kind in ipairs({ "vehicle", "ped" }) do
        for _, element in ipairs(getElementsByType(kind, root, true)) do
            local data = getElementDimension(element) == dim and getElementData(element, "vsm.label")
            if type(data) == "table" then
                local x, y, z = getElementPosition(element)
                local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                if dist <= VSM.LABEL_RANGE then
                    local sx, sy = getScreenFromWorldPosition(x, y, z + (kind == "ped" and 1.1 or 1.4), 0.06)
                    if sx then
                        local label = LabelText(data)
                        local s = math.max(0.6, 1.1 - dist / VSM.LABEL_RANGE * 0.5) * scale
                        local threat = data.role == "hostile" or data.role == "fighter"
                        local color = kind == "ped" and (threat and tocolor(255, 170, 60) or tocolor(255, 120, 120)) or tocolor(120, 190, 255)
                        dxDrawText(label, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), s, "default-bold", "center", "bottom")
                        dxDrawText(label, sx, sy, sx, sy, color, s, "default-bold", "center", "bottom")
                    end
                end
            end
        end
    end
end

renderEditor = function()
    drawLabels()
    drawBanner()
end
