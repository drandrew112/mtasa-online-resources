if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Editor state, the game document, undo / redo and the session lifecycle.
--
-- Editor.doc is the game in v_jobmanager's JSON format (the creator's contract):
-- every tool edits it and View.sync() mirrors it into client-side elements.

uicore = exports.ui_core
inac = exports.ui_inac
iobj = exports.ui_interactobject

Editor = {
    active = false,     -- a creator session is open
    info = nil,         -- { admin, account, vehicleNames, dimension }
    doc = nil,          -- the game being edited (nil = start menu)
    meta = nil,         -- { id, published, pending, owner }
    dirty = false,
    undo = {}, redo = {},
    camMode = "foot",   -- "foot" | "free"
    tool = nil,         -- active tool (client/tools.lua)
    selected = nil,     -- View item
    testing = false,
    photo = false,
    hasThumb = false,
}

local MAX_UNDO = 50

-- Per-frame handlers of the editor (view, tools, keys, photo, hud): attached only while a
-- creator session is open.
local frameHandlers = {}
local framesOn = false

function Editor.onFrame(eventName, fn)
    frameHandlers[#frameHandlers + 1] = { eventName, fn }
    if framesOn then addEventHandler(eventName, root, fn) end
end

local function setFrames(on)
    if on == framesOn then return end
    framesOn = on
    for _, h in ipairs(frameHandlers) do
        if on then
            addEventHandler(h[1], root, h[2])
        else
            removeEventHandler(h[1], root, h[2])
        end
    end
end

function notify(text)
    uicore:addNotification(L("v_jobcreator.core.job_creator"), text)
end

function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end

-- Panels, chat, console or the text input own the keyboard right now.
function inputBlocked()
    return isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive()
        or getElementData(localPlayer, "textInputOpen") or getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "showChatInput") or getElementData(localPlayer, "phoneOpen")
end

--------------------------------------------------------------------------------
-- undo / redo
--------------------------------------------------------------------------------

-- Call BEFORE mutating the doc, or pass a snapshot taken earlier (move tool).
function Editor.pushUndo(snapshot)
    table.insert(Editor.undo, snapshot or deepCopy(Editor.doc))
    if #Editor.undo > MAX_UNDO then table.remove(Editor.undo, 1) end
    Editor.redo = {}
    Editor.dirty = true
end

-- One undoable change: fn mutates Editor.doc, then the view is synced.
function Editor.change(fn)
    if not Editor.doc then return end
    Editor.pushUndo()
    fn(Editor.doc)
    View.sync()
end

local function swapHistory(from, to)
    if not Editor.doc or #from == 0 then return false end
    Tools.cancel()
    table.insert(to, deepCopy(Editor.doc))
    Editor.doc = table.remove(from)
    Editor.dirty = true
    Editor.selected = nil
    View.sync()
    return true
end

function Editor.undoStep()
    if swapHistory(Editor.undo, Editor.redo) then notify("Undone.") end
end

function Editor.redoStep()
    if swapHistory(Editor.redo, Editor.undo) then notify("Redone.") end
end

--------------------------------------------------------------------------------
-- document helpers
--------------------------------------------------------------------------------

function Editor.spawnList()
    local doc = Editor.doc
    if not doc then return {} end
    if doc.type == "race" then return doc.race.spawnpoints end
    return doc.deathmatch.spawnpoints
end

