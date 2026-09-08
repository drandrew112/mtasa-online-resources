--[[
    loadResources.lua
    ---------------------------------------------------------------------------
    A v_main indításakor lefut. Megkeresi az összes szerver-resource-t,
    kiolvassa a meta.xml-ekbol az <include> fuggosegeket, fuggosegi
    (topologiai) sorrendbe allitja oket - az include-ban kert resource-ok
    mindig elorebb kerulnek -, majd ebben a sorrendben elinditja azokat,
    amelyek meg nem futnak.

    Igy nem kell tobbe kezzel karbantartani az mtaserver.conf resource-listajat.

    A folyamat a v_main resource indulasakor (onResourceStart) kezdodik, es
    minden lepest a szerverkonzolba (outputServerLog) logol.
]]

-- Ezeket a resource-okat sosem inditjuk automatikusan.
local IGNORE = {
    [getResourceName(resource)] = true,   -- onmagunk (v_main)
    ["ai_autoplayer"]           = true,   -- [tiktok] - kezi inditas
    ["tiktok-live"]             = true,   -- [tiktok] - kezi inditas
}

local function log(msg)
    outputServerLog("[v_main:loadResources] " .. msg)
end

-- Egy resource meta.xml-jebol visszaadja az <include resource="..."> neveket.
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

-- Osszegyujti a resource-okat, feloldja a fuggosegeket, majd topologiai
-- sorrendbe rendezi oket. Visszaad: name->resource map + rendezett nevlista.
local function buildOrder()
    local resources = {}   -- name -> resource element
    local deps      = {}   -- name -> { fuggoseg-nev, ... }

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

    -- Determinisztikus kiindulas: nevek ABC-sorrendben.
    local names = {}
    for name in pairs(resources) do
        names[#names + 1] = name
    end
    table.sort(names)

    local order = {}
    local mark  = {}   -- nil = nincs latogatva, 1 = folyamatban, 2 = kesz

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
            log(("  started (%d/%d): %s"):format(started, #order, name))
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
