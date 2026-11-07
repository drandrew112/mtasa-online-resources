if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- v_anims server: plays the database animations (server setPedAnimation = synced to everybody),
-- registers one command per group (/sit, /sit 2, ...), keeps the favourites in accData.
--
-- State per player: element data ANIMS.DATA_CURRENT = id (synced, cleared when it ends).
-- A looped / held animation runs until stopped (F9 tap, /stopanim, another animation, death,
-- a blocking state); a once / move animation clears itself after its length. The owner client
-- reports an animation GTA or another script ended early (v_anims:ended).

addEvent("onPlayerAccountLogin")              -- v_accounts (accountName, isNew), source = player
addEvent("v_anims:play", true)                -- client: (id)
addEvent("v_anims:stop", true)                -- client
addEvent("v_anims:ended", true)               -- client: (id) the ped no longer plays it
addEvent("v_anims:setFavs", true)             -- client: (list of ids)
addEvent("v_anims:requestFavs", true)         -- client
addEvent("onPlayerAnimStart")                 -- (id) source = player, after the animation started
addEvent("onPlayerAnimStop")                  -- (id) source = player

local MIN_GAP = 350 -- ms between two starts of one player

local state = {}    -- player -> { id, timer, tick }
local favs = {}     -- player -> { ids }
local blocks = {}   -- player -> { key = true } (setAnimsBlocked)
local lastStart = {}

local function notify(player, key, params)
    if isElement(player) then triggerClientEvent(player, "v_anims:notify", resourceRoot, L.msg(key, params)) end
end

local function killTimer_(t)
    if t and isTimer(t) then killTimer(t) end
end

--------------------------------------------------------------------------------
-- blocking
--------------------------------------------------------------------------------

-- nil when the player may animate, else the v_locals key of the reason
local function blockReason(player)
    if isPedDead(player) then return "v_anims.msg.dead" end
    if getPedOccupiedVehicle(player) then return "v_anims.msg.vehicle" end
    if isElementAttached(player) or isElementInWater(player) then return "v_anims.msg.cannot" end
    if isPedWearingJetpack and isPedWearingJetpack(player) then return "v_anims.msg.cannot" end
    if not isPedOnGround(player) then return "v_anims.msg.cannot" end
    for _, key in ipairs(ANIMS.BLOCK_DATA) do
        local v = getElementData(player, key)
        if v ~= nil and v ~= false then return "v_anims.msg.cannot" end
    end
    if blocks[player] and next(blocks[player]) then return "v_anims.msg.cannot" end
    return nil
end

--------------------------------------------------------------------------------
-- play / stop
--------------------------------------------------------------------------------

local function clear(player, reason)
    local s = state[player]
    if not s then return end
    killTimer_(s.timer)
    state[player] = nil
    if isElement(player) then
        setElementData(player, ANIMS.DATA_CURRENT, false)
        triggerEvent("onPlayerAnimStop", player, s.id, reason)
    end
end

local function applyMain(player, a)
    if a.loop then
        setPedAnimation(player, a.block, a.name, -1, true, false, true, false, ANIMS.BLEND)
    elseif a.hold then
        setPedAnimation(player, a.block, a.name, -1, false, false, true, true, ANIMS.BLEND)
    else
        setPedAnimation(player, a.block, a.name, -1, false, a.move, true, false, ANIMS.BLEND)
        -- a once / move animation ends by itself: free the state afterwards
        local s = state[player]
        s.timer = setTimer(function()
            if state[player] == s then clear(player, "ended") end
        end, a.ms + 300, 1)
    end
end

-- Starts animation `id` on the player. quiet = no notification on refusal (exports).
function playAnim(player, id, quiet)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local a = ANIMS.byId[id]
    if not a then return false end
    local reason = blockReason(player)
    if reason then
        if not quiet then notify(player, reason) end
        return false
    end
    local now = getTickCount()
    if lastStart[player] and now - lastStart[player] < MIN_GAP then return false end
    lastStart[player] = now

    local old = state[player]
    if old then
        killTimer_(old.timer)
        triggerEvent("onPlayerAnimStop", player, old.id, "replaced")
    end
    local s = { id = id, tick = now }
    state[player] = s
    setElementData(player, ANIMS.DATA_CURRENT, id)

    -- the intro only when the player stood normally (not switching from another sit, ...)
    if a.intro and not old then
        setPedAnimation(player, a.intro[1], a.intro[2], -1, false, false, true, true, ANIMS.BLEND)
        s.timer = setTimer(function()
            if state[player] ~= s then return end
            s.timer = nil
            applyMain(player, a)
        end, math.max(50, a.intro[3] - 60), 1)
    else
        applyMain(player, a)
    end
    triggerEvent("onPlayerAnimStart", player, id)
    return true
end

-- Stops the player's animation (plays the outro of a looped one). Returns false when none ran.
function stopAnim(player, instant)
    local s = state[player]
    if not s then
        return false
    end
    local a = ANIMS.byId[s.id]
    local inIntro = s.timer and a and a.intro and a.loop and getTickCount() - s.tick < a.intro[3]
    clear(player, "stopped")
    if not isElement(player) or isPedDead(player) then return true end
    if not instant and a and a.outro and not inIntro and not getPedOccupiedVehicle(player) then
        setPedAnimation(player, a.outro[1], a.outro[2], -1, false, false, true, false, ANIMS.BLEND)
    else
        setPedAnimation(player)
    end
    return true
