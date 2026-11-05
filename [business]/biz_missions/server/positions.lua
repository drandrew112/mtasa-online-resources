-- biz_missions / server/positions.lua
-- Mission positions saved by /bizmissioneditor (MIS.POSITIONS_FILE). When the
-- file exists, its lists replace MIS.SUPPLY_SPOTS, MIS.VAN_SPAWNS and
-- MIS.BUYERS of shared/config.lua (whole lists, not merged).
--
-- File: { supply = [ spot ], vanSpawns = { building = [ { x, y, z, rot } ] }, buyers = [ { name, x, y, z } ] }
-- spot: { name, x, y, z, van = { x, y, z, rot } | nil, guards = [ { x, y, z, rot } ] | nil }

POS = {}

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if lo and (v < lo or v > hi) then return nil end
    return math.floor(v * 100 + 0.5) / 100
end

local function point(t, withRot)
    if type(t) ~= "table" then return nil end
    local x, y, z = num(t.x, -4000, 4000), num(t.y, -4000, 4000), num(t.z, -100, 1500)
    if not x or not y or not z then return nil end
    local out = { x = x, y = y, z = z }
    if withRot then out.rot = math.floor((tonumber(t.rot) or 0) % 360) end
    return out
end

local function name(v, fallback)
    v = type(v) == "string" and v:gsub("[%c]", ""):sub(1, 40) or ""
    return v ~= "" and v or fallback
end

--- validated copy (nil entries dropped); used for the file and the editor's save
function POS.sanitize(doc)
    if type(doc) ~= "table" then return nil end
    local out = { supply = {}, vanSpawns = {}, buyers = {} }
    for i, s in ipairs(type(doc.supply) == "table" and doc.supply or {}) do
        local p = point(s)
        if p then
            p.name = name(s.name, "Spot " .. i)
            p.van = point(s.van, true)
            if type(s.guards) == "table" then
                local g = {}
                for _, gp in ipairs(s.guards) do
                    gp = point(gp, true)
                    if gp and #g < 12 then g[#g + 1] = gp end
                end
                if #g > 0 then p.guards = g end
            end
            out.supply[#out.supply + 1] = p
        end
    end
    for building, list in pairs(type(doc.vanSpawns) == "table" and doc.vanSpawns or {}) do
        if type(building) == "string" and building:match("^[%w_]+$") and type(list) == "table" then
            local l = {}
            for _, v in ipairs(list) do
                v = point(v, true)
                if v and #l < 16 then l[#l + 1] = v end
            end
            if #l > 0 then out.vanSpawns[building] = l end
        end
    end
    for i, b in ipairs(type(doc.buyers) == "table" and doc.buyers or {}) do
        local p = point(b)
        if p then
            p.name = name(b.name, "Buyer " .. i)
            out.buyers[#out.buyers + 1] = p
        end
    end
    return out
end

--- the lists in use now
function POS.snapshot()
    return { supply = MIS.SUPPLY_SPOTS, vanSpawns = MIS.VAN_SPAWNS, buyers = MIS.BUYERS }
end

local function apply(doc)
    MIS.SUPPLY_SPOTS = doc.supply
    MIS.VAN_SPAWNS = doc.vanSpawns
    MIS.BUYERS = doc.buyers
end

--- validates, applies (next missions use it) and writes the file -> true | false, err
function POS.save(doc)
    doc = POS.sanitize(doc)
    if not doc then return false, "invalid" end
    if #doc.supply == 0 then return false, "no_supply" end
    if #doc.buyers == 0 then return false, "no_buyers" end
    local f = fileCreate(MIS.POSITIONS_FILE)
    if not f then return false, "file" end
    fileWrite(f, toJSON(doc, false, "spaces"))
    fileClose(f)
    apply(doc)
    return true
end

local function load()
    if not fileExists(MIS.POSITIONS_FILE) then return end
    local f = fileOpen(MIS.POSITIONS_FILE, true)
    if not f then return end
    local raw = fileRead(f, fileGetSize(f))
    fileClose(f)
    local doc = POS.sanitize(fromJSON(raw))
    if doc and #doc.supply > 0 and #doc.buyers > 0 then
        apply(doc)
    else
        outputDebugString("[biz_missions] " .. MIS.POSITIONS_FILE .. " is invalid, config.lua positions are used", 2)
    end
end
load()
