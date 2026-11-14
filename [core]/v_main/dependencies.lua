--[[
    dependencies.lua
    ---------------------------------------------------------------------------
    Hand-maintained start-order list + client download-order audit.

    1) RESOURCE_DEPENDENCIES
       resource -> { resources that must be running BEFORE it starts }.
       Merged into loadResources.lua's topological sort on top of the
       <include> tags, so it also covers dependencies that are not includes
       (runtime exports.X calls, events a resource waits for, ...).

    2) Client download-order audit (auditClientOrder)
       On the client MTA starts resources in <download_priority_group> order
       (higher group first), NOT in include order. If a dependency has a lower
       group than the resource that needs it, the dependent starts first on the
       client and its exports.X:... calls at load time fail (this is what broke
       ui_browser: group 997 vs gov_tax 201 -> util.lua died on importVat, no
       BR table, no /browser command, the phone could not open it).
       The audit logs every such pair at v_main start with the group values
       that would fix it. It only reports - meta.xml files are never edited
       here (the GitHub updater would see them as local changes).
]]

RESOURCE_DEPENDENCIES = {
    -- ui_browser: util.lua imports the VAT lib of gov_tax, layout uses ui_core
    ui_browser = { "v_locals", "ui_core", "gov_tax" },
    gov_tax    = { "gov_core", "v_locals" },
    gov_core   = { "v_locals", "web_api" },
    -- ui_phone opens the browser app via exports.ui_browser:openBrowser()
    ui_phone   = { "ui_browser" },
}

local function log(msg)
    outputServerLog("[v_main:dependencies] " .. tostring(msg))
end

-- Reads what the audit needs from a resource's meta.xml.
-- Returns { group = number, client = bool, includes = { name, ... } } or nil.
local function readMeta(resName)
    local xml = xmlLoadFile(":" .. resName .. "/meta.xml")
    if not xml then return nil end

    local info = { group = 0, client = false, includes = {} }
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local tag = xmlNodeGetName(node)
        if tag == "download_priority_group" then
            info.group = tonumber(xmlNodeGetValue(node)) or 0
        elseif tag == "include" then
            local dep = xmlNodeGetAttribute(node, "resource")
            if dep and dep ~= "" then info.includes[#info.includes + 1] = dep end
        elseif tag == "script" then
            local t = xmlNodeGetAttribute(node, "type")
            if t == "client" or t == "shared" then info.client = true end
        end
    end
    xmlUnloadFile(xml)
    return info
end

-- Every dependency of `name`: its <include>s + RESOURCE_DEPENDENCIES entries.
local function allDeps(name, info)
    local seen, list = {}, {}
    local function add(dep)
        if dep ~= name and not seen[dep] then
            seen[dep] = true
            list[#list + 1] = dep
        end
    end
    for _, dep in ipairs(info and info.includes or {}) do add(dep) end
    for _, dep in ipairs(RESOURCE_DEPENDENCIES[name] or {}) do add(dep) end
    return list
end

--- Logs every client-side ordering problem. Returns the number of bad pairs.
function auditClientOrder()
    local metas = {}
    for _, res in ipairs(getResources()) do
        local name = getResourceName(res)
        if name then metas[name] = readMeta(name) end
    end

    -- Names listed in RESOURCE_DEPENDENCIES that do not exist on this server.
    for name, deps in pairs(RESOURCE_DEPENDENCIES) do
        if not metas[name] then log("NOTE: listed resource not found: " .. name) end
        for _, dep in ipairs(deps) do
            if not metas[dep] then
                log(("NOTE: '%s' lists a missing dependency: %s"):format(name, dep))
            end
        end
    end

    local bad = 0
    local names = {}
    for name in pairs(metas) do names[#names + 1] = name end
    table.sort(names)

    -- Suggested groups: raise each dependency to at least its dependents' group.
    local need = {}
    for name, m in pairs(metas) do need[name] = m.group end

    for _, name in ipairs(names) do
        local m = metas[name]
        if m and m.client then
            for _, dep in ipairs(allDeps(name, m)) do
                local d = metas[dep]
                if d and d.client and d.group < m.group then
                    bad = bad + 1
                    log(("WARNING: client order: '%s' (download_priority_group %d) starts before its dependency '%s' (%d)")
                        :format(name, m.group, dep, d.group))
                end
            end
        end
    end

    if bad > 0 then
        local changed = true
        while changed do
            changed = false
            for name, m in pairs(metas) do
                if m.client then
                    for _, dep in ipairs(allDeps(name, m)) do
                        local d = metas[dep]
                        if d and d.client and need[dep] < need[name] then
                            need[dep] = need[name]
                            changed = true
                        end
                    end
                end
            end
        end
        for _, name in ipairs(names) do
            if need[name] ~= metas[name].group then
                log(("  fix: set <download_priority_group> of '%s' to %d (now %d), or lower its dependents")
                    :format(name, need[name], metas[name].group))
            end
        end
    else
        log("Client download order OK.")
    end

    return bad
end
