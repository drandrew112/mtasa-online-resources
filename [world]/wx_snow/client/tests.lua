-- wx_snow :: /snowtest (DESIGN.md 10)
--
--   /snowtest interiors  every world_interiors interior: snow 5 vs snow 0 screen diff must be ~0,
--                        and the state must say indoor / no shader / no flakes
--   /snowtest zones      the same for every maps_loader "indoor" box (int 0)
--   /snowtest tour       outdoor points: level 0 / 2 / 4 / 5 by day, 4 at night: FPS, share of
--                        snow white pixels, screenshot (@shots/<point>_<case>.png in the client's
--                        wx_snow private folder), report @wx_snow_tour_<variant>_<quality>.json
--   /snowtest cost       where the fixed fps cost comes from (ground / snowfall / foliage / generic distance)
--   /snowtest stop
--
-- Local only: the levels are a /snow preview, the weather / server state is not touched.

TESTS = { running = false, co = nil, kind = nil, results = {} }

local CAP_W, CAP_H = 640, 360

-- outdoor points: x, y (z from the ground), camera heading (deg)
local TOUR = {
    { id = "ls_pershing",      x = 1481,  y = -1700, h = 0 },
    { id = "ls_grove",         x = 2495,  y = -1668, h = 90 },
    { id = "ls_santamaria",    x = 370,   y = -1830, h = 180 },
    { id = "ls_vinewood",      x = 1338,  y = -829,  h = 200 },
    { id = "ls_unity",         x = 1765,  y = -1940, h = 0 },
    { id = "ls_idlewood_gas",  x = 1941,  y = -1772, h = 90 },   -- canopy: covered under it
    { id = "ls_allsaints",     x = 1180,  y = -1325, h = 270 },
    { id = "ls_airport",       x = 1680,  y = -2450, h = 90 },
    { id = "ls_freeway",       x = 1700,  y = -1800, h = 0 },
    { id = "ls_market",        x = 820,   y = -1340, h = 90 },
    { id = "ls_rodeo",         x = 420,   y = -1430, h = 0 },
    { id = "ls_eastbeach",     x = 2800,  y = -1480, h = 90 },
    { id = "chiliad_top",      x = -2350, y = -1630, h = 45 },
    { id = "angel_pine",       x = -2150, y = -2400, h = 45 },
    { id = "whetstone_forest", x = -1600, y = -2200, h = 0 },
    { id = "flint_farm",       x = -380,  y = -1430, h = 90 },
    { id = "red_county",       x = 230,   y = -150,  h = 0 },
    { id = "dillimore",        x = 660,   y = -560,  h = 0 },
    { id = "montgomery",       x = 1300,  y = 250,   h = 0 },
    { id = "palomino",         x = 2330,  y = 60,    h = 180 },
    { id = "sf_downtown",      x = -1900, y = 900,   h = 0 },
    { id = "sf_chinatown",     x = -2200, y = 700,   h = 90 },
    { id = "sf_doherty",       x = -2030, y = 170,   h = 0 },
    { id = "sf_oceanflats",    x = -2650, y = -50,   h = 90 },
    { id = "sf_airport",       x = -1400, y = -200,  h = 0 },
    { id = "sf_gant_bridge",   x = -2680, y = 1600,  h = 0 },
    { id = "sf_bayside",       x = -2500, y = 2300,  h = 90 },
    { id = "lv_strip",         x = 2040,  y = 1500,  h = 0 },
    { id = "lv_fourdragons",   x = 2020,  y = 1010,  h = 90 },
    { id = "lv_airport",       x = 1480,  y = 1600,  h = 0 },
    { id = "lv_redsands",      x = 1800,  y = 2050,  h = 0 },
    { id = "fort_carson",      x = -150,  y = 1100,  h = 0 },
    { id = "area69",           x = 210,   y = 1900,  h = 0 },
    { id = "el_quebrados",     x = -1450, y = 2600,  h = 0 },
    { id = "las_barrancas",    x = -800,  y = 1500,  h = 0 },
    { id = "desert_dunes",     x = 600,   y = 1200,  h = 90 },
    { id = "bone_county",      x = 700,   y = 1900,  h = 0 },
    { id = "tierra_robada",    x = -1200, y = 1900,  h = 0 },
    { id = "hilltop_farm",     x = 1050,  y = -300,  h = 0 },
    { id = "panopticon",       x = -600,  y = -150,  h = 0 },
}

