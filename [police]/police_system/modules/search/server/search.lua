-- police_system / modules/search/server/search.lua
-- Ped and vehicle search (stop menu "Search person" / "Search vehicle", also on a cuffed suspect). The items come
-- from shared/search_items.json: drawn by weight (count [min, max]), the drug / warrant items weigh boost_factor
-- times more for an NPC who uses drugs / has an active warrant. Classes: legal (green), questionable (orange),
-- illegal (red). An element is searched once: a second search shows the same items. Players: nothing is found
-- for now (no link to v_inventory yet; pol.search element data = { ids } is read when a script sets it). The result
-- goes to the unit's query window (kind "search") and into the report (log line "search").

local S = POL.module("search", { person = { items = {} }, vehicle = { items = {} }, boost = 5, byId = {}, done = {} })

local function load()
    local f = fileExists("shared/search_items.json") and fileOpen("shared/search_items.json", true)
    if not f then outputDebugString("[police_system] shared/search_items.json missing", 1) return end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    if type(data) ~= "table" then outputDebugString("[police_system] shared/search_items.json: bad JSON", 1) return end
    S.boost = tonumber(data.boost_factor) or 5
    S.byId = {}
    for _, kind in ipairs({ "person", "vehicle" }) do
        local d = type(data[kind]) == "table" and data[kind] or {}
        local c = type(d.count) == "table" and d.count or { 0, 2 }
        S[kind] = { min = tonumber(c[1]) or 0, max = tonumber(c[2]) or 2, items = {} }
        for _, it in ipairs(d.items or {}) do
            if it.id and (tonumber(it.weight) or 0) > 0 then
                local cls = (it.class == "illegal" or it.class == "questionable") and it.class or "legal"
                local e = { id = it.id, weight = tonumber(it.weight), class = cls, boost = it.boost }
                table.insert(S[kind].items, e)
                S.byId[e.id] = e
            end
        end
    end
end

-- ids drawn by weight, no item twice; ctx = { drug = bool, warrant = bool }
local function roll(kind, ctx)
    local def = S[kind]
    local pool = {}
    for _, e in ipairs(def.items) do
        local w = e.weight
        if e.boost and ctx[e.boost] then w = w * S.boost end
        pool[#pool + 1] = { id = e.id, w = w }
    end
    local out = {}
    for _ = 1, math.random(def.min, math.max(def.min, def.max)) do
        local total = 0
        for _, p in ipairs(pool) do total = total + p.w end
        if total <= 0 then break end
        local r = math.random() * total
        for i, p in ipairs(pool) do
            r = r - p.w
            if r <= 0 then out[#out + 1] = p.id; table.remove(pool, i); break end
        end
    end
    return out
end

local function classOf(id) local e = S.byId[id]; return e and e.class or "legal" end

-- the search of `el` (a ped / player: "person", a vehicle: "vehicle"); s = the stop (flags, citizenId, unit, inc)
function S.search(officer, el, kind, s)
    local unit = POL.units.of(officer)
    if not unit or not isElement(el) then return end
    local name = kind == "vehicle" and (getVehiclePlateText(el) or "?") or POL.stop.nameOf(el)
    local function show(ids)
        local list, illegal = {}, 0
        for _, id in ipairs(ids) do
            local cls = classOf(id)
            if cls == "illegal" then illegal = illegal + 1 end
            list[#list + 1] = { id = id, class = cls }
        end
        local r = { kind = "search", what = kind, name = name, items = list, at = POL.now() }
        POL.send(POL.units.members(unit), "query:result", r)
        local inc = (s and s.inc) or POL.events.incidentOf(unit, el)
        POL.events.log(unit, officer, "search", { name = kind ~= "vehicle" and name or nil, plate = kind == "vehicle" and name or nil,
            vehicle = kind == "vehicle", items = ids, illegal = illegal }, inc)
    end
    if S.done[el] then return show(S.done[el]) end
    -- players: what a script put on them (nothing for now)
    local person = kind == "vehicle" and getVehicleController(el) or el
    if (kind == "person" and getElementType(el) == "player") or (kind == "vehicle" and getElementData(el, "ownveh:id")) then
        local ids = getElementData(el, "pol.search")
        S.done[el] = type(ids) == "table" and ids or {}
        return show(S.done[el])
    end
    local flags = s and s.flags or {}
    local cid = s and s.citizenId or (isElement(person) and getElementData(person, "pol.cid"))
    local function go(warrant)
        if S.done[el] then return show(S.done[el]) end
        S.done[el] = roll(kind, { drug = flags.drug == true, warrant = warrant })
        show(S.done[el])
    end
    if cid then
        POL.warrants.activeFor(cid, function(w) go(type(w) == "table" and #w > 0) end)
    else
        go(false)
    end
end

addEventHandler("onElementDestroy", root, function() if S.done[source] then S.done[source] = nil end end)

function S.start() load() end
