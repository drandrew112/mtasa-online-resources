-- ai_llm / server/contexts.lua
-- Named contexts: longer texts a resource registers once (help docs, code lists, rules) and the
-- requests refer to by name (options.contexts = { "name", ... }). Names are global; by convention
-- "<resource>.<name>". A context belongs to the resource that set it and is removed when it stops.

AI = AI or {}
AI.contexts = {}   -- [name] = { text, owner = resource name, updated = timestamp }

local function validName(name)
    return type(name) == "string" and #name >= 1 and #name <= 64 and name:match("^[%w_%.%-:]+$") ~= nil
end

function AI.getContextText(name)
    local c = AI.contexts[name]
    return c and c.text or nil
end

-- setContext(name, text) -> true | false, error
function setContext(name, text)
    if not validName(name) then return false, "invalid context name" end
    if type(text) ~= "string" then return false, "context text must be a string" end
    if not AI.contexts[name] then
        local n = 0
        for _ in pairs(AI.contexts) do n = n + 1 end
        if n >= AI.CONFIG.MAX_CONTEXTS then return false, "too many contexts" end
    end
    if #text > AI.CONFIG.MAX_NAMED_CONTEXT_LENGTH then text = text:sub(1, AI.CONFIG.MAX_NAMED_CONTEXT_LENGTH) end
    AI.contexts[name] = {
        text = text,
        owner = sourceResource and getResourceName(sourceResource) or getResourceName(resource),
        updated = getRealTime().timestamp,
    }
    return true
end

function getContext(name)
    return AI.getContextText(name) or false
end

function removeContext(name)
    if not AI.contexts[name] then return false end
    AI.contexts[name] = nil
    return true
end

-- -> { { name, owner, length, updated }, ... }
function getContexts()
    local list = {}
    for name, c in pairs(AI.contexts) do
        list[#list + 1] = { name = name, owner = c.owner, length = #c.text, updated = c.updated }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

addEventHandler("onResourceStop", root, function(res)
    if res == resource then return end
    local owner = getResourceName(res)
    for name, c in pairs(AI.contexts) do
        if c.owner == owner then AI.contexts[name] = nil end
    end
end)
