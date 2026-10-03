-- Stable references for MTA elements.
--
-- Workspace entities are referred to by their semantic id (tmp_vehicle_001).
-- Any other element the API reports (players, foreign vehicles, ...) gets an
-- ephemeral reference "el_<type>_<n>" that stays valid until the element is
-- destroyed or the bridge restarts. Raw element handles are never exposed.

Refs = { byElement = {}, byRef = {}, seq = 0 }

function Refs.of(element)
    if not isElement(element) then return nil end
    local entity = Registry and Registry.byElement[element]
    if entity then return entity.id end
    local ref = Refs.byElement[element]
    if not ref then
        Refs.seq = Refs.seq + 1
        local t = getElementType(element)
        ref = "el_" .. t .. "_" .. Refs.seq
        Refs.byElement[element] = ref
        Refs.byRef[ref] = element
    end
    return ref
end

-- id / ref / player name -> element, entity (or nil)
function Refs.resolve(id)
    if type(id) ~= "string" then return nil end
    local entity = Registry and Registry.entities[id]
    if entity then
        return isElement(entity.element) and entity.element or nil, entity
    end
    local el = Refs.byRef[id]
    if el and isElement(el) then return el, Registry and Registry.byElement[el] end
    if id == "probe" or id == "player" then
        local p = Probe.get()
        return p, nil
    end
    local p = getPlayerFromName(id)
    if p then return p, nil end
    return nil
end

-- like resolve but throws ENTITY_NOT_FOUND
function Refs.require(id, what)
    local el, entity = Refs.resolve(id)
    if not el then
        if entity then
            fail("ENTITY_MISSING", "Entity '" .. tostring(id) .. "' exists in the registry but its MTA element is gone (" .. tostring(entity.lostReason or "destroyed") .. ").",
                { entity = id, retryable = false, suggestion = "Delete it with delete_entity and spawn it again." })
        end
        fail("ENTITY_NOT_FOUND", "No entity or element with id '" .. tostring(id) .. "'" .. (what and (" (" .. what .. ")") or "") .. ".",
            { entity = id, retryable = false, suggestion = "List entities with inspect_workspace or inspect_area; element refs (el_*) expire when the bridge restarts." })
    end
    return el, entity
end

addEventHandler("onElementDestroy", root, function()
    local ref = Refs.byElement[source]
    if ref then
        Refs.byElement[source] = nil
        Refs.byRef[ref] = nil
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local ref = Refs.byElement[source]
    if ref then
        Refs.byElement[source] = nil
        Refs.byRef[ref] = nil
    end
end)