local CASES = {
    { id = "d0", level = 0, hour = 12 },
    { id = "d2", level = 2, hour = 12 },
    { id = "d4", level = 4, hour = 12 },
    { id = "d5", level = 5, hour = 12 },
    { id = "n4", level = 4, hour = 23 },
}

-------------------------------------------------------------------------------- coroutine helpers

local waitUntil, waitCond = 0, nil

local function wait(ms)
    waitUntil = getTickCount() + ms
    coroutine.yield()
end

local function waitFor(fn, timeout)
    waitCond = fn
    waitUntil = getTickCount() + (timeout or 5000)
    coroutine.yield()
    waitCond = nil
end

-------------------------------------------------------------------------------- capture

local capture = { src = nil, rt = nil, want = false, pixels = nil }

local function capturePixels()
    if not capture.src then
        capture.src = dxCreateScreenSource(CAP_W, CAP_H)
        capture.rt = dxCreateRenderTarget(CAP_W, CAP_H, false)
        if not capture.src or not capture.rt then return nil end
    end
    capture.pixels, capture.want = nil, true
    waitFor(function() return capture.pixels ~= nil end, 3000)
    return capture.pixels or nil
end

-- frame 1: screen -> render target, frame 2: read the render target (the draw has surely run)
addEventHandler("onClientRender", root, function()
    if capture.stage == 2 then
        capture.stage = nil
        capture.pixels = dxGetTexturePixels(capture.rt) or false
        return
    end
    if not capture.want then return end
    capture.want = false
    dxUpdateScreenSource(capture.src, true)
    dxSetRenderTarget(capture.rt, true)
    dxDrawImage(0, 0, CAP_W, CAP_H, capture.src)
    dxSetRenderTarget()
    capture.stage = 2
end)

-- mean abs difference (0..255) and share of changed pixels in the centre (HUD / notifications
-- at the edges are left out)
local function diff(a, b)
    if not a or not b then return 999, 1 end
    local sum, changed, n = 0, 0, 0
    for y = math.floor(CAP_H * 0.18), math.floor(CAP_H * 0.85), 4 do
        for x = math.floor(CAP_W * 0.1), math.floor(CAP_W * 0.9), 4 do
            local r1, g1, b1 = dxGetPixelColor(a, x, y)
            local r2, g2, b2 = dxGetPixelColor(b, x, y)
            if r1 and r2 then
                local d = (math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)) / 3
                sum, n = sum + d, n + 1
                if d > 12 then changed = changed + 1 end
            end
        end
    end
    if n == 0 then return 999, 1 end
    return sum / n, changed / n
end

-- share of bright, colourless pixels (snow) in the lower 2/3 of the picture
local function whiteShare(px)
    if not px then return 0 end
    local white, n = 0, 0
    for y = math.floor(CAP_H * 0.35), CAP_H - 8, 6 do
        for x = 8, CAP_W - 8, 6 do
            local r, g, b = dxGetPixelColor(px, x, y)
            if r then
                n = n + 1
                local mx, mn = math.max(r, g, b), math.min(r, g, b)
                if mx > 150 and mn > mx * 0.82 then white = white + 1 end
            end
        end
    end
    return n > 0 and white / n or 0
end

local function fps(ms)
    local frames, t0 = 0, getTickCount()
    local h = function() frames = frames + 1 end
    addEventHandler("onClientRender", root, h)
    wait(ms)
    removeEventHandler("onClientRender", root, h)
    return frames * 1000 / math.max(1, getTickCount() - t0)
end

local function savePng(px, name)
    local png = px and dxConvertPixels(px, "png")
    if not png then return false end
    local path = "@shots/" .. name .. ".png"
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if not f then return false end
    fileWrite(f, png)
    fileClose(f)
    return path
end

