-- Groups and relations (server): who attacks whom.
--
-- Every AI ped has a group (traffic walkers / drivers "civilian", scripted peds "scripted" unless set). Players are
-- in "player" unless setPlayerAIGroup / element data "ai_peds.group" says otherwise. Relations between groups are
-- "hostile" | "neutral" | "friendly" (default neutral, a group with itself friendly). On top of that each ped keeps
-- personal grudges (attacker -> until), so a neutral ped fights back the one who hurt it.

Groups = { rel = {}, players = {} }

local G = Groups

function Groups.set(a, b, rel, mutual)
    G.rel[a] = G.rel[a] or {}
    G.rel[a][b] = rel
    if mutual ~= false then
        G.rel[b] = G.rel[b] or {}
        G.rel[b][a] = rel
    end
end

function Groups.get(a, b)
    local r = G.rel[a] and G.rel[a][b]
    if r then return r end
    return a == b and "friendly" or "neutral"
end

function Groups.of(el)
    local p = Peds.list[el]
    if p then return p.group end
    if getElementType(el) == "player" then
        return G.players[el] or getElementData(el, "ai_peds.group") or "player"
    end
    return "none"
end

function Groups.grudge(p, el, ms)
    if not isElement(el) or el == p.el then return end
    p.grudges[el] = getTickCount() + (ms or AIPEDS.GRUDGE_TIME)
end

function Groups.isHostile(p, el)
    if el == p.el or not Peds.alive(el) then return false end
    if getElementDimension(el) ~= getElementDimension(p.el) or getElementInterior(el) ~= getElementInterior(p.el) then
        return false
    end
    local g = p.grudges[el]
    if g then
        if g > getTickCount() then return true end
        p.grudges[el] = nil
    end
    return G.get(p.group, G.of(el)) == "hostile"
end

-- nearest hostile player / AI ped within radius (or nil)
function Groups.findHostile(p, radius)
    local best, bd = nil, radius * radius
    local dim, int = getElementDimension(p.el), getElementInterior(p.el)
    for _, pl in ipairs(getElementsWithinRange(p.x, p.y, p.z, radius, "player", int, dim)) do
        local x, y = getElementPosition(pl)
        local d = (x - p.x) ^ 2 + (y - p.y) ^ 2
        if d < bd and Groups.isHostile(p, pl) then best, bd = pl, d end
    end
    for _, o in pairs(Peds.list) do
        if o ~= p and not o.dead then
            local d = (o.x - p.x) ^ 2 + (o.y - p.y) ^ 2
            if d < bd and Groups.isHostile(p, o.el) then best, bd = o.el, d end
        end
    end
    -- personal grudges also against peds of other resources
    for el, untilT in pairs(p.grudges) do
        if isElement(el) and not Peds.list[el] and getElementType(el) == "ped" and untilT > getTickCount() then
            local x, y = getElementPosition(el)
            local d = (x - p.x) ^ 2 + (y - p.y) ^ 2
            if d < bd and Peds.alive(el) then best, bd = el, d end
        end
    end
    return best
end

addEventHandler("onPlayerQuit", root, function() G.players[source] = nil end)
