-- wx_snow :: /snowbake - roof map bake on an admin client (DESIGN.md 5)
--
-- The map is cut into tiles (SNOW.ROOF.TILE cells). For every tile the player (frozen) and the
-- camera go there so the collisions and the maps_loader objects stream in, then for every cell
-- SUB rays go straight down; the cell's value is the LOWEST of their first hits (so ground right
-- next to a wall does not count as covered). Result: R = high, G = low byte of the 16 bit height.
-- At the end the png goes to the server (server/bake.lua) in chunks; restart wx_snow to use it.
--
--   /snowbake start [tile]   start (or restart from a tile index)
--   /snowbake stop           pause (data stays in memory, start <tile> continues)
--   /snowbake status
--   /snowbake save           build + upload what is done (missing tiles = not covered)

BAKE = { running = false, co = nil, data = {}, tile = 0, hits = 0, rays = 0, started = 0, phase = "" }

local R = SNOW.ROOF
local CELLS = R.SIZE / R.CELL
local PER_SIDE = CELLS / R.TILE
local TILES = PER_SIDE * PER_SIDE

local waitUntil = 0
local frameStart = 0

local function yieldBudget()
    if getTickCount() - frameStart > R.BUDGET_MS then coroutine.yield() end
end

local function wait(ms)
    waitUntil = getTickCount() + ms
    coroutine.yield()
end

local function pack(z)
    local h = math.floor((z - R.Z_MIN) / (R.Z_MAX - R.Z_MIN) * 65535 + 0.5)
    h = math.max(0, math.min(65535, h))
    return string.char(math.floor(h / 256), h % 256)
end

local function rayTop(x, y)
    BAKE.rays = BAKE.rays + 1
    local hit, _, _, hz = processLineOfSight(x, y, R.RAY_TOP, x, y, R.RAY_BOTTOM,
        true, false, false, true, false, false, false, false, localPlayer)
    if hit then return hz end
    return nil
end

local function moveTo(x, y, z)
    setElementPosition(localPlayer, x, y, z)
    setCameraMatrix(x, y, z + 25, x + 30, y + 30, z - 10)
end