local function writeReport(name, data)
    local path = "@" .. name
    if fileExists(path) then fileDelete(path) end
    local f = fileCreate(path)
    if f then
        fileWrite(f, toJSON(data, false, "spaces"))
        fileClose(f)
    end
end

-------------------------------------------------------------------------------- moving around

local saved = nil

local function move(x, y, z, int, dim)
    triggerServerEvent("wx_snow:testMove", resourceRoot, x, y, z, int, dim)
    waitFor(function()
        local px, py = getElementPosition(localPlayer)
        return getElementInterior(localPlayer) == int and getElementDimension(localPlayer) == dim
            and math.abs(px - x) < 3 and math.abs(py - y) < 3
    end, 5000)
end

local function savePlace()
    local x, y, z = getElementPosition(localPlayer)
    local h, m = getTime()
    saved = { x = x, y = y, z = z, int = getElementInterior(localPlayer), dim = getElementDimension(localPlayer),
        preview = CS.preview, cover = CS.coverFixed, hour = h, minute = m }
end

local function restorePlace()
    if not saved then return end
    triggerServerEvent("wx_snow:testMove", resourceRoot, saved.x, saved.y, saved.z, saved.int, saved.dim)
    setElementFrozen(localPlayer, false)
    setCameraTarget(localPlayer)
    CS.preview, CS.coverFixed = saved.preview, saved.cover
    setTime(saved.hour, saved.minute)
    snowChanged("level")
    saved = nil
end

-------------------------------------------------------------------------------- indoor checks

-- snow 5 vs 0 at the current place; -> result table
local function indoorCheck(entry)
    setSnowPreview(SNOW.MAX_LEVEL, true)
    wait(1500)
    local st = getSnowDebugState()
    local a = capturePixels()
    setSnowPreview(0, true)
    wait(1200)
    local b = capturePixels()
    local mean, share = diff(a, b)
    -- interiors: the ground layers draw nothing; zones: the boxes mask them (the diff shows it)
    local ok = st.indoor and not (st.interior and st.groundActive) and st.flakesDrawn == 0 and mean < 2.5 and share < 0.01
    entry.indoor, entry.why, entry.shaders, entry.flakes = st.indoor, st.indoorWhy or false, st.groundActive and 1 or 0, st.flakesDrawn
    entry.meanDiff, entry.changed, entry.ok = math.floor(mean * 100) / 100, math.floor(share * 1000) / 1000, ok
    if not ok then entry.shot = savePng(a, "fail_" .. entry.id) end
    return entry
end

