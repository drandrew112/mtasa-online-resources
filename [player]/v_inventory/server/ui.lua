if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Windows and HUD data. A session is the open window of a player: their own slots on the left and
-- optionally an "other side" on the right (a port, a trunk or a container: a bag on the ground, or a
-- container a script opened with openInventory). The server sends whole views; the client only asks
-- for moves, and every move is checked here (reach) and in server/core.lua (rules).
-- Any change touches its location (touchLoc): the players who see it get a fresh HUD / view on the
-- next frame.

addEvent("inv:openOwn", true)
addEvent("inv:close", true)
addEvent("inv:move", true)
addEvent("inv:requestHud", true)

Sessions = {}           -- player -> { other = loc | nil, readOnly, external, x, y, z, dim, int }
local dirty = {}        -- player -> true
local flushPending = false

-- ---------------------------------------------------------------------------------------------
-- Item views
-- ---------------------------------------------------------------------------------------------

-- What the client draws for an item. ctx: { player, port } marks port rules / suggestions.
local function itemView(item, ctx, withContents)
    local def = defOf(item)
    local v = {
        u = item.uid, d = item.def, a = item.amount, w = itemWeight(item),
        disp = item.meta.display, bar = item.meta.bar,
        hold = def.holdable or nil, back = def.back or nil,
    }
    if def.container then
        v.cap = def.container.capacity
        v.used = listWeight(item.contents)
        v.n = #item.contents
        if withContents then
            v.items = {}
            for i, it in ipairs(item.contents) do v.items[i] = itemView(it, ctx, false) end
        end
    end
    if ctx and ctx.port then
        local onPort = item.loc.type == "port"
        if onPort then
            if not portAllows(ctx.port, ctx.player, item, "out") then v.st = "lockOut"
            elseif portSuggestion(ctx.port, ctx.player, item) == "out" then v.st = "out" end
        elseif item.loc.type == "container" or item.loc.type == "slot" then
            if not def.storable or not portAllows(ctx.port, ctx.player, item, "in") then v.st = "lockIn"
            elseif portSuggestion(ctx.port, ctx.player, item) == "in" then v.st = "in" end
        end
    elseif ctx and ctx.storage and not def.storable and item.loc.type == "slot" then
        v.st = "lockIn"
    end
    return v
end

local function slotsView(player, ctx)
    local out = {}
    local slots = getSlots(player)
    for _, slot in ipairs(INV.SLOTS) do
        local item = slots and slots[slot]
        if item then out[slot] = itemView(item, ctx, true) end
    end
    return out
end

local function otherView(player, session, ctx)
    local other = session.other
    if not other then return nil end
    local v = { kind = other.type }
    local list
    if other.type == "port" then
        local port = Ports[other.port]
        if not port then return nil end
        v.title, v.sub, v.cap, v.icon, v.color = port.title, port.name, port.capacity, port.icon, port.color
        list = port.items
    elseif other.type == "trunk" then
        local trunk = Trunks[other.vehicle]
        if not trunk then return nil end
        local p = (getVehiclePlateText(other.vehicle) or ""):gsub("^%s+", ""):gsub("%s+$", "")
        v.title = trunk.title or L.msg("v_inventory.ui.trunk")
        v.sub = p ~= "" and p or nil
        v.cap = trunk.capacity
        list = trunk.items
    elseif other.type == "container" then
        local item = other.item
        if not Items[item.uid] then return nil end
        v.uid, v.def = item.uid, item.def
        v.disp = item.meta.display
        v.cap = defOf(item).container.capacity
        list = item.contents
    end
    v.used = listWeight(list)
    v.items = {}
    for i, it in ipairs(list) do v.items[i] = itemView(it, ctx, false) end
    return v
end

local function buildView(player, session)
    local ctx = { player = player }
    local other = session.other
    if other and other.type == "port" then ctx.port = other.port end
    if other and (other.type == "trunk" or other.type == "container") then ctx.storage = true end
    return {
        slots = slotsView(player, ctx),
        other = otherView(player, session, ctx),
        readOnly = session.readOnly or nil,
        banner = (other and other.type == "port") and portBanner(other.port, player) or nil,
        origin = { session.x, session.y, session.z },
        range = INV.SESSION_RANGE,
    }