local function bakeTile(index)
    local tx, ty = index % PER_SIDE, math.floor(index / PER_SIDE)
    local x0 = R.MIN_X + tx * R.TILE * R.CELL
    local y0 = R.MIN_Y + ty * R.TILE * R.CELL
    local half = R.TILE * R.CELL / 2
    local cx, cy = x0 + half, y0 + half

    -- go there, wait for collisions; if the ground is far from where we guessed, go closer
    local guess = BAKE.lastGround or 20
    BAKE.phase = "stream"
    moveTo(cx, cy, guess + 40)
    wait(R.WAIT_MS)
    local g = rayTop(cx, cy)
    if g and math.abs(g + 40 - (guess + 40)) > 60 then
        moveTo(cx, cy, g + 40)
        wait(R.WAIT_MS / 2)
    end
    if g then BAKE.lastGround = g end

    BAKE.phase = "rays"
    local out = {}
    for j = 0, R.TILE - 1 do
        local y = y0 + (j + 0.5) * R.CELL
        for i = 0, R.TILE - 1 do
            local x = x0 + (i + 0.5) * R.CELL
            local low = nil
            for _, s in ipairs(R.SUB) do
                local z = rayTop(x + s[1], y + s[2])
                if not z then low = nil break end -- one sample sees water / nothing: open sky
                if not low or z < low then low = z end
            end
            if low then BAKE.hits = BAKE.hits + 1 end
            out[#out + 1] = pack(low or R.Z_MIN)
        end
        yieldBudget()
    end
    BAKE.data[index] = table.concat(out)
end

-- "plain" pixel format of this client: raw BGRA + trailer; the trailer layout is read from a probe
local function plainTrailer(w, h)
    local probe = dxCreateTexture(3, 2)
    if not probe then return nil end
    local px = dxGetTexturePixels(probe)
    destroyElement(probe)
    if not px or #px ~= 3 * 2 * 4 + 4 then return nil end
    local t = px:sub(-4)
    if t == string.char(3, 0, 2, 0) then
        return string.char(w % 256, math.floor(w / 256), h % 256, math.floor(h / 256))
    elseif t == string.char(0, 3, 0, 2) then
        return string.char(math.floor(w / 256), w % 256, math.floor(h / 256), h % 256)
    end
    return nil
end

local function toBGRA(seg)
    return (seg:gsub("(.)(.)", function(hi, lo) return "\0" .. lo .. hi .. "\255" end))
end

local function upload(png, info)
    local chunk = R.CHUNK
    local total = math.ceil(#png / chunk)
    BAKE.phase = "upload"
    BAKE.acked = 0
    for i = 1, total do
        triggerLatentServerEvent("wx_snow:bakeChunk", 200000, false, resourceRoot, i, total, png:sub((i - 1) * chunk + 1, i * chunk))
        local deadline = getTickCount() + 60000
        while (BAKE.acked or 0) < i do
            if getTickCount() > deadline then
                snowMessage("wx_snow.bake.upload_failed")
                return false
            end
            wait(100)
        end
        BAKE.uploadPart = i .. "/" .. total
    end
    triggerServerEvent("wx_snow:bakeDone", resourceRoot, info)
    return true
end

addEvent("wx_snow:bakeAck", true)
addEventHandler("wx_snow:bakeAck", resourceRoot, function(index) BAKE.acked = math.max(BAKE.acked or 0, tonumber(index) or 0) end)

local function build()
    BAKE.phase = "build"
    local trailer = plainTrailer(CELLS, CELLS)
    if not trailer then
        snowMessage("wx_snow.bake.pixels_failed")
        return false
    end
    local blank = string.rep(pack(R.Z_MIN), R.TILE)
    local rows = {}
    for j = 0, CELLS - 1 do
        local ty, jj = math.floor(j / R.TILE), j % R.TILE
        local parts = {}
        for tx = 0, PER_SIDE - 1 do
            local d = BAKE.data[ty * PER_SIDE + tx]
            parts[#parts + 1] = d and d:sub(jj * R.TILE * 2 + 1, (jj + 1) * R.TILE * 2) or blank
        end
        rows[#rows + 1] = toBGRA(table.concat(parts))
        yieldBudget()
    end
    local plain = table.concat(rows) .. trailer
    rows = nil
    local png = dxConvertPixels(plain, "png")
    if not png then
        snowMessage("wx_snow.bake.pixels_failed")
        return false
    end
    local done = 0
    for _ in pairs(BAKE.data) do done = done + 1 end
    return upload(png, { minX = R.MIN_X, minY = R.MIN_Y, size = R.SIZE, cells = CELLS,
        zMin = R.Z_MIN, zMax = R.Z_MAX, tiles = done, hits = BAKE.hits })
end

local saved = nil

local function restorePlayer()
    if saved then
        triggerServerEvent("wx_snow:testMove", resourceRoot, saved.x, saved.y, saved.z, saved.int, saved.dim)
        saved = nil
    end
    setElementFrozen(localPlayer, false)
    setCameraTarget(localPlayer)
end

local function finish(ok)
    BAKE.running, BAKE.co = false, nil
    restorePlayer()
    if ok ~= nil then
        snowMessage(ok and "wx_snow.bake.uploaded" or "wx_snow.bake.failed")
    end
end

local function runAll(from, onlySave)
    if not onlySave then
        for index = from, TILES - 1 do
            BAKE.tile = index
            bakeTile(index)
            if index % 24 == 23 then
                snowMessage("wx_snow.bake.progress", { done = index + 1, total = TILES,
                    minutes = math.ceil((TILES - index - 1) * (R.WAIT_MS + 600) / 60000) })
            end
        end
        restorePlayer()
    end
    return build()
end

local function step()
    if not BAKE.co then return end
    if getTickCount() < waitUntil then return end
    frameStart = getTickCount()
    local ok, res = coroutine.resume(BAKE.co)
    if not ok then
        outputDebugString("[wx_snow] bake: " .. tostring(res), 1)
        finish(false)
    elseif coroutine.status(BAKE.co) == "dead" then
        finish(res == true)
    end
end
addEventHandler("onClientRender", root, step)

-- progress on screen
addEventHandler("onClientRender", root, function()
    if not BAKE.running then return end
    local sw = guiGetScreenSize()
    local text = L("wx_snow.bake.overlay", { tile = BAKE.tile + 1, total = TILES, phase = BAKE.phase,
        rays = BAKE.rays, part = BAKE.uploadPart or "-" })
    dxDrawRectangle(sw / 2 - 260, 20, 520, 34, tocolor(0, 0, 0, 170))
    dxDrawText(text, sw / 2 - 250, 20, sw / 2 + 250, 54, tocolor(255, 255, 255), 1, "default-bold", "center", "center")
end)

local function start(from, onlySave)
    if BAKE.running then return snowMessage("wx_snow.bake.already") end
    if getPedOccupiedVehicle(localPlayer) then return snowMessage("wx_snow.bake.on_foot") end
    local x, y, z = getElementPosition(localPlayer)
    saved = { x = x, y = y, z = z, int = getElementInterior(localPlayer), dim = getElementDimension(localPlayer) }
    if not onlySave then
        triggerServerEvent("wx_snow:testMove", resourceRoot, false, false, false, 0, 0)
        setElementFrozen(localPlayer, true)
    end
    BAKE.running, BAKE.started, BAKE.uploadPart = true, getTickCount(), nil
    BAKE.co = coroutine.create(function() return runAll(from, onlySave) end)
    snowMessage("wx_snow.bake.started", { from = from + 1, total = TILES,
        minutes = math.ceil((TILES - from) * (R.WAIT_MS + 600) / 60000) })
end

SNOW_COMMANDS.bake = function(a)
    local action = a.action
    if action == "start" then
        local from = math.max(0, math.min(TILES - 1, math.floor((tonumber(a.from) or 1) - 1)))
        if from == 0 then BAKE.data, BAKE.hits, BAKE.rays = {}, 0, 0 end
        start(from, false)
    elseif action == "stop" then
        if not BAKE.running then return snowMessage("wx_snow.bake.not_running") end
        finish(nil)
        snowMessage("wx_snow.bake.stopped", { tile = BAKE.tile + 1 })
    elseif action == "save" then
        start(0, true)
    else
        local done = 0
        for _ in pairs(BAKE.data) do done = done + 1 end
        snowMessage("wx_snow.bake.status", { running = BAKE.running and L("wx_snow.yes") or L("wx_snow.no"),
            done = done, total = TILES, loaded = ROOF.isLoaded() and L("wx_snow.yes") or L("wx_snow.no") })
    end
end
