-- Every creator menu is a ui_inac temp menu. Item values are small arrays:
-- { action, arg1, arg2 } and are dispatched in onSelect below.

Menus = { rootId = nil, kind = nil, item = nil, leaves = {} }

local L = CREATOR.LIMITS
local SCALES = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }
local ALPHAS = { 255, 200, 150, 100, 50 }

local function leaf(label, value, desc, extra)
    local item = { label = label, value = value, desc = desc }
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

local function sub(label, items, desc, title)
    return { label = label, items = items, desc = desc, title = title or label:upper() }
end

local function info(label, desc)
    return leaf(label, { "none" }, desc, { closeOnSelect = false })
end

-- remembers the ui_inac path of every leaf (for live tick updates)
local function indexLeaves(items, prefix, out)
    for i, item in ipairs(items) do
        local path = prefix == "" and tostring(i) or (prefix .. "/" .. i)
        if item.items then indexLeaves(item.items, path, out)
        elseif type(item.value) == "table" then out[#out + 1] = { path = path, value = item.value } end
    end
    return out
end

local function open(kind, title, items)
    Menus.kind = kind
    Menus.leaves = indexLeaves(items, "", {})
    Menus.rootId = inac:createTempMenu({ title = title, items = items })
    if not Menus.rootId then Menus.kind = nil end
    return Menus.rootId
end

function Menus.close()
    if Menus.rootId then inac:closeTempMenu() end
end

function Menus.isOpen()
    return Menus.rootId ~= nil and inac:isTempMenuOpen()
end

-- Moves the tick inside one exclusive group (vehicle, weapon, scale ...).
local function retick(group, selected)
    for _, entry in ipairs(Menus.leaves) do
        if entry.value[1] == group then
            inac:updateTempMenuItem(entry.path, { checked = entry.value[2] == selected })
        end
    end
end

--------------------------------------------------------------------------------
-- start menu + game lists
--------------------------------------------------------------------------------

function Menus.openStart()
    local items = {
        leaf("New Race", { "new", "race" }, "Checkpoint race with one vehicle model"),
        leaf("New Deathmatch", { "new", "deathmatch" }, "Last player standing"),
        leaf("My Games", { "list", "mine" }, "Open, delete or check the status of your games"),
    }
    if Editor.info.admin then
        items[#items + 1] = leaf("Community Games", { "list", "all" }, "Every player-made game (admin)")
        items[#items + 1] = leaf("Official Games", { "list", "official" }, "The server's own games (admin)")
    end
    items[#items + 1] = leaf("Exit Creator", { "exit" })
    open("start", "JOB CREATOR", items)
end

local function statusText(entry)
    if entry.official then return entry.pending and "Official, draft not published yet" or "Official" end
    if entry.published and entry.pending then return "Published, newer changes saved" end
    if entry.published then return "Published" end
    return "Private"
end

addEvent("jobcreator:list", true)
addEventHandler("jobcreator:list", resourceRoot, function(scope, list)
    if not Editor.active then return end
    Menus.lastScope = scope
    local items = {}
    for _, entry in ipairs(list) do
        local actions = { leaf("Edit", { "load", entry.id }) }
        if entry.official then
            if entry.pending then actions[#actions + 1] = leaf("Publish draft", { "manage", entry.id, "publish" }) end
        elseif Editor.info.admin then
            if entry.published then
                if entry.pending then actions[#actions + 1] = leaf("Publish changes", { "manage", entry.id, "publish" }) end
                actions[#actions + 1] = leaf("Unpublish", { "manage", entry.id, "unpublish" })
            else
                actions[#actions + 1] = leaf("Publish", { "manage", entry.id, "publish" })
            end
        end
        if not entry.official and (Editor.info.admin or not entry.published) then
            actions[#actions + 1] = sub("Delete", { leaf("Yes, delete " .. tostring(entry.name), { "manage", entry.id, "delete" }) })
        end
        local typeName = entry.type == "race" and "Race" or "Deathmatch"
        items[#items + 1] = sub(tostring(entry.name or entry.id), actions,
            typeName .. "  ·  " .. statusText(entry) .. "  ·  by " .. tostring(entry.owner), tostring(entry.name or entry.id):upper())
    end
    if #items == 0 then items[1] = info("No games yet") end
    items[#items + 1] = leaf("Back", { "start" })
    local titles = { all = "COMMUNITY GAMES", official = "OFFICIAL GAMES" }
    open("list", titles[scope] or "MY GAMES", items)
end)

addEvent("jobcreator:managed", true)
addEventHandler("jobcreator:managed", resourceRoot, function()
    if Editor.active and not Editor.doc then
        triggerServerEvent("jobcreator:requestList", resourceRoot, Menus.lastScope or "mine")
    end
end)

--------------------------------------------------------------------------------
-- editor hub
--------------------------------------------------------------------------------

local function numberList(group, values, current, suffix)
    local items = {}
    for _, v in ipairs(values) do
        items[#items + 1] = leaf(tostring(v) .. (suffix or ""), { group, v }, nil, { checked = v == current, closeOnSelect = false })
    end
    return items
end

local function range(a, b)
    local t = {}
    for i = a, b do t[#t + 1] = i end
    return t
end

local function objectMenu()
    local cats = {}
    for _, cat in ipairs(CATALOG.objects) do
        local items = {}
        for _, entry in ipairs(cat.items) do
            items[#items + 1] = leaf(entry[2], { "place", "object", entry[1] }, "Model " .. entry[1])
        end
        cats[#cats + 1] = sub(cat.name, items)
    end
    return sub("Objects", cats, #Editor.doc.objects .. " / " .. L.objects .. " placed  ·  click an object to edit it")
end

local function vehicleMenu()
    local current = Editor.doc.race.vehicles[1]
    local names = Editor.info.vehicleNames or {}
    local cats = {}
    for _, cat in ipairs(CATALOG.vehicles) do
        local items = {}
        for _, model in ipairs(cat.items) do
            items[#items + 1] = leaf(names[model] or tostring(model), { "vehicle", model }, nil, { checked = model == current, closeOnSelect = false })
        end
        cats[#cats + 1] = sub(cat.name, items)
    end
    return sub("Vehicle", cats, "Every racer gets this vehicle  ·  now: " .. (names[current] or tostring(current)))
end

local function weaponMenu()
    local current = Editor.doc.deathmatch.weapon
    local cats = {}
    for _, cat in ipairs(CATALOG.weapons) do
        local items = {}
        for _, id in ipairs(cat.items) do
            items[#items + 1] = leaf(getWeaponNameFromID(id) or tostring(id), { "weapon", id }, nil, { checked = id == current, closeOnSelect = false })
        end
        cats[#cats + 1] = sub(cat.name, items)
    end
    return sub("Weapon", cats, "now: " .. (getWeaponNameFromID(current) or tostring(current)))
end

function Menus.openHub()
    local doc = Editor.doc
    if not doc then return Menus.openStart() end
    Tools.cancel()
    local admin = Editor.info.admin
    local isRace = doc.type == "race"
    local problems = Editor.problems()

    local status = (isRace and "Race" or "Deathmatch") .. "  ·  " .. (Editor.dirty and "Unsaved changes" or "Saved")
    local official = Editor.meta and Editor.meta.official
    if official then
        status = status .. "  ·  Official" .. (Editor.meta.pending and ", draft" or "")
    elseif Editor.meta and Editor.meta.published then
        status = status .. "  ·  Published"
    end
    local items = { info(status, #problems == 0 and "Ready to publish" or (#problems .. " thing(s) to check, see Check Problems")) }

    local place = { leaf("Spawnpoint", { "place", "spawn" }, #Editor.spawnList() .. " placed, " .. doc.maxPlayers .. " needed") }
    if isRace then
        place[#place + 1] = leaf("Checkpoint", { "place", "checkpoint" }, #doc.race.checkpoints .. " placed  ·  added at the end of the route")
        place[#place + 1] = leaf("Finish", { "place", "finish" }, doc.race.finish and "Placed  ·  placing again moves it" or "Not placed yet")
        place[#place + 1] = leaf("Finish camera (current view)", { "finishcam" }, "Scoreboard camera after the race")
    end
    if admin then
        place[#place + 1] = leaf("Job marker (admin)", { "place", "marker" }, "World marker + blip for joining the game")
    end
    items[#items + 1] = sub("Place", place)
    items[#items + 1] = objectMenu()

    if isRace then
        items[#items + 1] = sub("Race Settings", { vehicleMenu() })
    else
        local dm = doc.deathmatch
        items[#items + 1] = sub("Deathmatch Settings", {
            weaponMenu(),
            sub("Ammo", numberList("ammo", CATALOG.ammo, dm.ammo), "now: " .. dm.ammo),
            sub("Armour", numberList("armour", CATALOG.armour, dm.armour), "now: " .. dm.armour),
        })
    end

    items[#items + 1] = sub("Game Info", {
        leaf("Name", { "name" }, doc.name),
        leaf("Description", { "desc" }, doc.description ~= "" and doc.description or "(empty)"),
        sub("Min Players", numberList("min", range(1, L.maxPlayers), doc.minPlayers), "now: " .. doc.minPlayers),
        sub("Max Players", numberList("max", range(1, L.maxPlayers), doc.maxPlayers), "now: " .. doc.maxPlayers),
    })

    if isRace then
        items[#items + 1] = sub("Test", {
            leaf("From the start", { "test", "start" }, "Spawnpoint #1, every checkpoint"),
            leaf("From here", { "test", "here" }, "Your position, from the nearest checkpoint"),
        }, "F6 ends the test")
    else
        items[#items + 1] = leaf("Test", { "test", "here" }, "Spawn here with the weapon  ·  F6 ends the test")
    end

    items[#items + 1] = sub("Thumbnail", {
        leaf("Take photo", { "photo" }, "Free camera, HUD hidden, SPACE takes the picture"),
        leaf("Remove photo", { "photoRemove" }),
    }, Editor.hasThumb and "Has a photo" or "No photo yet")

    local problemItems = {}
    for _, text in ipairs(problems) do problemItems[#problemItems + 1] = info(text) end
    if #problemItems == 0 then problemItems[1] = info("Nothing found") end
    problemItems[#problemItems + 1] = leaf("Check with the server", { "validate" }, "The same check Publish runs")
    items[#items + 1] = sub("Check Problems", problemItems, #problems == 0 and "Nothing found" or (#problems .. " found"))

    items[#items + 1] = leaf("Undo", { "undo" }, "Ctrl+Z", { closeOnSelect = false })
    items[#items + 1] = leaf("Redo", { "redo" }, "Ctrl+Y", { closeOnSelect = false })
    items[#items + 1] = leaf("Save", { "save" }, official and "Saves a draft, the live game changes on Publish"
        or (admin and "Saves the private copy (not live)" or "Only admins can publish games"))
    if admin then
        items[#items + 1] = leaf("Save & Publish", { "publish" }, "Makes this version live")
        if Editor.meta and Editor.meta.published and not official then
            items[#items + 1] = leaf("Unpublish", { "unpublish" }, "Removes it from the job list")
        end
    end
    items[#items + 1] = sub("Close Game", {
        leaf("Save and close", { "close", "save" }),
        leaf("Close without saving", { "close", "discard" }),
    })
    items[#items + 1] = sub("Exit Creator", {
        leaf("Save and exit", { "exit", "save" }),
        leaf("Exit without saving", { "exit", "discard" }),
    })
    open("hub", doc.name:upper(), items)
end

--------------------------------------------------------------------------------
-- item menu (selected element)
--------------------------------------------------------------------------------

function Menus.openItem(item)
    if not item then return end
    Tools.cancel()
    Editor.selected = item
    local K, ref = Kinds[item.kind], item.ref
    local items = {}
    if not K.fixed then items[#items + 1] = leaf("Move", { "move" }, "Follows the cursor  ·  arrows / PgUp / PgDn fine-tune  ·  Enter to drop") end
    if item.kind == "object" or item.kind == "spawn" then items[#items + 1] = leaf("Duplicate", { "dup" }) end
    if item.kind == "object" then
        items[#items + 1] = sub("Scale", numberList("scale", SCALES, ref.scale or 1, "x"), "now: " .. (ref.scale or 1) .. "x")
        items[#items + 1] = sub("Transparency", numberList("alpha", ALPHAS, ref.alpha or 255), "255 = solid")
        items[#items + 1] = leaf("Collisions", { "toggle", "collisions" }, "Off = vehicles and players pass through", { checked = ref.collisions ~= false, closeOnSelect = false })
        items[#items + 1] = leaf("Double-sided", { "toggle", "doublesided" }, "Draw the back faces too", { checked = ref.doublesided == true, closeOnSelect = false })
    elseif item.kind == "checkpoint" or item.kind == "finish" then
        items[#items + 1] = sub("Size", numberList("size", CATALOG.checkpointSizes, ref[4] or 5), "now: " .. (ref[4] or 5))
        if item.kind == "checkpoint" then items[#items + 1] = leaf("Insert checkpoints after this", { "insertAfter" }) end
    elseif item.kind == "camera" then
        items[#items + 1] = leaf("Set to the current view", { "finishcam" })
        items[#items + 1] = leaf("Preview", { "camPreview" }, "3 seconds")
    end
    items[#items + 1] = sub("Delete", { leaf("Yes, delete", { "delete" }) })

    local title = K.label
    if item.kind == "object" then title = CATALOG.objectName[ref.model] or title
    elseif item.kind == "spawn" or item.kind == "checkpoint" then title = title .. " #" .. item.index end
    open("item", title:upper(), items)
    Menus.item = item
end

-- live previews of scale / transparency / size while scrolling
local function resetPreview()
    local item = Menus.item
    if item and isElement(item.element) and Editor.doc then
        Kinds[item.kind].apply(item.element, item.ref, item.extra)
    end
end

addEventHandler("ui_inac:tempMenuHover", root, function(rootId, value)
    if rootId ~= Menus.rootId or Menus.kind ~= "item" then return end
    resetPreview()
    local item = Menus.item
    if not item or type(value) ~= "table" or not isElement(item.element) then return end
    if value[1] == "scale" then setObjectScale(item.element, value[2])
    elseif value[1] == "alpha" then setElementAlpha(item.element, value[2])
    elseif value[1] == "size" and isElement(item.extra) then setMarkerSize(item.extra, value[2]) end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(rootId)
    if rootId ~= Menus.rootId then return end
    if Menus.kind == "item" then resetPreview() end
    Menus.rootId, Menus.kind, Menus.item = nil, nil, nil
end)

--------------------------------------------------------------------------------
-- text input
--------------------------------------------------------------------------------

local textToken, textField

local function askText(field, title, max, default)
    textField = field
    textToken = uicore:openTextInput(title, max, default)
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= textToken then return end
    textToken = nil
    if text and Editor.doc then
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if textField == "name" and text ~= "" then
            Editor.change(function(doc) doc.name = text end)
        elseif textField == "desc" then
            Editor.change(function(doc) doc.description = text end)
        end
    end
    if Editor.doc then Menus.openHub() end
end)

--------------------------------------------------------------------------------
-- dispatch
--------------------------------------------------------------------------------

local function nearestCheckpoint(x, y, z)
    local best, bestDist = 1, math.huge
    for i, cp in ipairs(Editor.doc.race.checkpoints) do
        local d = getDistanceBetweenPoints3D(x, y, z, cp[1], cp[2], cp[3])
        if d < bestDist then best, bestDist = i, d end
    end
    return best
end

local actions = {}

actions.none = function() end
actions.start = function() Menus.openStart() end
actions.new = function(v) triggerServerEvent("jobcreator:new", resourceRoot, v[2]) end
actions.list = function(v) triggerServerEvent("jobcreator:requestList", resourceRoot, v[2]) end
actions.load = function(v) triggerServerEvent("jobcreator:load", resourceRoot, v[2]) end
actions.manage = function(v) triggerServerEvent("jobcreator:manage", resourceRoot, v[2], v[3]) end

actions.exit = function(v)
    if v[2] == "save" then Editor.save(false, Editor.exit) else Editor.exit() end
end
actions.close = function(v)
    if v[2] == "save" then Editor.save(false, Editor.closeGame) else Editor.closeGame() end
end
actions.save = function() Editor.save(false) end
actions.publish = function() Editor.save(true) end
actions.unpublish = function()
    if Editor.meta and Editor.meta.id then
        triggerServerEvent("jobcreator:manage", resourceRoot, Editor.meta.id, "unpublish")
        Editor.meta.published = false
    end
end
actions.undo = function() Editor.undoStep() end
actions.redo = function() Editor.redoStep() end
actions.validate = function() triggerServerEvent("jobcreator:validate", resourceRoot, Editor.doc) end

actions.place = function(v)
    if Editor.testing then return end
    Tools.place(v[2], { model = v[3] })
    notify("Click (or LMB at the crosshair) to place  ·  wheel rotates  ·  Backspace stops")
end
actions.finishcam = function() Ops.setFinishCamera() end

actions.vehicle = function(v)
    Editor.change(function(doc) doc.race.vehicles = { v[2] } end)
    View.rebuildSpawns()
    retick("vehicle", v[2])
end
actions.weapon = function(v) Editor.change(function(doc) doc.deathmatch.weapon = v[2] end) retick("weapon", v[2]) end
actions.ammo = function(v) Editor.change(function(doc) doc.deathmatch.ammo = v[2] end) retick("ammo", v[2]) end
actions.armour = function(v) Editor.change(function(doc) doc.deathmatch.armour = v[2] end) retick("armour", v[2]) end
actions.min = function(v)
    Editor.change(function(doc)
        doc.minPlayers = v[2]
        if doc.maxPlayers < v[2] then doc.maxPlayers = v[2] end
    end)
    retick("min", v[2])
end
actions.max = function(v)
    Editor.change(function(doc)
        doc.maxPlayers = v[2]
        if doc.minPlayers > v[2] then doc.minPlayers = v[2] end
    end)
    retick("max", v[2])
end
actions.name = function() askText("name", "Game name", L.name, Editor.doc.name) end
actions.desc = function() askText("desc", "Description", L.description, Editor.doc.description) end

actions.test = function(v)
    if v[2] == "start" then
        local spawn = Editor.spawnList()[1]
        if not spawn then notify("Place spawnpoint #1 first.") return end
        Test.start(spawn[1], spawn[2], spawn[3], spawn[4] or 0, 1)
    else
        if Editor.camMode == "free" then Freecam.stop() end
        local x, y, z = getElementPosition(localPlayer)
        local rz = select(3, getElementRotation(localPlayer))
        local first = Editor.doc.race and nearestCheckpoint(x, y, z) or 1
        Test.start(x, y, z, rz, first)
    end
end
actions.photo = function() Photo.start() end
actions.photoRemove = function() Photo.remove() end

-- item menu
actions.move = function() Tools.move(Editor.selected) end
actions.dup = function() Ops.duplicate(Editor.selected) end
actions.delete = function() Ops.delete(Editor.selected) end
actions.scale = function(v)
    local item = Menus.item
    if item then Ops.setField(item, "scale", v[2] ~= 1 and v[2] or nil) retick("scale", v[2]) end
end
actions.alpha = function(v)
    local item = Menus.item
    if item then Ops.setField(item, "alpha", v[2] < 255 and v[2] or nil) retick("alpha", v[2]) end
end
actions.size = function(v)
    local item = Menus.item
    if item then Ops.setField(item, 4, v[2]) retick("size", v[2]) end
end
actions.toggle = function(v, path)
    local item = Menus.item
    if not item then return end
    local key = v[2]
    local on
    if key == "collisions" then
        on = item.ref.collisions == false
        Ops.setField(item, "collisions", (not on) and false or nil)
    else
        on = item.ref.doublesided ~= true
        Ops.setField(item, "doublesided", on or nil)
    end
    inac:updateTempMenuItem(path, { checked = on })
end
actions.insertAfter = function()
    local item = Editor.selected
    if item then Tools.place("checkpoint", { insertAt = item.index + 1 }) end
end
actions.camPreview = function() Ops.previewCamera(Editor.doc.race.finishCamera) end

addEventHandler("ui_inac:tempMenuSelect", root, function(rootId, value, path)
    if rootId ~= Menus.rootId or type(value) ~= "table" then return end
    local fn = actions[value[1]]
    if fn then fn(value, path) end
end)

addEvent("jobcreator:validated", true)
addEventHandler("jobcreator:validated", resourceRoot, function(ok, err)
    notify(ok and "The server found no problems: ready to publish." or ("Server check: " .. tostring(err)))
end)
