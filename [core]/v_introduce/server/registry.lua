-- Module registry. A module is one chapter of the introduction: plain data (no functions), so
-- it can be sent to the client as it is. The modules of this resource are in modules/*.lua and
-- call Intro.module{...}; other resources call exports.v_introduce:registerModule{...}.
--
-- Module fields:
--   id        unique string
--   order     number, chapters run in ascending order
--   version   number >= 1; raise it when the content changes a lot - players who saw an older
--             version get the module again ("What's new")
--   title     shown in the chapter bar
--   xp        reward for finishing it the first time
--   requires  { "resource", ... }  - the module is left out while one of them is not running
--   final     true: the last chapter, gets the XP top-up (INTRO.REWARD_TOTAL_XP)
--   rules     true: finishing it stores INTRO.RULES_VERSION as accepted
--   update    true: an update module (updates/*.lua). It is NOT part of the main line: only
--             players who had already finished the introduction get it ("What's new"). A player
--             who finishes the main line gets every current update marked as seen.
--   expires   "YYYY-MM-DD" (update modules): from this day on nobody gets it any more
--   scenes  { scene, ... }  (see client/scenes.lua); a scene may have its own requires too
--
-- Resources in INTRO.BLOCKED_RESOURCES (v_modmenu) can neither register a module nor be
-- required by one.

Intro = Intro or {}
local modules = {}     -- id -> def
local owners = {}      -- id -> resource name

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local SCENE_TYPES = { camera = true, card = true, task = true, highlight = true, world = true, accept = true }

-- -> true | false, reason
local function validate(def)
    if type(def) ~= "table" then return false, "module is not a table" end
    if type(def.id) ~= "string" or def.id == "" then return false, "missing id" end
    if type(def.title) ~= "string" then return false, def.id .. ": missing title" end
    if type(def.scenes) ~= "table" or #def.scenes == 0 then return false, def.id .. ": no scenes" end
    for i, scene in ipairs(def.scenes) do
        if type(scene) ~= "table" or not SCENE_TYPES[scene.type] then
            return false, ("%s: scene %d has an unknown type"):format(def.id, i)
        end
        for _, name in ipairs(scene.requires or {}) do
            if INTRO.isBlocked(name) then return false, def.id .. ": requires a blocked resource (" .. name .. ")" end
        end
    end
    for _, name in ipairs(def.requires or {}) do
        if INTRO.isBlocked(name) then return false, def.id .. ": requires a blocked resource (" .. name .. ")" end
    end
    if def.expires ~= nil and (type(def.expires) ~= "string" or not def.expires:match("^%d%d%d%d%-%d%d%-%d%d$")) then
        return false, def.id .. ": expires must be \"YYYY-MM-DD\""
    end
    if def.update and def.final then return false, def.id .. ": an update module cannot be final" end
    return true
end

local function today()
    local t = getRealTime()
    return ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

function Intro.isExpired(def)
    return def.expires ~= nil and today() >= def.expires
end

-- -> true | false, reason
function Intro.register(def, ownerName)
    if INTRO.isBlocked(ownerName) then return false, ownerName .. " may not add introduction modules" end
    local ok, err = validate(def)
    if not ok then return false, err end
    if modules[def.id] and owners[def.id] ~= ownerName then
        return false, "module id '" .. def.id .. "' is already used by " .. tostring(owners[def.id])
    end
    def.order = tonumber(def.order) or 1000
    def.version = math.max(1, math.floor(tonumber(def.version) or 1))
    def.xp = math.max(0, math.floor(tonumber(def.xp) or 0))
    def.requires = def.requires or {}
    modules[def.id] = def
    owners[def.id] = ownerName
    return true
end

-- modules/*.lua
function Intro.module(def)
    local ok, err = Intro.register(def, getResourceName(resource))
    if not ok then outputDebugString("[v_introduce] module refused: " .. tostring(err), 1) end
end

function Intro.get(id) return modules[id] end

-- The module can run now: every required resource is running and it has not expired.
function Intro.isAvailable(def)
    if Intro.isExpired(def) then return false end
    for _, name in ipairs(def.requires) do
        if not isRunning(name) then return false end
    end
    return true
end

-- Every available module, in chapter order. kind: nil = all, "main" = main line, "update" = updates
function Intro.available(kind)
    local list = {}
    for _, def in pairs(modules) do
        local isUpdate = def.update == true
        if Intro.isAvailable(def) and (kind == nil or (kind == "update") == isUpdate) then
            list[#list + 1] = def
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return list
end

-- The copy sent to the client: scenes whose own requirements are missing are left out
function Intro.clientCopy(def)
    local scenes = {}
    for _, scene in ipairs(def.scenes) do
        local ok = true
        for _, name in ipairs(scene.requires or {}) do
            if not isRunning(name) then ok = false break end
        end
        if ok then scenes[#scenes + 1] = scene end
    end
    return { id = def.id, title = def.title, xp = def.xp, final = def.final, update = def.update, scenes = scenes }
end

-- Minimum seconds the module takes (server-side check against finishing it too fast)
function Intro.minDuration(copy)
    local total = 0
    for _, scene in ipairs(copy.scenes) do total = total + INTRO.sceneMinTime(scene) end
    return total
end

---------------------------------------------------------------- exports

function registerModule(def)
    local owner = sourceResource and getResourceName(sourceResource) or getResourceName(resource)
    return Intro.register(def, owner)
end

function unregisterModule(id)
    local owner = sourceResource and getResourceName(sourceResource) or getResourceName(resource)
    if modules[id] and owners[id] == owner then
        modules[id], owners[id] = nil, nil
        return true
    end
    return false
end

-- a stopped resource takes its modules with it
addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    for id, owner in pairs(owners) do
        if owner == name and res ~= resource then modules[id], owners[id] = nil, nil end
    end
end)