end

function getPlayerAnim(player)
    local s = state[player]
    return s and s.id or false
end

-- Other systems can forbid animations: setAnimsBlocked(player, "minigame", true). A running
-- animation stops when the first block is set.
function setAnimsBlocked(player, key, blocked)
    if not isElement(player) or type(key) ~= "string" then return false end
    blocks[player] = blocks[player] or {}
    blocks[player][key] = blocked and true or nil
    if blocked and state[player] then stopAnim(player, true) end
    if not next(blocks[player]) then blocks[player] = nil end
    return true
end

-- { { id, cmd, n, cat, block, name, loop, hold, move }, ... } in database order
function getAnimList()
    local out = {}
    for i, a in ipairs(ANIMS.order) do
        out[i] = { id = a.id, cmd = a.cmd, n = a.n, cat = a.cat, block = a.block, name = a.name,
                   loop = a.loop, hold = a.hold, move = a.move }
    end
    return out
end

addEventHandler("v_anims:play", resourceRoot, function(id)
    if type(id) == "string" then playAnim(client, id) end
end)

addEventHandler("v_anims:stop", resourceRoot, function()
    stopAnim(client)
end)

addEventHandler("v_anims:ended", resourceRoot, function(id)
    local s = state[client]
    if s and s.id == id and getTickCount() - s.tick > 500 then clear(client, "ended") end
end)

-- a blocking element data appeared: the animation stops without its outro
addEventHandler("onElementDataChange", root, function(key, _, new)
    if getElementType(source) ~= "player" or not state[source] then return end
    if new == nil or new == false then return end
    for _, k in ipairs(ANIMS.BLOCK_DATA) do
        if k == key then
            clear(source, "blocked") -- the other system sets its own animation
            return
        end
    end
end)

addEventHandler("onPlayerWasted", root, function() clear(source, "dead") end)
addEventHandler("onPlayerVehicleEnter", root, function() clear(source, "vehicle") end)
addEventHandler("onPlayerQuit", root, function()
    clear(source, "quit")
    favs[source], blocks[source], lastStart[source] = nil, nil, nil
end)

--------------------------------------------------------------------------------
-- commands: one per group + /anim <id|cmd> [n] + /stopanim
--------------------------------------------------------------------------------

local function runGroup(player, cmd, arg)
    local g = ANIMS.groups[cmd]
    if not g then return end
    local n = tonumber(arg) or 1
    local a = g.anims[math.floor(n)]
    if not a then
        notify(player, "v_anims.msg.range", { cmd = cmd, max = #g.anims })
        return
    end
    playAnim(player, a.id)
end

for cmd in pairs(ANIMS.groups) do
    addCommandHandler(cmd, function(player, _, arg) runGroup(player, cmd, arg) end, false, false)
end

addCommandHandler("anim", function(player, _, what, n)
    if not what then
        notify(player, "v_anims.msg.usage")
        return
    end
    what = what:lower()
    if what == "stop" then stopAnim(player) return end
    local a = ANIMS.resolve(what, n)
    if a then
        playAnim(player, a.id)
    elseif ANIMS.groups[what] then
        runGroup(player, what, n)
    else
        notify(player, "v_anims.msg.unknown", { name = what })
    end
end, false, false)

addCommandHandler("stopanim", function(player) stopAnim(player) end, false, false)

--------------------------------------------------------------------------------
-- favourites (accData ANIMS.ACC_KEY = JSON array, wheel order)
--------------------------------------------------------------------------------

local function loggedIn(player)
    local acc = getElementData(player, "accName")
    return type(acc) == "string" and acc ~= ""
end

local function loadFavs(player)
    if not loggedIn(player) then return favs[player] or {} end
    local ok, raw = pcall(function() return exports.v_mysql:getAccData(player, ANIMS.ACC_KEY) end)
    local list = {}
    if ok and type(raw) == "string" and raw ~= "" then list = fromJSON(raw) or {} end
    favs[player] = ANIMS.cleanFavs(list)
    return favs[player]
end

local function sendFavs(player)
    triggerClientEvent(player, "v_anims:favs", resourceRoot, favs[player] or loadFavs(player))
end

-- exports
function getPlayerFavouriteAnims(player)
    return favs[player] or loadFavs(player)
end

function setPlayerFavouriteAnims(player, list)
    if not isElement(player) then return false end
    list = ANIMS.cleanFavs(list)
    favs[player] = list
    if loggedIn(player) then
        pcall(function() exports.v_mysql:setAccData(player, ANIMS.ACC_KEY, toJSON(list, true)) end)
    end
    sendFavs(player)
    return true
end

addEventHandler("v_anims:setFavs", resourceRoot, function(list)
    if type(list) == "table" and #list > ANIMS.MAX_FAVS then
        notify(client, "v_anims.msg.favs_full", { max = ANIMS.MAX_FAVS })
    end
    setPlayerFavouriteAnims(client, list)
end)

addEventHandler("v_anims:requestFavs", resourceRoot, function()
    sendFavs(client)
end)

addEventHandler("onPlayerAccountLogin", root, function()
    favs[source] = nil
    loadFavs(source)
    sendFavs(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(state) do
        if isElement(player) then
            setElementData(player, ANIMS.DATA_CURRENT, false)
            if not isPedDead(player) then setPedAnimation(player) end
        end
    end
end)
