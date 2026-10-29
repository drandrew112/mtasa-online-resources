-- The placed objects of a match (job.objects, created and frozen by the server in core/server.lua).
-- Many creator catalog models are dynamic or breakable in GTA and some only draw from 30 m, so
-- while a match runs: every object in the match dimension is unbreakable, and the LOD distance of
-- the match's object models is raised to MIN_LOD (restored when the match is over).

local MIN_LOD = 170

local matchDimension = nil
local raisedLod = {}        -- model -> original LOD distance

local function restoreLod()
    for model, original in pairs(raisedLod) do engineSetModelLODDistance(model, original) end
    raisedLod = {}
end

local function raiseLod(models)
    restoreLod()
    for _, model in ipairs(type(models) == "table" and models or {}) do
        local current = engineGetModelLODDistance(model)
        if current and current < MIN_LOD and engineSetModelLODDistance(model, MIN_LOD) then
            raisedLod[model] = current
        end
    end
end

local function protect(object)
    if getElementType(object) == "object" and getElementDimension(object) == matchDimension then
        setObjectBreakable(object, false)
    end
end

addEventHandler("onClientElementStreamIn", root, function()
    if matchDimension then protect(source) end
end)

addEvent("jobmanager:matchStarted", true)
addEventHandler("jobmanager:matchStarted", resourceRoot, function(_, info)
    matchDimension = type(info) == "table" and info.dimension or nil
    raiseLod(type(info) == "table" and info.objectModels)
    -- objects that streamed in before this event (normally none: they are created right after it)
    if matchDimension then
        for _, object in ipairs(getElementsByType("object", root, true)) do protect(object) end
    end
end)

local function matchOver()
    matchDimension = nil
    restoreLod()
end
addEvent("jobmanager:matchEnded", true)
addEventHandler("jobmanager:matchEnded", resourceRoot, matchOver)
addEvent("jobmanager:matchLeft", true)
addEventHandler("jobmanager:matchLeft", resourceRoot, matchOver)
addEvent("jobmanager:matchQuietEnd", true)
addEventHandler("jobmanager:matchQuietEnd", resourceRoot, matchOver)
addEventHandler("onClientResourceStop", resourceRoot, restoreLod)
