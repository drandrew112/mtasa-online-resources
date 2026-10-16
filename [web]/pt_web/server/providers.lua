-- pt_web :: server/providers.lua
-- One interface over every operator. A provider is a table:
--
--   online()            -> bool
--   stops()             -> { { id, name, city, x, y } }                     (local ids)
--   trips(t0, t1)       -> { trip }   trips departing in [t0, t1] (timestamps), see below
--   board(stopId, rows) -> { departures = {...}, arrivals = {...} } | false  (local stop id)
--   lines()             -> { { id, code, name, from, to, stops = {names}, headway } }
--
-- trip = { id, line, number, name, headsign, status ("scheduled" | "active"), delay (s),
--          stops = { { stop (local id), arr (ts) | nil, dep (ts) | nil, state } } }
--   state of a stop: "pending" | "stopped" (train there now) | "done" | "skipped"
--
-- Built-in providers live in server/provider_<adapter>.lua and fill ProviderAdapters. An entry
-- without `adapter` in PT.PROVIDERS is an external resource exporting ptGetStops / ptGetTrips /
-- ptGetBoard / ptGetLines with the same shapes (README.md) - the bus system will use that.
-- Here every stop id gets the provider prefix ("rail:unity"), so ids never clash.

ProviderAdapters = ProviderAdapters or {}

Providers = { list = {}, byId = {} }

local function external(def)
    local res = def.resource
    return {
        online = function() return Util.running(res) end,
        stops  = function() return Util.call(res, "ptGetStops") or {} end,
        trips  = function(t0, t1) return Util.call(res, "ptGetTrips", t0, t1) or {} end,
        board  = function(stop, rows) return Util.call(res, "ptGetBoard", stop, rows) or false end,
        lines  = function() return Util.call(res, "ptGetLines") or {} end,
    }
end

local function build()
    Providers.list, Providers.byId = {}, {}
    for _, def in ipairs(PT.PROVIDERS) do
        local impl
        if def.adapter then
            local make = ProviderAdapters[def.adapter]
            impl = make and make(def)
            if not impl then outputDebugString("pt_web: unknown provider adapter " .. tostring(def.adapter), 1) end
        elseif def.resource then
            impl = external(def)
        end
        if impl then
            local p = { id = def.id, mode = def.mode, name = def.name, short = def.short, color = def.color, impl = impl }
            Providers.list[#Providers.list + 1] = p
            Providers.byId[def.id] = p
        end
    end
end
addEventHandler("onResourceStart", resourceRoot, build)

-- "rail:unity" -> provider, "unity"
function Providers.split(globalId)
    if type(globalId) ~= "string" then return nil end
    local pid, sid = globalId:match("^([^:]+):(.+)$")
    local p = pid and Providers.byId[pid]
    if p then return p, sid end
end

local function safe(p, fn, ...)
    if not p.impl.online() then return nil end
    local ok, a = pcall(p.impl[fn], ...)
    if ok then return a end
    outputDebugString(("pt_web: provider %s.%s failed: %s"):format(p.id, fn, tostring(a)), 2)
end

function Providers.info()
    local out = {}
    for _, p in ipairs(Providers.list) do
        out[#out + 1] = { id = p.id, mode = p.mode, name = p.name, short = p.short, color = p.color, online = p.impl.online() }
    end
    return out
end

-- every stop of every online provider, global ids
function Providers.stops()
    local out = {}
    for _, p in ipairs(Providers.list) do
        for _, s in ipairs(Util.text(safe(p, "stops") or {})) do
            out[#out + 1] = { id = p.id .. ":" .. s.id, local_id = s.id, provider = p.id, mode = p.mode,
                name = Util.clean(s.name), city = s.city and Util.clean(s.city) or "", x = tonumber(s.x) or 0, y = tonumber(s.y) or 0 }
        end
    end
    return out
end

-- trips of every online provider, stop ids made global, provider / mode filled in (cached)
local tripCache, tripCacheAt, tripCacheKey = nil, -math.huge, nil
function Providers.trips(t0, t1)
    local key = t0 .. ":" .. t1
    local now = getTickCount()
    if tripCache and now - tripCacheAt < PT.PLANNER.CACHE * 1000 and tripCacheKey == key then return tripCache end
    local out = {}
    for _, p in ipairs(Providers.list) do
        for _, t in ipairs(Util.text(safe(p, "trips", t0, t1) or {})) do
            if t.status ~= "done" and t.status ~= "cancelled" then
                t.provider, t.mode = p.id, p.mode
                t.gid = p.id .. ":" .. tostring(t.id)
                for _, s in ipairs(t.stops or {}) do s.stop = p.id .. ":" .. tostring(s.stop) end
                out[#out + 1] = t
            end
        end
    end
    tripCache, tripCacheAt, tripCacheKey = out, now, key
    return out
end

function Providers.board(globalId, rows)
    local p, sid = Providers.split(globalId)
    if not p then return false end
    return Util.text(safe(p, "board", sid, rows) or false)
end

function Providers.lines()
    local out = {}
    for _, p in ipairs(Providers.list) do
        out[#out + 1] = { provider = p.id, mode = p.mode, name = p.name, online = p.impl.online(),
            lines = Util.text(safe(p, "lines") or {}) }
    end
    return out
end
