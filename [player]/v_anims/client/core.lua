if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_anims client core: favourites cache, play / stop requests, labels, end detection of the
-- local animation and re-applying looped animations of players that stream in.

addEvent("v_anims:notify", true)
addEvent("v_anims:favs", true)
addEvent("onClientAnimFavouritesChanged") -- (list) source = localPlayer

Anims = { favs = {}, favSet = {} }

function Anims.label(a)
    local g = ANIMS.groups[a.cmd]
    local name = L("v_anims.group." .. a.cmd)
    if g and #g.anims > 1 then name = name .. " " .. a.n end
    return name
end

function Anims.command(a)
    return a.n == 1 and ("/" .. a.cmd) or ("/" .. a.cmd .. " " .. a.n)
end

function Anims.catLabel(cat)
    return L("v_anims.cat." .. cat)
end

function Anims.current()
    local id = getElementData(localPlayer, ANIMS.DATA_CURRENT)
    return id and ANIMS.byId[id] or nil
end

function Anims.play(id)
    if ANIMS.byId[id] then triggerServerEvent("v_anims:play", resourceRoot, id) end
end

function Anims.stop()
    triggerServerEvent("v_anims:stop", resourceRoot)
end

function Anims.isFav(id) return Anims.favSet[id] == true end

function Anims.setFavs(list)
    list = ANIMS.cleanFavs(list)
    Anims.favs = list -- optimistic, the server echoes the stored list
    Anims.favSet = {}
    for _, id in ipairs(list) do Anims.favSet[id] = true end
    triggerServerEvent("v_anims:setFavs", resourceRoot, list)
    triggerEvent("onClientAnimFavouritesChanged", localPlayer, list)
end

-- true = added, false = removed, nil = list full
function Anims.toggleFav(id)
    local list = {}
    for _, f in ipairs(Anims.favs) do list[#list + 1] = f end
    if Anims.favSet[id] then
        for i, f in ipairs(list) do if f == id then table.remove(list, i) break end end
        Anims.setFavs(list)
        return false
    end
    if #list >= ANIMS.MAX_FAVS then
        Anims.notify(L("v_anims.msg.favs_full", { max = ANIMS.MAX_FAVS }))
        return nil
    end
    list[#list + 1] = id
    Anims.setFavs(list)
    return true
end

function Anims.notify(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("v_anims.title"), text, false)
    end
end

addEventHandler("v_anims:notify", resourceRoot, function(text)
    Anims.notify(L.resolve(text))
end)

addEventHandler("v_anims:favs", resourceRoot, function(list)
    Anims.favs = ANIMS.cleanFavs(list)
    Anims.favSet = {}
    for _, id in ipairs(Anims.favs) do Anims.favSet[id] = true end
    triggerEvent("onClientAnimFavouritesChanged", localPlayer, Anims.favs)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_anims:requestFavs", resourceRoot)
end)

-- the accName arrives later than the resource start on a fresh join
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "accName" then triggerServerEvent("v_anims:requestFavs", resourceRoot) end
end)

--------------------------------------------------------------------------------
-- end detection: the local ped stopped playing the animation (GTA interrupted it, another
-- script replaced it) -> the server clears the state. Runs only while an animation is set.
--------------------------------------------------------------------------------

local watch, misses = nil, 0

local function check()
    local a = Anims.current()
    if not a then
        if watch then killTimer(watch) watch = nil end
        return
    end
    if ANIMS.matches(a, getPedAnimation(localPlayer)) then misses = 0 return end
    misses = misses + 1
    if misses >= 3 then
        misses = 0
        triggerServerEvent("v_anims:ended", resourceRoot, a.id)
    end
end

local function startWatch()
    misses = 0
    if not watch then watch = setTimer(check, 400, 0) end
end

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= ANIMS.DATA_CURRENT then return end
    if source == localPlayer then
        if new then startWatch() end
        return
    end
end)

if Anims.current() then startWatch() end

--------------------------------------------------------------------------------
-- a player streaming in keeps his looped / held animation (in case the late sync misses it)
--------------------------------------------------------------------------------

local function reapply(player)
    if player == localPlayer or not isElement(player) or getElementType(player) ~= "player" then return end
    local id = getElementData(player, ANIMS.DATA_CURRENT)
    local a = id and ANIMS.byId[id]
    if not a or not (a.loop or a.hold) or isPedDead(player) or getPedOccupiedVehicle(player) then return end
    if ANIMS.matches(a, getPedAnimation(player)) then return end
    setPedAnimation(player, a.block, a.name, -1, a.loop, false, true, a.hold, 0)
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "player" then return end
    local p = source
    setTimer(function() reapply(p) end, 500, 1)
end)

-- exports
function playAnim(id) Anims.play(id) return ANIMS.byId[id] ~= nil end
function stopAnim() Anims.stop() return true end
function getFavouriteAnims() return Anims.favs end
function getCurrentAnim() local a = Anims.current() return a and a.id or false end
function getAnimLabel(id) local a = ANIMS.byId[id] return a and Anims.label(a) or false end