-- Human-readable list of what still blocks publishing (the server runs the
-- authoritative check on Publish / "Check with server").
function Editor.problems()
    local doc, list = Editor.doc, {}
    if not doc then return list end
    if doc.name:find("^Untitled") then list[#list + 1] = L("v_jobcreator.core.give_game_name") end
    local spawns = #Editor.spawnList()
    if spawns < doc.maxPlayers then
        list[#list + 1] = L("v_jobcreator.core.spawnpoints_placed_needed_max_players", { spawns = spawns, max_players = doc.maxPlayers })
    end
    if doc.type == "race" then
        if not doc.race.finish then list[#list + 1] = L("v_jobcreator.core.place_finish") end
        if #doc.race.checkpoints == 0 then list[#list + 1] = L("v_jobcreator.core.no_checkpoints_yet_optional") end
    end
    if not Editor.hasThumb then list[#list + 1] = L("v_jobcreator.core.no_thumbnail_yet_optional") end
    return list
end

-- A point to drop the player at when a game is opened.
local function focusPoint(doc)
    local spawn = Editor.spawnList()[1]
    if spawn then return spawn[1], spawn[2], spawn[3] end
    if doc.race and doc.race.checkpoints[1] then return unpack(doc.race.checkpoints[1]) end
    if doc.objects[1] then return doc.objects[1].x, doc.objects[1].y, doc.objects[1].z end
    if doc.marker then return unpack(doc.marker) end
end

--------------------------------------------------------------------------------
-- session lifecycle
--------------------------------------------------------------------------------

addEvent("jobcreator:opened", true)
addEventHandler("jobcreator:opened", resourceRoot, function(info)
    Editor.active, Editor.info = true, info
    Editor.doc, Editor.meta, Editor.dirty = nil, nil, false
    setFrames(true)
    setElementData(localPlayer, "jobCreator", true, false)
    Keys.bind()
    Interact.register()
    Menus.openStart()
end)

addEvent("jobcreator:loaded", true)
addEventHandler("jobcreator:loaded", resourceRoot, function(game, meta)
    if not Editor.active then return end
    Tools.cancel()
    -- lists may arrive as nil when empty
    game.objects = game.objects or {}
    if game.type == "race" then
        game.race = game.race or {}
        game.race.vehicles = game.race.vehicles or { 411 }
        game.race.spawnpoints = game.race.spawnpoints or {}
        game.race.checkpoints = game.race.checkpoints or {}
    else
        game.deathmatch = game.deathmatch or {}
        game.deathmatch.spawnpoints = game.deathmatch.spawnpoints or {}
    end
    Editor.doc, Editor.meta = game, meta
    Editor.dirty, Editor.undo, Editor.redo, Editor.selected = false, {}, {}, nil
    Photo.clear()
    View.sync()
    local x, y, z = focusPoint(game)
    if x then
        if Editor.camMode == "free" then Freecam.setPosition(x, y, z + 15) else setElementPosition(localPlayer, x, y, z + 1) end
    end
    notify(L("v_jobcreator.core.press_for_menu", { id = (meta.id and L("v_jobcreator.core.opened") or L("v_jobcreator.core.new")), type = (game.type == "race" and "race" or "deathmatch"), name = game.name, menu = CREATOR.KEYS.menu:upper() }))
end)

addEvent("jobcreator:saved", true)
addEventHandler("jobcreator:saved", resourceRoot, function(meta)
    Editor.meta = meta
    Editor.dirty = false
    if Editor.afterSave then
        local fn = Editor.afterSave
        Editor.afterSave = nil
        fn()
    end
end)

addEvent("jobcreator:notify", true)
addEventHandler("jobcreator:notify", resourceRoot, function(_, text) notify(text) end)

function Editor.save(publish, afterSave)
    if not Editor.doc then return end
    Editor.afterSave = afterSave
    triggerServerEvent("jobcreator:save", resourceRoot, Editor.doc, publish == true)
end

-- Back to the start menu (the doc is dropped).
function Editor.closeGame()
    Tools.cancel()
    triggerServerEvent("jobcreator:closeGame", resourceRoot)
    Editor.doc, Editor.meta, Editor.dirty, Editor.selected = nil, nil, false, nil
    Editor.undo, Editor.redo = {}, {}
    Photo.clear()
    View.clear()
    Menus.openStart()
end

function Editor.exit()
    triggerServerEvent("jobcreator:close", resourceRoot)
end

addEvent("jobcreator:closed", true)
addEventHandler("jobcreator:closed", resourceRoot, function()
    Tools.cancel()
    Test.cleanup()
    Photo.stop(true)
    Photo.clear()
    if Editor.camMode == "free" then Freecam.stop(true) end
    View.clear()
    Menus.close()
    Interact.unregister()
    Keys.unbind()
    Editor.active, Editor.doc, Editor.meta, Editor.info = false, nil, nil, nil
    setFrames(false)
    setElementData(localPlayer, "jobCreator", false, false)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if not Editor.active then return end
    if Editor.camMode == "free" then Freecam.stop(true) end
    Photo.stop(true)
    setElementData(localPlayer, "jobCreator", false, false)
end)

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function jobcreatorOpen(gameId)
    if Editor.active then return false end
    triggerServerEvent("jobcreator:open", resourceRoot, type(gameId) == "string" and gameId or nil)
    return true
end

function jobcreatorClose()
    if not Editor.active then return false end
    Editor.exit()
    return true
end

function jobcreatorIsActive()
    return Editor.active
end
