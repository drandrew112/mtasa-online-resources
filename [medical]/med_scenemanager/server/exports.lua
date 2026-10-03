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

-- getSceneList() -> summaries { { name, path, category, title, priority, center, interior, dimension, weight, enabled, peds, vehicles }, ... }
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

-- getCatalog() -> the editor's data tables, for tools that build scenes (claude-mcp medical module):
-- { anims, injuries, severities, state, stateOrder, stateResting, damage = { [id] = entry }, colors, pedSkins, defaultErm }
function getCatalog()
    local damage = {}
    for _, d in ipairs(MSM_DAMAGE) do
        local entry = {}
        Builder.damagePreset(entry, d.id)
        entry.label = d.label
        damage[d.id] = entry
    end
    return msmCopy({
        anims = MSM_ANIMS, injuries = MSM_INJURIES, severities = MSM_SEVERITY,
        state = MSM_STATE, stateOrder = MSM_STATE_ORDER, stateResting = MSM_STATE_RESTING,
        damage = damage, colors = MSM_COLORS, pedSkins = MSM.PED_SKINS, defaultErm = MSM.DEFAULT_ERM,
    })
end

-- saveSceneData(name, scene [, overwrite]) -> true | false, "exists" | error
-- Writes scenes/<Settlement>/[<category>/]<name>.json (normalized, editor format) and updates
-- the index. scene.category: "heartattack" | "mva" | "" (missing = taken from the name).
-- A scene that is open in the in-game editor is never overwritten.
function saveSceneData(name, scene, overwrite)
    name = tostring(name)
    if type(scene) ~= "table" then return false, "scene must be a table" end
    if Storage.exists(name) and not overwrite then return false, "exists" end
    if Editor and Editor.locks and Editor.locks[name] then return false, "Scene is open in the editor" end
    return Storage.save(name, scene)
end