end

-- The HUD: the slot items with their display lines and container summary
local function buildHud(player)
    return slotsView(player, nil)
end

-- ---------------------------------------------------------------------------------------------
-- Dirty tracking
-- ---------------------------------------------------------------------------------------------

local function flush()
    flushPending = false
    local list = dirty
    dirty = {}
    for player in pairs(list) do
        if isElement(player) then
            triggerClientEvent(player, "inv:hud", resourceRoot, buildHud(player))
            local session = Sessions[player]
            if session then triggerClientEvent(player, "inv:view", resourceRoot, buildView(player, session)) end
        end
    end
end

local function markPlayer(player)
    if not isElement(player) then return end
    dirty[player] = true
    if not flushPending then
        flushPending = true
        setTimer(flush, 50, 1)
    end
end

local function sessionShows(session, loc)
    local o = session.other
    if not o then return false end
    if loc.type == "port" then return o.type == "port" and o.port == loc.port end
    if loc.type == "trunk" then return o.type == "trunk" and o.vehicle == loc.vehicle end
    if loc.type == "containerItem" then return o.type == "container" and o.item == loc.item end
    return false
end

-- Hook of server/core.lua: something changed at loc
function touchLoc(loc)
    if not loc then return end
    local guard = 0
    while loc and guard < 5 do
        guard = guard + 1
        if loc.type == "slot" then
            markPlayer(loc.player)
            return
        elseif loc.type == "container" then
            local c = loc.item
            local probe = { type = "containerItem", item = c }
            for player, session in pairs(Sessions) do
                if sessionShows(session, probe) then markPlayer(player) end
            end
            loc = c.loc
        elseif loc.type == "port" or loc.type == "trunk" then
            for player, session in pairs(Sessions) do
                if sessionShows(session, loc) then markPlayer(player) end
            end
            return
        else
            if loc.type == "ground" then
                -- a stack on the ground changed: its menu title
                for _, item in pairs(Items) do
                    if item.loc == loc then refreshGroundMenu(item) break end
                end
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------------------------

-- other: nil (own inventory) | { type = "port", port } | { type = "trunk", vehicle } |
-- { type = "container", item }. opts: readOnly, external (opened by a script, any location)
function openSession(player, other, opts)
    opts = opts or {}
    if not isElement(player) then return false end
    local x, y, z = getElementPosition(player)
    Sessions[player] = {
        other = other, readOnly = opts.readOnly == true, external = opts.external == true,
        x = x, y = y, z = z, dim = getElementDimension(player), int = getElementInterior(player),
    }
    triggerClientEvent(player, "inv:open", resourceRoot, buildView(player, Sessions[player]))
    return true
end

function closeSession(player, tellClient)
    if not Sessions[player] then return end
    Sessions[player] = nil
    if tellClient and isElement(player) then triggerClientEvent(player, "inv:closed", resourceRoot) end
end

-- Closes the sessions showing loc (of one player, or everyone)
function closeSessionsOf(loc, onlyPlayer)
    for player, session in pairs(Sessions) do
        if (not onlyPlayer or player == onlyPlayer) and sessionShows(session, loc) then closeSession(player, true) end
    end
end

-- Is the session still valid?
local function sessionValid(player, session)
    if not isElement(player) or isPedDead(player) or isPedInVehicle(player) then return false end
    if getElementDimension(player) ~= session.dim or getElementInterior(player) ~= session.int then return false end
    local x, y, z = getElementPosition(player)
    if getDistanceBetweenPoints3D(x, y, z, session.x, session.y, session.z) > INV.SESSION_RANGE then return false end
    local o = session.other
    if not o then return true end
    if o.type == "port" then
        local port = Ports[o.port]
        return port ~= nil and portVisibleFor(port, player)
    elseif o.type == "trunk" then
        local trunk = Trunks[o.vehicle]
        return trunk ~= nil and hasTrunkAccess(trunk, player)
    elseif o.type == "container" then
        if not Items[o.item.uid] then return false end
        if session.external then return true end
        -- a container on the ground: still there and near
        if o.item.loc.type ~= "ground" then return false end
        local ix, iy, iz = itemWorldPosition(o.item)
        return ix ~= false and getDistanceBetweenPoints3D(x, y, z, ix, iy, iz) <= INV.OPEN_RANGE + 2
    end
    return false
