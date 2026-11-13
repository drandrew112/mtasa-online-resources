-- wx_snow :: roof map (DESIGN.md 5)
--
-- data/roofmap.png: top-down 16 bit height of the highest surface per cell (R = high byte,
-- G = low byte), row j / column i = cell at minY + j*cell / minX + i*cell. Written by /snowbake.
-- A pixel of the world (ground shader) or a flake below `height - TOLERANCE` is under a roof.
-- Until a map is baked (data/roofmap.json cells = 0) nothing counts as covered, the camera
-- check falls back to a line of sight upwards.

ROOF = { texture = nil, pixels = nil, info = nil }

local function readInfo()
    if not fileExists(SNOW.ROOF.INFO) then return nil end
    local f = fileOpen(SNOW.ROOF.INFO, true)
    if not f then return nil end
    local data = fileRead(f, fileGetSize(f))
    fileClose(f)
    local info = fromJSON(data)
    if type(info) ~= "table" or (tonumber(info.cells) or 0) < 2 then return nil end
    return info
end

function ROOF.load()
    ROOF.unload()
    local info = readInfo()
    if not info then return false end
    local tex = dxCreateTexture(SNOW.ROOF.FILE, "argb", false, "clamp")
    if not tex then
        outputDebugString("[wx_snow] roof map texture could not be created", 2)
        return false, "texture"
    end
    local w, h = dxGetMaterialSize(tex)
    if w ~= info.cells or h ~= info.cells then
        outputDebugString(("[wx_snow] roof map size %dx%d does not match roofmap.json (%d)"):format(w, h, info.cells), 2)
        destroyElement(tex)
        return false
    end
    ROOF.texture, ROOF.info = tex, info
    ROOF.pixels = dxGetTexturePixels(tex)
    ROOF.cell = info.size / info.cells
    return true
end

function ROOF.unload()
    if isElement(ROOF.texture) then destroyElement(ROOF.texture) end
    ROOF.texture, ROOF.pixels, ROOF.info = nil, nil, nil
end

function ROOF.isLoaded() return ROOF.texture ~= nil end

-- top surface height of the cell at x, y; nil without a roof map / outside it
function ROOF.heightAt(x, y)
    local info = ROOF.info
    if not info or not ROOF.pixels then return nil end
    local i = math.floor((x - info.minX) / ROOF.cell)
    local j = math.floor((y - info.minY) / ROOF.cell)
    if i < 0 or j < 0 or i >= info.cells or j >= info.cells then return nil end
    local r, g = dxGetPixelColor(ROOF.pixels, i, j)
    if not r then return nil end
    return (r * 256 + g) / 65535 * (info.zMax - info.zMin) + info.zMin
end

-- roof map parameters of a shader (ground, flakes, layers)
function ROOF.apply(shader)
    local info = ROOF.info
    if not info then
        dxSetShaderValue(shader, "gRoofOn", 0)
        return
    end
    dxSetShaderValue(shader, "gRoofTex", ROOF.texture)
    dxSetShaderValue(shader, "gRoofRect", info.minX, info.minY, info.size, info.cells)
    dxSetShaderValue(shader, "gRoofZ", info.zMin, info.zMax, SNOW.ROOF.TOLERANCE)
    dxSetShaderValue(shader, "gRoofOn", 1)
end

-------------------------------------------------------------------------------- lane map
-- data/road/c_<cx>_<cy>.png (tools/build_roadmap.py, from GTA data/Paths): wheel tracks on the roads.
--
-- STREAMED: the three full images were 3 x 1536^2 texels (28 MB) in a 32 bit client that already ran out of
-- memory ("DxCreateTexture failed ... out of memory" after /restart wx_snow). The shader only reads the lane map
-- within SNOW.LOD.road[2] m of the camera, so the client holds a small WINDOW x WINDOW cell window (64 KB per
-- layer texture) and refills it from the chunk files (256 cells each, the three layers stacked) when the camera
-- gets closer than MARGIN cells to the window edge. The fill is spread over frames (ROWS_PER_FRAME rows each).
-- The shader is the same: gRoadRect describes the window instead of the whole map.
-- Format 4 (junctions): the chunks have a fourth layer (junction layer: path list offset / length + junction
-- mask), windowed like the others; the path table data/road/jpaths.png and the lists data/road/jlists.png are
-- small (a few hundred KB) and loaded once for the whole map.

