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