end

setTimer(function()
    for player, session in pairs(Sessions) do
        if not sessionValid(player, session) then closeSession(player, true) end
    end
end, 1000, 0)

addEventHandler("inv:openOwn", resourceRoot, function()
    local player = client
    if isPedDead(player) or isPedInVehicle(player) then return end
    openSession(player, nil)
end)

addEventHandler("inv:close", resourceRoot, function()
    closeSession(client, false)
end)

addEventHandler("inv:requestHud", resourceRoot, function()
    markPlayer(client)
end)

addEventHandler("onPlayerQuit", root, function()
    Sessions[source] = nil
    dirty[source] = nil
end)

-- ---------------------------------------------------------------------------------------------
-- Moves asked by the client
-- ---------------------------------------------------------------------------------------------

-- Can the player reach the item through their session? (own slots and the containers in them,
-- or the other side's list)
local function reachable(player, session, item)
    local top = topItem(item)
    if top.loc.type == "slot" and top.loc.player == player then return true end
    local o = session.other
    if not o then return false end
    if o.type == "port" then return item.loc.type == "port" and item.loc.port == o.port end
    if o.type == "trunk" then return item.loc.type == "trunk" and item.loc.vehicle == o.vehicle end
    if o.type == "container" then return item.loc.type == "container" and item.loc.item == o.item end
    return false
end

-- target from the client: { kind = "slot", slot } | { kind = "container", uid } | { kind = "other" }
-- | { kind = "ground" }
local function resolveTarget(player, session, target)
    if type(target) ~= "table" then return nil end
    if target.kind == "slot" then
        if target.slot ~= "left" and target.slot ~= "right" and target.slot ~= "back" then return nil end
        return { type = "slot", player = player, slot = target.slot }
    elseif target.kind == "container" then
        local c = Items[target.uid]
        if not c or not isContainer(c) then return nil end
        if c.loc.type == "slot" and c.loc.player == player then return { type = "container", item = c } end
        if session.other and session.other.type == "container" and session.other.item == c then
            return { type = "container", item = c }
        end
        return nil
    elseif target.kind == "other" then
        local o = session.other
        if not o then return nil end
        if o.type == "container" then return { type = "container", item = o.item } end
        return o
    elseif target.kind == "ground" then
        return { type = "ground" }
    end
    return nil
end

addEventHandler("inv:move", resourceRoot, function(uid, target, amount)
    local player = client
    local session = Sessions[player]
    if not session or session.readOnly then return end
    if not sessionValid(player, session) then return closeSession(player, true) end
    local item = Items[uid]
    if not item or not reachable(player, session, item) then return markPlayer(player) end
    local loc = resolveTarget(player, session, target)
    if not loc then return markPlayer(player) end

    local ok, reason
    if loc.type == "ground" then
        -- put down at the feet: only what can be picked up again
        local def = defOf(item)
        if not def.holdable and not def.back then
            ok, reason = false, L.msg("v_inventory.msg.cannot_put_down")
        elseif not canPlayerHandle(player, item) then
            ok, reason = false, L.msg("v_inventory.msg.no_access")
        else
            local x, y, z = getElementPosition(player)
            local _, _, rz = getElementRotation(player)
            local rad = math.rad(rz)
            ok, reason = dropItemAt(item, x - 0.6 * math.sin(rad), y + 0.6 * math.cos(rad), z - 1.0, rz,
                getElementDimension(player), getElementInterior(player), player, { player = player })
            if ok then playAnim(player, INV.PUT_ANIM) end
        end
    else
        ok, reason = moveItem(item, loc, { player = player, amount = tonumber(amount) })
        if ok and loc.type == "slot" then playAnim(player, INV.TAKE_ANIM) end
    end
    if not ok then
        notify(player, reason, true)
        markPlayer(player)
    end
end)
