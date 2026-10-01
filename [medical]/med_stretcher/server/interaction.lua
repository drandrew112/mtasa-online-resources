-- ui_interactobject menu on every stretcher object. There is no separate ambulance menu: while
-- the stretcher is stowed, its own menu is reached at the rear of the ambulance. The items follow
-- the stretcher state; selections are re-checked here before server/stretcher.lua acts.

addEvent("onInteractMenuSelect")

local IO_RESOURCE = "ui_interactobject"
local menuOwner = {}  -- menu id -> stretcher record

local function isIORunning()
    local res = getResourceFromName(IO_RESOURCE)
    return res and getResourceState(res) == "running"
end

-- ---------------------------------------------------------------------------------------------
-- Medic role (medsys). With the role required, only medics see and use the stretcher menus.
-- ---------------------------------------------------------------------------------------------

local MEDSYS_RESOURCE = "medsys"
local roleRequired     -- nil = not asked yet; medsys is asked once (again only if it restarts)

addEvent("onPlayerMedicChange") -- fired by medsys

local function isMedsysRunning()
    local res = getResourceFromName(MEDSYS_RESOURCE)
    return res and getResourceState(res) == "running"
end

local function isRoleRequired()
    if roleRequired == nil and isMedsysRunning() then
        roleRequired = exports.medsys:isMedicRoleRequired() == true
    end
    return roleRequired == true
end

function hasStretcherAccess(player)
    if not isRoleRequired() then return true end
    return isMedsysRunning() and exports.medsys:isPlayerMedic(player) == true
end

-- nil = everyone; while pushed only the pusher; with the role required only the medics
local function visibleFor(s)
    if s.state == "pushing" then return s.pusher end
    if not isRoleRequired() then return nil end
    return isMedsysRunning() and exports.medsys:getMedicPlayers() or {}
end

-- ---------------------------------------------------------------------------------------------
-- Menu contents
-- ---------------------------------------------------------------------------------------------

local LOAD_ITEM = { label = "Load into ambulance", value = "load", desc = "At the rear doors of its ambulance" }