local function runInteriors(list)
    local results = {}
    for i, it in ipairs(list) do
        TESTS.progress = ("%d/%d %s"):format(i, #list, it.name)
        move(it.x, it.y, it.z + 0.5, it.interior, it.dimension)
        setCameraTarget(localPlayer)
        wait(2500)
        results[#results + 1] = indoorCheck({ id = it.id, name = it.name, interior = it.interior, dimension = it.dimension })
    end
    return results
end

local function runZones()
    local zones = {}
    if snowResourceRunning("maps_loader") then
        local ok, list = pcall(function() return exports.maps_loader:getIndoorZones(true) end)
        zones = ok and type(list) == "table" and list or {}
    end
    local results = {}
    for i, b in ipairs(zones) do
        local id = ("%s_%d"):format(tostring(b.map), i)
        TESTS.progress = ("%d/%d %s"):format(i, #zones, id)
        local x, y = (b[1] + b[4]) / 2, (b[2] + b[5]) / 2
        local z = math.min(b[3] + 1.2, b[6] - 0.5)
        move(x, y, z, 0, 0)
        setCameraTarget(localPlayer)
        setElementFrozen(localPlayer, true)
        wait(3500) -- maps_loader builds the indoor objects (250 ms zone check + streaming)
        results[#results + 1] = indoorCheck({ id = id, name = id })
        setElementFrozen(localPlayer, false)
    end
    return results
end

-------------------------------------------------------------------------------- tour

local function runTour()
    local results = {}
    for i, p in ipairs(TOUR) do
        TESTS.progress = ("%d/%d %s"):format(i, #TOUR, p.id)
        setElementFrozen(localPlayer, true)
        move(p.x, p.y, 200, 0, 0)
        setCameraMatrix(p.x, p.y, 230, p.x + 1, p.y + 1, 200)
        wait(2500)
        local gz = getGroundPosition(p.x, p.y, 500)
        if not gz or gz == 0 then gz = 20 end
        setElementPosition(localPlayer, p.x, p.y, gz + 1)
        local h = math.rad(p.h)
        local cx, cy = p.x - math.cos(h) * 14, p.y - math.sin(h) * 14
        setCameraMatrix(cx, cy, gz + 7, p.x + math.cos(h) * 20, p.y + math.sin(h) * 20, gz)
        wait(1500)
        local row = { id = p.id, x = p.x, y = p.y, z = gz, cases = {} }
        for _, c in ipairs(CASES) do
            setTime(c.hour, 0)
            setSnowPreview(c.level, true)
            wait(1800)
            local f = fps(1500)
            local px = capturePixels()
            local st = getSnowDebugState()
            row.cases[c.id] = {
                fps = math.floor(f * 10) / 10, white = math.floor(whiteShare(px) * 1000) / 1000,
                covered = st.covered, indoor = st.indoor, flakes = st.flakesDrawn, roof = st.roofHere or false,
                shot = savePng(px, p.id .. "_" .. c.id) or false,
            }
        end
        local d0, d4 = row.cases.d0, row.cases.d4
        row.fpsDrop4 = d0.fps > 0 and math.floor((1 - d4.fps / d0.fps) * 1000) / 10 or 0
        row.whiteGain4 = math.floor((d4.white - d0.white) * 1000) / 1000
        results[#results + 1] = row
        outputConsole(("[snowtest] %-18s fps %5.1f -> %5.1f (L4, -%4.1f%%)  white %.2f -> %.2f"):format(
            p.id, d0.fps, d4.fps, row.fpsDrop4, d0.white, d4.white))
    end
    setElementFrozen(localPlayer, false)
    return results
end

-------------------------------------------------------------------------------- cost split

-- Where does the fixed fps drop come from? Same spot, same camera, level 4 by day: nothing / everything /
-- only snowfall / only ground shaders / ground without foliage. Run it with vsync off and the fps limit
-- high, otherwise the numbers jump between frame limiter steps.
local function runCost()
    local results = {}
    local function measure(name, level, groundOff, flakesOff, noFoliage, genericDist, noGeneric)
        GROUND.costMode(groundOff, noFoliage, genericDist, noGeneric)
        PRECIP.disabled = flakesOff
        setSnowPreview(level, true)
        wait(2500)
        local f = fps(3000)
        results[#results + 1] = { name = name, fps = math.floor(f * 10) / 10 }
        outputConsole(("[snowtest] cost %-26s fps %6.1f"):format(name, f))
    end
    setElementFrozen(localPlayer, true)
    setTime(12, 0)
    measure("warm up (ignore)", 0, false, false, false)
    measure("level 0 (no snow)", 0, false, false, false)
    measure("level 4 snowfall only", 4, true, false, false)
    measure("ground, generic unlimited", 4, false, true, false, 0)
    measure("ground, generic 250 m", 4, false, true, false, 250)
    measure("ground, generic 120 m", 4, false, true, false, 120)
    measure("ground, generic 60 m", 4, false, true, false, 60)
    measure("ground, no generic at all", 4, false, true, false, nil, true)
    measure("ground, no generic, no foliage", 4, false, true, true, nil, true)
    measure("level 4 config (everything)", 4, false, false, false)
    measure("level 0 (no snow) again", 0, false, false, false)
    GROUND.costMode(false, false)
    PRECIP.disabled = false
    setElementFrozen(localPlayer, false)
    return results
end

-------------------------------------------------------------------------------- runner

local function summary(kind, results)
    if kind == "cost" then
        writeReport("wx_snow_cost_" .. tostring(GROUND.variant) .. ".json", results)
        snowMessage("wx_snow.test.tour_done", { n = #results, drop = 0, low = "see the console" })
        return
    end
    if kind == "tour" then
        local drop, n, low = 0, 0, {}
        for _, r in ipairs(results) do
            drop, n = drop + r.fpsDrop4, n + 1
            if r.whiteGain4 < 0.05 then low[#low + 1] = r.id end
        end
        -- one file per shader variant / quality, so v1 (before F1) and v2 can be compared; the console
        -- prints the average fps of every case and its drop against the snow free case d0
        local name = ("wx_snow_tour_%s_%s.json"):format(tostring(GROUND.variant), tostring(CS.quality))
        writeReport(name, results)
        local sum, cnt = {}, 0
        for _, r in ipairs(results) do
            cnt = cnt + 1
            for id, cs in pairs(r.cases) do sum[id] = (sum[id] or 0) + cs.fps end
        end
        if cnt > 0 and (sum.d0 or 0) > 0 then
            for _, c in ipairs(CASES) do
                local avg = (sum[c.id] or 0) / cnt
                outputConsole(("[snowtest] %s/%s %-3s avg fps %6.1f  (-%4.1f%% vs d0)  report @%s"):format(
                    tostring(GROUND.variant), tostring(CS.quality), c.id, avg, (1 - (sum[c.id] or 0) / sum.d0) * 100, name))
            end
        end
        snowMessage("wx_snow.test.tour_done", { n = n, drop = n > 0 and math.floor(drop / n * 10) / 10 or 0,
            low = #low > 0 and table.concat(low, ", ") or "-" })
        return
    end
    local failed = {}
    for _, r in ipairs(results) do
        outputConsole(("[snowtest] %-6s %-32s indoor=%s shaders=%d flakes=%d diff=%.2f changed=%.3f"):format(
            r.ok and "OK" or "FAIL", tostring(r.name):sub(1, 32), tostring(r.indoor), r.shaders or 0, r.flakes or 0,
            r.meanDiff or 0, r.changed or 0))
        if not r.ok then failed[#failed + 1] = r.name end
    end
    writeReport("wx_snow_" .. kind .. ".json", results)
    snowMessage("wx_snow.test.indoor_done", { kind = kind, n = #results, failed = #failed,
        list = #failed > 0 and table.concat(failed, ", "):sub(1, 200) or "-" })
end

local function stop(message)
    TESTS.running, TESTS.co = false, nil
    capture.want = false
    restorePlace()
    if message then snowMessage(message) end
end

addEventHandler("onClientRender", root, function()
    if not TESTS.co then return end
    if waitCond then
        if not waitCond() and getTickCount() < waitUntil then return end
    elseif getTickCount() < waitUntil then
        return
    end
    local ok, err = coroutine.resume(TESTS.co)
    if not ok then
        outputDebugString("[wx_snow] snowtest: " .. tostring(err), 1)
        stop("wx_snow.test.failed")
    elseif coroutine.status(TESTS.co) == "dead" then
        stop(nil)
    end
end)

addEventHandler("onClientRender", root, function()
    if not TESTS.running then return end
    local sw = guiGetScreenSize()
    dxDrawRectangle(sw / 2 - 260, 60, 520, 30, tocolor(0, 0, 0, 160))
    dxDrawText("snowtest " .. tostring(TESTS.kind) .. ": " .. tostring(TESTS.progress or ""), sw / 2 - 250, 60,
        sw / 2 + 250, 90, tocolor(255, 255, 255), 1, "default-bold", "center", "center")
end)

SNOW_COMMANDS.test = function(a)
    if a.action == "stop" then
        if TESTS.running then stop("wx_snow.test.stopped") end
        return
    end
    if TESTS.running or BAKE.running then return snowMessage("wx_snow.test.busy") end
    if getPedOccupiedVehicle(localPlayer) then return snowMessage("wx_snow.bake.on_foot") end
    savePlace()
    TESTS.running, TESTS.kind, TESTS.progress = true, a.action, ""
    TESTS.co = coroutine.create(function()
        local results
        if a.action == "interiors" then
            results = runInteriors(type(a.list) == "table" and a.list or {})
        elseif a.action == "zones" then
            results = runZones()
        elseif a.action == "cost" then
            results = runCost()
        else
            results = runTour()
        end
        summary(a.action, results)
    end)
    snowMessage("wx_snow.test.started", { kind = a.action })
end