ROAD = { textures = nil, info = nil, ready = false, cache = {}, order = {}, job = nil, win = nil, failedAt = 0,
         jpaths = nil, jlists = nil }

local RC = SNOW.ROAD

function ROAD.unload()
    for _, t in ipairs(ROAD.textures or {}) do if isElement(t) then destroyElement(t) end end
    if isElement(ROAD.jpaths) then destroyElement(ROAD.jpaths) end
    if isElement(ROAD.jlists) then destroyElement(ROAD.jlists) end
    ROAD.jpaths, ROAD.jlists = nil, nil
    ROAD.textures, ROAD.info, ROAD.ready, ROAD.job, ROAD.win = nil, nil, false, nil, nil
    ROAD.cache, ROAD.order = {}, {}
end

function ROAD.load()
    ROAD.unload()
    if not fileExists(RC.INFO) then
        outputDebugString("[wx_snow] lane map: " .. RC.INFO .. " is missing on the client", 2)
        return false
    end
    local f = fileOpen(RC.INFO, true)
    if not f then
        outputDebugString("[wx_snow] lane map: " .. RC.INFO .. " could not be opened", 2)
        return false
    end
    local info = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    if type(info) ~= "table" or (tonumber(info.cells) or 0) < 2 then
        outputDebugString("[wx_snow] lane map: " .. RC.INFO .. " unreadable (" .. type(info) .. ")", 2)
        return false
    end
    if info.format ~= 4 or not info.chunk then
        outputDebugString("[wx_snow] data/roadmap.json is not format 4 (junction layer), run tools/build_roadmap.py", 2)
        return false
    end
    info.layers = tonumber(info.layers) or 4
    info.have = {}
    for _, key in ipairs(info.chunks or {}) do info.have[key] = true end
    local texs = {}
    for i = 1, info.layers do
        texs[i] = dxCreateTexture(RC.WINDOW, RC.WINDOW, "argb", "clamp")
        if not texs[i] then
            for _, t in ipairs(texs) do if isElement(t) then destroyElement(t) end end
            outputDebugString("[wx_snow] lane map window texture could not be created", 2)
            return false, "texture"
        end
    end
    ROAD.textures, ROAD.info = texs, info
    outputDebugString(("[wx_snow] lane map info loaded: %d chunks, window %d cells"):format(#(info.chunks or {}), RC.WINDOW))
    ROAD.loadJunctions()
    return true
end

-- the junction path table + lists (whole map, once); without them the shader keeps the junction mask only
function ROAD.loadJunctions()
    local info = ROAD.info
    local jp = dxCreateTexture(RC.DIR .. "jpaths.png", "argb", false, "clamp")
    local jl = jp and dxCreateTexture(RC.DIR .. "jlists.png", "argb", false, "clamp")
    if not jp or not jl then
        if isElement(jp) then destroyElement(jp) end
        outputDebugString("[wx_snow] junction tables could not be created (files missing on the client or memory)", 2)
        return false
    end
    local pw, ph = dxGetMaterialSize(jp)
    local lw, lh = dxGetMaterialSize(jl)
    local ps, ls = info.jPathSize or {}, info.jListSize or {}
    if pw ~= ps[1] or ph ~= ps[2] or lw ~= ls[1] or lh ~= ls[2] then
        outputDebugString(("[wx_snow] junction tables %dx%d / %dx%d do not match roadmap.json"):format(pw, ph, lw, lh), 2)
        destroyElement(jp)
        destroyElement(jl)
        return false
    end
    ROAD.jpaths, ROAD.jlists = jp, jl
    outputDebugString(("[wx_snow] junction tables loaded: %d paths, jpaths %dx%d (%d KB), jlists %dx%d (%d KB)"):format(
        tonumber(info.jPaths) or 0, pw, ph, math.floor(pw * ph * 4 / 1024), lw, lh, math.floor(lw * lh * 4 / 1024)))
    return true
end

-- the window is usable (filled at least once)
function ROAD.isLoaded() return ROAD.ready end

local function chunkPixels(cx, cy)
    local info = ROAD.info
    local key = cx .. "_" .. cy
    if not info.have[key] then return false end               -- empty chunk
    local c = ROAD.cache[key]
    if c then return c end
    local tex = dxCreateTexture(RC.DIR .. "c_" .. key .. ".png", "argb", false, "clamp")
    if not tex then
        ROAD.why = "chunk texture c_" .. key .. " could not be created (file missing on the client or memory)"
        return nil                                            -- try again later
    end
    local px = dxGetTexturePixels(tex)
    destroyElement(tex)
    if not px then
        ROAD.why = "pixels of chunk c_" .. key .. " could not be read"
        return nil
    end
    ROAD.cache[key] = px
    ROAD.order[#ROAD.order + 1] = key
    while #ROAD.order > RC.CACHE do
        ROAD.cache[table.remove(ROAD.order, 1)] = nil
    end
    return px
end

-- fills the window with its origin at cell (ox, oy); a coroutine, resumed a few rows per frame
-- dxGetTexturePixels of the three window textures shared ONE buffer in the client (all three layers ended up as
-- the last one = the height layer, so the shader never saw a lane): the cells are collected in Lua tables first
-- and every layer is read / written back on its own.
local function fillJob(ox, oy)
    local info, W, CH = ROAD.info, RC.WINDOW, ROAD.info.chunk
    local cells, L = info.cells, info.layers
    local data = {}
    for l = 1, L do data[l] = {} end
    local rows = 0
    for j = 0, W - 1 do
        local gj = oy + j
        for i = 0, W - 1 do
            local gi = ox + i
            local px, li, lj = false, 0, 0
            if gi >= 0 and gj >= 0 and gi < cells and gj < cells then
                local cx, cy = math.floor(gi / CH), math.floor(gj / CH)
                px = chunkPixels(cx, cy)
                if px == nil then return false end
                li, lj = gi - cx * CH, gj - cy * CH
            end
            local o = (j * W + i) * 4
            for l = 1, L do
                local t = data[l]
                if px then
                    local r, g, b, a = dxGetPixelColor(px, li, lj + (l - 1) * CH)
                    t[o + 1], t[o + 2], t[o + 3], t[o + 4] = r or 0, g or 0, b or 0, a or 0
                else
                    t[o + 1], t[o + 2], t[o + 3], t[o + 4] = 0, 0, 0, 0
                end
            end
        end
        rows = rows + 1
        if rows >= RC.ROWS_PER_FRAME then
            rows = 0
            coroutine.yield()
        end
    end
    for l = 1, L do
        local pix = dxGetTexturePixels(ROAD.textures[l])
        if not pix then
            ROAD.why = "window texture pixels could not be read"
            return false
        end
        local t = data[l]
        for j = 0, W - 1 do
            for i = 0, W - 1 do
                local o = (j * W + i) * 4
                dxSetPixelColor(pix, i, j, t[o + 1], t[o + 2], t[o + 3], t[o + 4])
            end
        end
        dxSetTexturePixels(ROAD.textures[l], pix)
    end
    ROAD.win = { ox = ox, oy = oy }
    ROAD.ready = true
    outputDebugString(("[wx_snow] lane map window filled at cell %d,%d"):format(ox, oy))
    return true
end

local function startFill(ox, oy)
    ROAD.job = coroutine.create(function() return fillJob(ox, oy) end)
end

-- window follows the camera
local function follow()
    if not ROAD.textures or ROAD.job or getTickCount() < ROAD.failedAt then return end
    local info = ROAD.info
    local cell = info.size / info.cells
    local cx, cy = getCameraMatrix()
    local ci, cj = math.floor((cx - info.minX) / cell), math.floor((cy - info.minY) / cell)
    local w = ROAD.win
    local W, M = RC.WINDOW, RC.MARGIN
    if w and ci >= w.ox + M and ci < w.ox + W - M and cj >= w.oy + M and cj < w.oy + W - M then return end
    local snap = RC.SNAP
    startFill(math.floor((ci - W / 2) / snap) * snap, math.floor((cj - W / 2) / snap) * snap)
end

addEventHandler("onClientRender", root, function()
    if not ROAD.job then return end
    local ok, res = coroutine.resume(ROAD.job)
    if not ok then
        outputDebugString("[wx_snow] lane map fill: " .. tostring(res), 1)
        ROAD.job, ROAD.failedAt = nil, getTickCount() + 5000
    elseif coroutine.status(ROAD.job) == "dead" then
        ROAD.job = nil
        if res then
            snowChanged("roadmap")
        else
            -- a chunk texture could not be created: memory, try again in a moment
            ROAD.failedAt = getTickCount() + 2500
            ROAD.fails = (ROAD.fails or 0) + 1
            if ROAD.fails <= 5 then
                outputDebugString("[wx_snow] lane map fill failed: " .. tostring(ROAD.why), 2)
            end
        end
    end
end)

function ROAD.apply(shader)
    local info, w = ROAD.info, ROAD.win
    if not info or not w or not ROAD.ready then
        dxSetShaderValue(shader, "gRoadOn", 0)
        dxSetShaderValue(shader, "gJOn", 0)
        return
    end
    local cell = info.size / info.cells
    dxSetShaderValue(shader, "gRoadTex", ROAD.textures[1])
    dxSetShaderValue(shader, "gRoad2Tex", ROAD.textures[2])
    dxSetShaderValue(shader, "gRoadZTex", ROAD.textures[3])
    dxSetShaderValue(shader, "gRoadRect", info.minX + w.ox * cell, info.minY + w.oy * cell, RC.WINDOW * cell, RC.WINDOW)
    dxSetShaderValue(shader, "gRoadDRange", info.dRange or 32)
    dxSetShaderValue(shader, "gRoadZ", info.zMin or -60, info.zMax or 1000)
    dxSetShaderValue(shader, "gRoadJTex", ROAD.textures[4])
    dxSetShaderValue(shader, "gRoadMin", info.minX, info.minY)
    if ROAD.jpaths then
        local ps, ls = info.jPathSize, info.jListSize
        dxSetShaderValue(shader, "gJPathTex", ROAD.jpaths)
        dxSetShaderValue(shader, "gJListTex", ROAD.jlists)
        dxSetShaderValue(shader, "gJSize", ps[1], ps[2], ls[1], ls[2])
        dxSetShaderValue(shader, "gJRel", info.jRel or 64)
        dxSetShaderValue(shader, "gJOn", 1)
    else
        dxSetShaderValue(shader, "gJOn", 0)
    end
    dxSetShaderValue(shader, "gRoadOn", 1)
end

local RETRY_MS, RETRIES = 2500, 8

local function loadRoof(try)
    local ok, why = ROOF.load()
    if ok then
        outputDebugString(("[wx_snow] roof map %dx%d loaded (%d m cells)"):format(ROOF.info.cells, ROOF.info.cells, ROOF.cell))
        return snowChanged("roofmap")
    end
    if why == "texture" and try < RETRIES then
        setTimer(function() loadRoof(try + 1) end, RETRY_MS, 1)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local ok = ROAD.load()
    if ok then setTimer(follow, 400, 0) end
    loadRoof(1)
end)

-- give the memory back at once (restart wx_snow)
addEventHandler("onClientResourceStop", resourceRoot, function()
    ROAD.unload()
    ROOF.unload()
end)
