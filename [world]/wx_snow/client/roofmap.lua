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
        return false
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
-- data/roadmap.png (tools/build_roadmap.py, from GTA data/Paths): wheel tracks on the roads

ROAD = { texture = nil, info = nil }

function ROAD.load()
    if not fileExists(SNOW.ROAD.INFO) then return false end
    local f = fileOpen(SNOW.ROAD.INFO, true)
    if not f then return false end
    local info = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    if type(info) ~= "table" or (tonumber(info.cells) or 0) < 2 then return false end
    if info.format ~= 3 then
        outputDebugString("[wx_snow] data/roadmap*.png is an old format, run tools/build_roadmap.py", 2)
        return false
    end
    -- layer 1, layer 2 (other height: overpasses), road heights
    local texs = {}
    for i, file in ipairs(SNOW.ROAD.FILES) do
        texs[i] = dxCreateTexture(file, "argb", false, "clamp")
        if not texs[i] then
            outputDebugString("[wx_snow] lane map texture could not be created: " .. file, 2)
            for _, t in ipairs(texs) do if isElement(t) then destroyElement(t) end end
            return false
        end
    end
    ROAD.textures, ROAD.texture, ROAD.info = texs, texs[1], info
    return true
end

function ROAD.isLoaded() return ROAD.texture ~= nil end

function ROAD.apply(shader)
    local info = ROAD.info
    if not info then
        dxSetShaderValue(shader, "gRoadOn", 0)
        return
    end
    dxSetShaderValue(shader, "gRoadTex", ROAD.textures[1])
    dxSetShaderValue(shader, "gRoad2Tex", ROAD.textures[2])
    dxSetShaderValue(shader, "gRoadZTex", ROAD.textures[3])
    dxSetShaderValue(shader, "gRoadRect", info.minX, info.minY, info.size, info.cells)
    dxSetShaderValue(shader, "gRoadDRange", info.dRange or 32)
    dxSetShaderValue(shader, "gRoadZ", info.zMin or -60, info.zMax or 1000)
    dxSetShaderValue(shader, "gRoadOn", 1)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    if ROAD.load() then snowChanged("roadmap") end
    if ROOF.load() then
        outputDebugString(("[wx_snow] roof map %dx%d loaded (%d m cells)"):format(ROOF.info.cells, ROOF.info.cells, ROOF.cell))
        snowChanged("roofmap")
    end
end)
