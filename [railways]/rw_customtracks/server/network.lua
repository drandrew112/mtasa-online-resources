-- Network data on the server: loads the files of the manifest, builds the network, sends the raw
-- data to every client, and offers the edit / query exports (MCP, editor). Edits are applied in
-- memory, rebuilt and broadcast at once; netSave() writes them back to their files.

local files = {}          -- ordered { { file, about, segments, nodes, groups, crossings } }
local dirty = {}          -- [file] = true
local ready = {}          -- [player] = true once the client asked for the data
local rebuildTimer

local function log(fmt, ...)
    outputDebugString("[rw_customtracks] " .. string.format(fmt, ...))
end

local function isAdmin(p)
    if getElementType(p) ~= "player" then return true end    -- console
    local res = getResourceFromName("rw_core")
    if res and getResourceState(res) == "running" then
        local ok, v = pcall(function() return exports.rw_core:isRailwayAdmin(p) end)
        if ok then return v end
    end
    return hasObjectPermissionTo(p, "command.kick", false)
end

-- ------------------------------------------------------------------ files

local function readFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    return s
end

local function writeFile(path, s)
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, s)
    fileClose(f)
    return true
end

local function fileEntry(name)
    for _, f in ipairs(files) do if f.file == name then return f end end
    local f = { file = name, segments = {}, nodes = {}, groups = {}, crossings = {} }
    files[#files + 1] = f
    return f
end

local function loadAll()
    files = {}
    -- { "files": [ ... ] } (MTA's fromJSON splits a top-level array into separate values)
    local manifest = fromJSON(readFile(NET.MANIFEST) or "") or {}
    for _, name in ipairs(manifest.files or {}) do
        local raw = readFile(NET.DATA_DIR .. name)
        local data = raw and fromJSON(raw)
        if type(data) ~= "table" then
            log("cannot read %s", name)
        else
            files[#files + 1] = { file = name, about = data.about, segments = data.segments or {},
                nodes = data.nodes or {}, groups = data.groups or {}, crossings = data.crossings or {} }
        end
    end
end

-- ------------------------------------------------------------------ JSON writer (diff-friendly)

local KEY_ORDER = { "id", "kind", "type", "name", "a", "b", "x", "y", "z", "rz", "trunk", "normal", "reverse",
    "ends", "group", "spring", "nodes", "tags", "pts" }
local ARRAY_KEYS = { tags = true, ends = true, nodes = true, pts = true }

local function num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function str(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local enc
local function encObject(t)
    local keys, seen = {}, {}
    for _, k in ipairs(KEY_ORDER) do if t[k] ~= nil then keys[#keys + 1] = k seen[k] = true end end
    local rest = {}
    for k in pairs(t) do if not seen[k] and k ~= "file" and type(k) == "string" then rest[#rest + 1] = k end end
    table.sort(rest)
    for _, k in ipairs(rest) do keys[#keys + 1] = k end
    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" and next(v) == nil then
            parts[#parts + 1] = str(k) .. ": " .. (ARRAY_KEYS[k] and "[]" or "{}")
        else
            parts[#parts + 1] = str(k) .. ": " .. enc(v)
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

enc = function(v)
    local t = type(v)
    if t == "number" then return num(v)
    elseif t == "string" then return str(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = enc(v[i]) end
            return "[" .. table.concat(parts, ", ") .. "]"
        end
        return encObject(v)
    end
    return "null"
end

local function encodeSegment(sg)
    local head = {}
    for k, v in pairs(sg) do if k ~= "pts" then head[k] = v end end
    local s = encObject(head)
    local rows = {}
    for i = 1, #sg.pts, 4 do
        local r = {}
        for j = i, math.min(i + 3, #sg.pts) do r[#r + 1] = enc(sg.pts[j]) end
        rows[#rows + 1] = "        " .. table.concat(r, ", ")
    end
    return s:sub(1, -3) .. ',\n      "pts": [\n' .. table.concat(rows, ",\n") .. "\n      ] }"
end

local function encodeFile(f)
    local out = { "{\n" }
    if f.about then out[#out + 1] = '  "about": ' .. str(f.about) .. ",\n" end
    local list = {}
    for i, sg in ipairs(f.segments) do list[i] = "    " .. encodeSegment(sg) end
    out[#out + 1] = '  "segments": [\n' .. table.concat(list, ",\n") .. "\n  ],\n"
    list = {}
    for i, n in ipairs(f.nodes) do list[i] = "    " .. encObject(n) end
    out[#out + 1] = '  "nodes": [\n' .. table.concat(list, ",\n") .. "\n  ],\n"
    list = {}
    for i, g in ipairs(f.groups) do list[i] = "    " .. encObject(g) end
    out[#out + 1] = '  "groups": [\n' .. table.concat(list, ",\n") .. "\n  ],\n"
    out[#out + 1] = '  "crossings": ' .. enc(f.crossings) .. "\n}\n"
    return table.concat(out)
end

-- ------------------------------------------------------------------ build + broadcast

local function payload()
    local t = {}
    for i, f in ipairs(files) do
        t[i] = { file = f.file, segments = f.segments, nodes = f.nodes, groups = f.groups, crossings = f.crossings }
    end
    return t
end

local function sendTo(players)
    if #players == 0 then return end
    triggerLatentClientEvent(players, "rw:net:data", 2 * 1024 * 1024, false, resourceRoot, payload(), Net.getStates())
end

local function readyPlayers()
    local t = {}
    for p in pairs(ready) do if isElement(p) then t[#t + 1] = p else ready[p] = nil end end
    return t
end

local function rebuild()
    local ms = Net.build(payload())
    local s = Net.summary()
    log("network built in %d ms: %d segments, %d nodes, %d groups, %.1f km", ms, s.segments, s.nodes, s.groups, s.length / 1000)
    if Trains then Trains.onNetworkRebuilt() end
    triggerEvent("onNetNetworkRebuilt", root)
    return ms
end

addEvent("onNetNetworkRebuilt", false)

-- shared with the other server files
NetServer = { readyPlayers = readyPlayers, isAdmin = isAdmin, log = log }

-- after an edit: rebuild now (exports return fresh data), broadcast once the edits settle
local function changed()
    rebuild()
    if isTimer(rebuildTimer) then killTimer(rebuildTimer) end
    rebuildTimer = setTimer(function() sendTo(readyPlayers()) end, 300, 1)
end

addEvent("rw:net:hello", true)
addEventHandler("rw:net:hello", resourceRoot, function()
    ready[client] = true
    sendTo({ client })
end)

addEventHandler("onPlayerQuit", root, function() ready[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    loadAll()
    rebuild()
end)

-- ------------------------------------------------------------------ edit helpers

local function find(kind, id)
    for _, f in ipairs(files) do
        for i, item in ipairs(f[kind]) do
            if item.id == id then return f, i, item end
        end
    end
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

local function put(kind, item, file)
    if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then return false, "id missing" end
    item = copy(item)
    item.file = nil
    local f, i = find(kind, item.id)
    if f and (not file or file == f.file) then
        f[kind][i] = item
    else
        if f then table.remove(f[kind], i) dirty[f.file] = true end
        f = fileEntry(file or "custom.json")
        f[kind][#f[kind] + 1] = item
    end
    dirty[f.file] = true
    changed()
    return true, f.file
end

local function remove(kind, id)
    local f, i = find(kind, id)
    if not f then return false, "not found" end
    table.remove(f[kind], i)
    dirty[f.file] = true
    changed()
    return true
end

-- ------------------------------------------------------------------ exports: editing

-- seg = { id, kind, name, a, b, tags, pts = { {x,y,z}, ... } }; file = data file (default: the
-- one it is in, new segments go to custom.json)
function netPutSegment(seg, file)
    if type(seg) ~= "table" or type(seg.pts) ~= "table" or #seg.pts < 2 then return false, "pts: at least 2 points" end
    for _, p in ipairs(seg.pts) do
        if type(p) ~= "table" or not tonumber(p[1]) or not tonumber(p[2]) or not tonumber(p[3]) then
            return false, "pts: {x, y, z} numbers"
        end
    end
    seg.tags = seg.tags or {}
    seg.kind = seg.kind or "other"
    return put("segments", seg, file)
end

function netDeleteSegment(id) return remove("segments", id) end

-- node = { id, type = link|switch|buffer, ends | trunk, normal, reverse, group, spring, x, y, z }
function netPutNode(node, file)
    if type(node) ~= "table" or not (node.type == "link" or node.type == "switch" or node.type == "buffer") then
        return false, "type: link | switch | buffer"
    end
    return put("nodes", node, file)
end

function netDeleteNode(id) return remove("nodes", id) end

-- group = { id, name, nodes = { nodeId, ... }, spring }  (a switch: its nodes are thrown together)
function netPutGroup(group, file) return put("groups", group, file) end
function netDeleteGroup(id) return remove("groups", id) end

function netPutCrossing(a, b, file)
    local f = fileEntry(file or "custom.json")
    f.crossings[#f.crossings + 1] = { a, b }
    dirty[f.file] = true
    changed()
    return true
end

function netGetSegment(id)
    local f, _, item = find("segments", id)
    if not f then return false end
    local c = copy(item)
    c.file = f.file
    return c
end

function netGetNode(id)
    local f, _, item = find("nodes", id)
    if not f then return false end
    local c = copy(item)
    c.file = f.file
    return c
end

-- writes every changed file (and the manifest) -> list of files written
function netSave()
    local written = {}
    for _, f in ipairs(files) do
        if dirty[f.file] then
            if writeFile(NET.DATA_DIR .. f.file, encodeFile(f)) then
                written[#written + 1] = f.file
                dirty[f.file] = nil
            else
                log("cannot write %s", f.file)
            end
        end
    end
    local manifest = {}
    for i, f in ipairs(files) do manifest[i] = '    "' .. f.file .. '"' end
    writeFile(NET.MANIFEST, '{\n  "files": [\n' .. table.concat(manifest, ",\n") .. "\n  ]\n}\n")
    return written
end

-- throws away unsaved edits
function netReload()
    loadAll()
    dirty = {}
    changed()
    return Net.summary()
end

-- ------------------------------------------------------------------ exports: queries

function netSummary()
    local s = Net.summary()
    local d = {}
    for f in pairs(dirty) do d[#d + 1] = f end
    s.unsaved = d
    local fl = {}
    for i, f in ipairs(files) do fl[i] = f.file end
    s.files = fl
    return s
end

-- { { id, kind, name, len, a, b, tags, file } } (optionally one kind only)
function netListSegments(kind)
    local t = {}
    for _, id in ipairs(Net.segmentIds()) do
        local g = Net.segment(id)
        if not kind or g.kind == kind then
            t[#t + 1] = { id = id, kind = g.kind, name = g.name, len = g.len, a = g.a, b = g.b, tags = g.tags, file = g.file }
        end
    end
    return t
end

function netProject(x, y, z, maxDist)
    local seg, s, d = Net.project(x, y, z, maxDist)
    if not seg then return false end
    local px, py, pz = Net.pointAt(seg, s)
    return { seg = seg, s = s, dist = d, x = px, y = py, z = pz, radius = Net.radiusAt(seg, s), grade = Net.gradeAt(seg, s) }
end

function netPointAt(seg, s)
    local x, y, z, tx, ty, tz = Net.pointAt(seg, s)
    if not x then return false end
    return { x = x, y = y, z = z, tx = tx, ty = ty, tz = tz }
end

function netAdvance(seg, s, dir, ds)
    local nseg, ns, ndir, left, passed, stop = Net.advance(seg, s, dir, ds)
    return { seg = nseg, s = ns, dir = ndir, left = left, passed = passed, stop = stop }
end

function netGetSwitch(group) return Net.getState(group) end

-- Switches are thrown by the routes (server/switches.lua); this is the admin / debug override.
-- force = ignore locks, reservations and damage (and repair it).
function netSetSwitch(group, state, force)
    local ok, err = Switches.throw(group, state, { force = force and true or false, reason = "manual" })
    if not ok then return false, err end
    return Net.getState(group)
end

-- ------------------------------------------------------------------ commands

-- /rwnetswitch <group> [normal|reverse]
-- /rwnetswitch <group> [normal|reverse] [force]   (debug: the system throws the switches itself)
addCommandHandler("rwnetswitch", function(p, _, group, state, force)
    if not isAdmin(p) then return outputChatBox("[SLR] Nincs jogod ehhez.", p, 255, 80, 80) end
    if not group or not Net.group(group) then return outputChatBox("[SLR] Ismeretlen váltó: " .. tostring(group), p, 255, 80, 80) end
    if state == "force" then state, force = nil, "force" end
    state = state or (Net.getState(group) == "normal" and "reverse" or "normal")
    local ok, err = netSetSwitch(group, state, force == "force")
    if ok then outputChatBox("[SLR] " .. group .. " -> " .. Net.getState(group), p, 120, 200, 255)
    else outputChatBox("[SLR] " .. group .. ": " .. tostring(err) .. " (force: /rwnetswitch " .. group .. " " .. state .. " force)", p, 255, 120, 80) end
end)

-- /rwnetcheck : validation summary
addCommandHandler("rwnetcheck", function(p)
    if not isAdmin(p) then return outputChatBox("[SLR] Nincs jogod ehhez.", p, 255, 80, 80) end
    local r = netValidate()
    outputChatBox(string.format("[SLR] Hálózat: %d hiba, %d figyelmeztetés (részletek a debug logban)", r.errors, r.warnings), p, 120, 200, 255)
    for _, i in ipairs(r.issues) do
        if i.level ~= "info" then log("%s %s %s: %s", i.level, i.code, i.ref or "", i.msg) end
    end
end)

-- /rwnetreload : reload the files (drops unsaved edits)
addCommandHandler("rwnetreload", function(p)
    if not isAdmin(p) then return outputChatBox("[SLR] Nincs jogod ehhez.", p, 255, 80, 80) end
    netReload()
    outputChatBox("[SLR] Hálózat újratöltve.", p, 120, 200, 255)
end)
