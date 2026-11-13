-- wx_snow :: debug state (exports.wx_snow:getSnowDebugState(), /snow, /snowtest)

function getSnowDebugState()
    local lvl, cov = snowCurrent()
    local n = 0
    for _ in pairs(GROUND.shaders) do n = n + 1 end
    return {
        level = lvl, coverage = cov, serverLevel = CS.server.level, preview = CS.preview ~= nil,
        quality = CS.quality, debug = CS.debug,
        indoor = CS.indoor, indoorWhy = CS.indoorWhy, covered = CS.covered,
        nearBoxes = #CS.nearBoxes, zones = #CS.zones,
        groundShaders = n, groundAttached = GROUND.attached, groundActive = GROUND.attached and GROUND.active or false,
        groundError = GROUND.error or false, laneMap = ROAD.isLoaded(), interior = CS.interior,
        groundTechnique = GROUND.technique or false, grass = GROUND.grassMode,
        roofMap = ROOF.isLoaded(), roofHere = ROOF.heightAt and ROOF.heightAt(getCameraMatrix()) or false,
        precip = PRECIP.intensity, flakesDrawn = PRECIP.drawn, precipError = PRECIP.error or false,
        fog = ENV.fogApplied or false, grade = ENV.grade ~= nil, windVolume = ENV.volume,
        baking = BAKE.running,
    }
end

-- lane map window sample at a world position (exports.wx_snow:getSnowRoadSample(x, y)): the four layer pixels
-- actually in the window textures + the window rect, to compare with data/road/c_*.png
local function roadSample(x, y)
    local info, w = ROAD.info, ROAD.win
    if not info or not w or not ROAD.textures then return false end
    local cell = info.size / info.cells
    local gi, gj = math.floor((x - info.minX) / cell), math.floor((y - info.minY) / cell)
    local i, j = gi - w.ox, gj - w.oy
    local W = SNOW.ROAD.WINDOW
    if i < 0 or j < 0 or i >= W or j >= W then return { outside = true, win = { w.ox, w.oy }, cell = { gi, gj } } end
    local out = { cell = { gi, gj }, win = { w.ox, w.oy }, local_ = { i, j } }
    for l = 1, #ROAD.textures do
        local px = dxGetTexturePixels(ROAD.textures[l])
        local r, g, b, a = dxGetPixelColor(px, i, j)
        out[l] = { r, g, b, a }
    end
    return out
end

function getSnowRoadSample(x, y)
    local ok, res = pcall(roadSample, x, y)
    if ok then return res end
    return { err = tostring(res) }
end
