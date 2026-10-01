-- Fénypont elrendezések modellenként (lights.json).
-- A szerver tölti be és ellenőrzi, a kliensek tőle kapják meg; a /elseditor
-- mentése ide fut be. A fájlt a kliensek nem töltik le.
--
-- layout = { points = { { x, y, z, r, g, b, group, size }, ... } }
-- (x, y, z a jármű középpontjához képest, jármű-koordinátában)

local FILE = "lights.json"
local MAX_OFFSET = 10

Layouts = { byModel = {} }

local validGroup = {}
for _, g in ipairs(ELS_GROUPS) do validGroup[g] = true end

local function round(v, decimals)
    local m = 10 ^ decimals
    return math.floor(v * m + 0.5) / m
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function cleanPoint(p)
    if type(p) ~= "table" then return nil end

    local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
    local r, g, b = tonumber(p.r), tonumber(p.g), tonumber(p.b)
    if not (x and y and z and r and g and b) then return nil end
    if math.abs(x) > MAX_OFFSET or math.abs(y) > MAX_OFFSET or math.abs(z) > MAX_OFFSET then return nil end

    return {
        x = round(x, 3), y = round(y, 3), z = round(z, 3),
        r = clamp(math.floor(r), 0, 255),
        g = clamp(math.floor(g), 0, 255),
        b = clamp(math.floor(b), 0, 255),
        group = validGroup[p.group] and p.group or "A",
        size  = round(clamp(tonumber(p.size) or 0.3, ELS_SIZE_MIN, ELS_SIZE_MAX), 2),
    }
end

-- ellenőrzött másolat, vagy nil ha nincs benne egy érvényes pont sem
function Layouts.clean(layout)
    if type(layout) ~= "table" or type(layout.points) ~= "table" then return nil end

    local points = {}
    for _, p in ipairs(layout.points) do
        local clean = cleanPoint(p)
        if clean then
            points[#points + 1] = clean
            if #points >= ELS_MAX_POINTS then break end
        end
    end
    return #points > 0 and { points = points } or nil
end

function Layouts.get(model)
    return Layouts.byModel[model]
end

local function load()
    local file = fileExists(FILE) and fileOpen(FILE, true)
    if not file then return end

    local data = fromJSON(fileRead(file, fileGetSize(file)))
    fileClose(file)
    if type(data) ~= "table" then
        outputDebugString("[v_els] " .. FILE .. " is not valid JSON", 1)
        return
    end

    for key, layout in pairs(data) do
        local model = tonumber(key)
        if model and sirenVehicles[model] then
            Layouts.byModel[model] = Layouts.clean(layout)
        end
    end
end

local function save()
    local data = {}
    for model, layout in pairs(Layouts.byModel) do
        data[tostring(model)] = layout
    end

    local file = fileCreate(FILE)
    if not file then return false end
    fileWrite(file, toJSON(data, false, "spaces"))
    fileClose(file)
    return true
end

-- új elrendezés mentése (nil = törlés); visszaadja, sikerült-e a fájlba írás
function Layouts.set(model, layout)
    Layouts.byModel[model] = Layouts.clean(layout)
    local ok = save()

    triggerClientEvent(root, "els:layout", resourceRoot, model, Layouts.byModel[model] or false)
    refreshModelSirens(model)
    return ok
end

------------------------------------------------------------
-- KLIENS SZINKRON
------------------------------------------------------------

-- a kliens a saját scriptjei betöltése után kéri le (így biztosan van handlere)
addEvent("els:requestLayouts", true)
addEventHandler("els:requestLayouts", resourceRoot, function()
    triggerClientEvent(client, "els:layouts", resourceRoot, Layouts.byModel)
end)

load()
