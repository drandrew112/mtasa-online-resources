-- Public API for other resources (see README.md).

-- spawnScene(name) -> instanceId | false, error   (works without free units)
-- A second return value is a warning, e.g. when no ERM task could be created.
function spawnScene(name)
    local source = sourceResource and getResourceName(sourceResource) or "script"
    return Live.spawn(tostring(name), "export:" .. source)
end

-- removeScene(instanceId) -> bool   (closes the ERM task if it is still open)
function removeScene(instanceId)
    return Live.remove(tonumber(instanceId), "removed by export")
end

-- getActiveScenes() -> { { id, name, taskId, source, center, createdAt, closed, peds, vehicles }, ... }
function getActiveScenes()
    local out = {}
    for _, scene in pairs(Live.scenes) do out[#out + 1] = Live.public(scene) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- getSceneList() -> summaries { { name, title, priority, center, interior, dimension, weight, enabled, peds, vehicles }, ... }
function getSceneList()
    return msmCopy(Storage.list())
end

-- getSceneData(name) -> the full scene table read from its file | false
function getSceneData(name)
    return Storage.load(tostring(name)) or false
end

function getAutoGenerate()
    return Auto.enabled
end

-- setAutoGenerate(enabled [, by]) -> true
function setAutoGenerate(on, by)
    return Auto.setEnabled(on, by or (sourceResource and getResourceName(sourceResource)))
end
