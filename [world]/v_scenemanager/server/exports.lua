-- Public API for other resources (see README.md).

-- spawnScene(name) -> instanceId | false, error   (works without free units: every needed agency gets its task)
-- A second return value is a warning, e.g. when a task could not be created.
function spawnScene(name)
    local source = sourceResource and getResourceName(sourceResource) or "script"
    local id, err = Live.spawn(tostring(name), "export:" .. source)
    return id, err and tostring(err) or nil
end

-- removeScene(instanceId) -> bool   (closes the open tasks)
function removeScene(instanceId)
    return Live.remove(tonumber(instanceId), "removed by export")
end

-- getSceneAt(x, y, z [, radius]) -> instanceId, sceneName, ermTaskId | false, policeCallId | false
-- The open scene (some task not closed yet) within radius (default VSM.CALL_RADIUS)
-- of the point - its centre, peds or vehicles. ui_phone refuses an emergency call there.
function getSceneAt(x, y, z, radius)
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if not x or not y then return false end
    local scene = Live.sceneAt(x, y, z, tonumber(radius) or VSM.CALL_RADIUS)
    if not scene then return false end
    return scene.id, scene.name, scene.tasks.ems and scene.tasks.ems.id or false, scene.tasks.pd and scene.tasks.pd.id or false
end

-- getActiveScenes() -> { { id, name, taskId, tasks = { ems = { id, closed }, pd = ... }, late, source, center,
--                          createdAt, closed, peds, vehicles, patients, safety }, ... }
function getActiveScenes()
    local out = {}
    for _, scene in pairs(Live.scenes) do out[#out + 1] = Live.public(scene) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- getSceneList() -> summaries (see Storage.summary)
function getSceneList()
    return vsmCopy(Storage.list())
end

-- getSceneData(name) -> the full scene table read from its file | false
function getSceneData(name)
    return Storage.load(tostring(name)) or false
end

-- validateSceneData(scene) -> { { level, key, params, text }, ... } (text = English)
function validateSceneData(scene)
    local out = {}
    for _, i in ipairs(Storage.validate(Storage.normalize(scene, scene and scene.name))) do
        out[#out + 1] = { level = i.level, key = i.key, params = i.params, text = tostring(L.msg(i.key, i.params)) }
    end
    return out
end

function getAutoGenerate()
    return Auto.enabled
end

-- setAutoGenerate(enabled [, by]) -> true
function setAutoGenerate(on, by)
    return Auto.setEnabled(on, by or (sourceResource and getResourceName(sourceResource)))
end

-- getCatalog() -> the editor's data tables, for tools that build scenes (claude-mcp medical module):
-- { anims, injuries, severities, state, stateOrder, stateResting, damage = { [id] = entry }, colors, pedSkins,
--   roles, drugs, agencies, defaultAgency }
function getCatalog()
    local damage = {}
    for _, d in ipairs(VSM_DAMAGE) do
        local entry = {}
        Builder.damagePreset(entry, d.id)
        entry.label = d.label
        damage[d.id] = entry
    end
    return vsmCopy({
        anims = VSM_ANIMS, injuries = VSM_INJURIES, severities = VSM_SEVERITY,
        state = VSM_STATE, stateOrder = VSM_STATE_ORDER, stateResting = VSM_STATE_RESTING,
        damage = damage, colors = VSM_COLORS, pedSkins = VSM.PED_SKINS,
        roles = VSM_ROLES, drugs = VSM_DRUGS, agencies = VSM.AGENCY_ORDER, langs = VSM.LANGS,
        defaultAgency = { need = 2, priority = VSM.DEFAULT_PRIORITY, caller = VSM.DEFAULT_CALLER },
        -- format 1 callers (claude-mcp) still send "erm": it becomes agencies.ems
        defaultErm = { caller = VSM.DEFAULT_CALLER, priority = VSM.DEFAULT_PRIORITY, locales = { en = { title = "", description = "" } } },
    })
end

-- saveSceneData(name, scene [, overwrite]) -> true, file | false, "exists" | error
-- Writes scenes/<Settlement>/[<category>/]<name>.json (normalized to format 2, editor format) and updates
-- the index. A scene that is open in the in-game editor is never overwritten.
function saveSceneData(name, scene, overwrite)
    name = tostring(name)
    if type(scene) ~= "table" then return false, "scene must be a table" end
    if Storage.exists(name) and not overwrite then return false, "exists" end
    if Editor and Editor.locks and Editor.locks[name] then return false, "Scene is open in the editor" end
    local ok, res = Storage.save(name, scene)
    return ok, tostring(res)
end

-- getSceneIssues([status]) -> { issue, ... } newest first (status "open" | "resolved" | nil = all)
function getSceneIssues(status)
    return vsmCopy(Issues.query(status))
end
