--[[
    loadResources.lua
    ---------------------------------------------------------------------------
    Runs when v_main starts. Collects every server resource, reads the
    <include> dependencies from their meta.xml files, sorts them into
    dependency (topological) order - resources requested via <include> always
    come first - then starts, in that order, the ones that are not running yet.

    This removes the need to hand-maintain the resource list in mtaserver.conf.

    The process is kicked off on v_main's onResourceStart and every step is
    logged to the server console (outputServerLog).
]]

-- These resources are never started automatically.
local IGNORE = {
    [getResourceName(resource)] = true,   -- ourselves (v_main)
    ["ai_autoplayer"]           = true,   -- [tiktok] - started manually
    ["tiktok-live"]             = true,   -- [tiktok] - started manually
}

local function log(msg)
    outputServerLog("[v_main:loadResources] " .. msg)
end

-- Returns the <include resource="..."> names from a resource's meta.xml.
local function getIncludes(resName)
    local includes = {}

    local xml = xmlLoadFile(":" .. resName .. "/meta.xml")
    if not xml then
        log("WARNING: could not read meta.xml: " .. resName)
        return includes
    end

    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetName(node) == "include" then
            local dep = xmlNodeGetAttribute(node, "resource")
            if dep and dep ~= "" then
                includes[#includes + 1] = dep
            end
        end
    end

    xmlUnloadFile(xml)
    return includes
end

-- Collects the resources, resolves their dependencies, then sorts them into
-- topological order. Returns: name->resource map + ordered list of names.
local function buildOrder()
    local resources = {}   -- name -> resource element
    local deps      = {}   -- name -> { dependency-name, ... }

    for _, res in ipairs(getResources()) do
        local name = getResourceName(res)
        if name and not IGNORE[name] then
            resources[name] = res
        end
    end

    for name in pairs(resources) do
        local list = {}
        for _, dep in ipairs(getIncludes(name)) do
            if resources[dep] then          -- only existing, non-ignored dependency
                list[#list + 1] = dep
            elseif not IGNORE[dep] then
                log("WARNING: '" .. name .. "' includes a missing resource: " .. dep)
            end
        end
        deps[name] = list
    end

    -- Deterministic starting point: names in alphabetical order.
    local names = {}
    for name in pairs(resources) do
        names[#names + 1] = name
    end
    table.sort(names)

    local order = {}
    local mark  = {}   -- nil = not visited, 1 = in progress, 2 = done

    local function visit(name)
        if mark[name] == 2 then return end
        if mark[name] == 1 then
            log("WARNING: circular include dependency at: " .. name)
            return
        end

        mark[name] = 1
        for _, dep in ipairs(deps[name]) do
            visit(dep)
        end
        mark[name] = 2

        order[#order + 1] = name
    end

    for _, name in ipairs(names) do
        visit(name)
    end

    return resources, order
end

local function startAll()
    log("Resource loading started...")

    local resources, order = buildOrder()
    log(("Dependency order ready: %d resources in the list."):format(#order))

    local started, alreadyRunning, failed = 0, 0, 0

    for _, name in ipairs(order) do
        local res   = resources[name]
        local state = getResourceState(res)

        if state == "running" then
            alreadyRunning = alreadyRunning + 1
        elseif startResource(res, true) then
            started = started + 1
        else
            failed = failed + 1
            log("  FAILED to start: " .. name)
        end
    end

    log(("Done. Started: %d, already running: %d, failed: %d.")
        :format(started, alreadyRunning, failed))
end

addEventHandler("onResourceStart", resourceRoot, function()
    startAll()
end)