local function stretcherItems(s)
    if s.state == "stowed" then
        return { { label = s.seated and "Take out stretcher (with patient)" or "Take out stretcher",
            value = "take", desc = "Stand at the rear doors" } }
    elseif s.state == "pushing" then
        return {
            { label = "Release stretcher", value = "release", desc = "Put it down in front of you" },
            LOAD_ITEM,
        }
    end
    local items = { { label = "Push stretcher", value = "push", desc = "Walk with the stretcher in front of you" } }
    if s.patient then
        items[#items + 1] = { label = "Take patient off", value = "unload" }
    else
        items[#items + 1] = { label = "Place patient on stretcher", value = "place",
            desc = "The injured / nearest person next to the stretcher" }
    end
    items[#items + 1] = LOAD_ITEM
    return items
end

local function stretcherDef(s)
    return {
        title = s.state == "stowed" and "Ambulance stretcher" or (s.patient and "Stretcher (patient)" or "Stretcher"),
        range = s.state == "stowed" and STRETCHER.STOWED_MENU_RANGE or STRETCHER.MENU_RANGE,
        priority = 20,
        lineOfSight = false,          -- inside the vehicle / collisions off while pushed
        enabled = s.state ~= "moving",
        selfDataKey = STRETCHER.SELF_DATA_KEY,
        items = stretcherItems(s),
    }
end

-- ---------------------------------------------------------------------------------------------
-- Registration (hooks called by server/stretcher.lua)
-- ---------------------------------------------------------------------------------------------

local function register(s)
    if not isIORunning() then return end
    s.menuId = exports.ui_interactobject:addInteractMenu(s.object, stretcherDef(s), visibleFor(s))
    if s.menuId then menuOwner[s.menuId] = s end
end

function onStretcherCreated(s)
    register(s)
end

function onStretcherChanged(s)
    if not s.menuId or not isIORunning() then return end
    local io = exports.ui_interactobject
    io:updateInteractMenu(s.menuId, stretcherDef(s))
    io:setInteractMenuVisibleTo(s.menuId, visibleFor(s))
end

function onStretcherDestroyed(s)
    if s.menuId then
        menuOwner[s.menuId] = nil
        if isIORunning() then exports.ui_interactobject:removeInteractMenu(s.menuId) end
    end
    s.menuId = nil
end

-- ui_interactobject (re)started after us: its registry is empty, register everything again.
addEventHandler("onResourceStart", root, function(started)
    if getResourceName(started) ~= IO_RESOURCE then return end
    menuOwner = {}
    for _, s in pairs(Stretchers) do register(s) end
end)

-- A medic got / lost the role: update who sees the menus; a pusher who lost it lets go.
addEventHandler("onPlayerMedicChange", root, function(enabled)
    if not isRoleRequired() then return end
    if not enabled then
        local s = Stretchers[getPusherStretcher(source)]
        if s then releaseStretcher(s) end
    end
    if not isIORunning() then return end
    for _, s in pairs(Stretchers) do
        if s.menuId then exports.ui_interactobject:setInteractMenuVisibleTo(s.menuId, visibleFor(s)) end
    end
end)

-- medsys (re)started: its setting may have changed, ask again and refresh the menus
addEventHandler("onResourceStart", root, function(started)
    if getResourceName(started) ~= MEDSYS_RESOURCE then return end
    roleRequired = nil
    for _, s in pairs(Stretchers) do onStretcherChanged(s) end
end)

addEventHandler("onResourceStop", root, function(stopped)
    if getResourceName(stopped) ~= IO_RESOURCE then return end
    menuOwner = {}
    for _, s in pairs(Stretchers) do s.menuId = nil end
end)

-- ---------------------------------------------------------------------------------------------
-- Selections
-- ---------------------------------------------------------------------------------------------

local actions = {}

function actions.take(s, player)
    if s.state ~= "stowed" then return end
    if getPusherStretcher(player) then return notify(player, "You are already pushing a stretcher.") end
    if not isAtVehicleRear(player, s.vehicle) then return notify(player, "Stand at the rear doors of the ambulance.") end
    takeOutStretcher(s, player)
end

function actions.push(s, player)
    if s.state ~= "ground" then return end
    if getPusherStretcher(player) then return notify(player, "You are already pushing a stretcher.") end
    startPushing(s, player)
end

function actions.release(s, player)
    if s.state ~= "pushing" or s.pusher ~= player then return end
    releaseStretcher(s)
end

-- Opens the patient selector on the medic's client (client/select.lua); the pick comes back
-- through stretcher:pickPatient.
function actions.place(s, player)
    if s.state ~= "ground" or s.patient then return end
    if not hasPatientCandidate(s, player) then return notify(player, "There is nobody next to the stretcher.") end
    triggerClientEvent(player, "stretcher:selectPatient", resourceRoot, s.object)
end

addEvent("stretcher:pickPatient", true)
addEventHandler("stretcher:pickPatient", resourceRoot, function(obj, ped)
    local player = client
    local s = Stretchers[obj]
    if not s or s.state ~= "ground" or s.patient then return end
    if isPedDead(player) or getPatientStretcher(player) or getPusherStretcher(player) then return end
    if not hasStretcherAccess(player) then return end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(obj)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > STRETCHER.SELECT_MAX_DISTANCE + 2 then return end
    if not isPatientCandidate(s, ped, player) then
        return notify(player, "That person cannot be placed on the stretcher.")
    end
    putPatient(s, ped)
end)

function actions.unload(s, player)
    if s.state ~= "ground" or not s.patient then return end
    removePatient(s, true)
end

function actions.load(s, player)
    if s.state ~= "ground" and s.state ~= "pushing" then return end
    if s.state == "pushing" and s.pusher ~= player then return end
    local ok, reason = loadStretcher(s, player)
    if not ok and reason then notify(player, reason) end
end

addEventHandler("onInteractMenuSelect", root, function(menuId, value, target)
    local s = menuOwner[menuId]
    local action = s and actions[value]
    if not action or not Stretchers[s.object] then return end
    -- the patient cannot move their own stretcher
    if getPatientStretcher(source) then return end
    if not hasStretcherAccess(source) then return notify(source, "Only medics can handle the stretcher.") end
    action(s, source)
end)
