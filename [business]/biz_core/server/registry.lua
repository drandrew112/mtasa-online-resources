-- biz_core / server/registry.lua
-- Public registry of every active organization (all instances), re-read every
-- BIZ.REGISTRY_REFRESH_MS. The website's Registry / Top organizations pages
-- and the admin list read this cache, so their exports answer synchronously.
-- Companies loaded on this instance show their live value.

REG = { list = {}, byId = {}, nameKeys = {}, loadedAt = 0 }

local int = DB.int

function REG.refresh()
    if not DB.ready then return end
    DB.query(function(rows)
        if not rows then return end
        local list, byId, keys = {}, {}, {}
        for _, r in ipairs(rows) do
            local e = {
                id = int(r.id), name = tostring(r.name), founderAccount = tostring(r.founder_account),
                founder = (r.display_name and r.display_name ~= "") and tostring(r.display_name) or tostring(r.founder_account),
                value = int(r.value_cache), createdAt = int(r.created_at), hqProperty = r.hq_property and tostring(r.hq_property) or nil,
                properties = {},
            }
            for pid in tostring(r.props or ""):gmatch("[^,]+") do e.properties[#e.properties + 1] = pid end
            list[#list + 1] = e
            byId[e.id] = e
            keys[e.name:lower()] = e.id
        end
        REG.list, REG.byId, REG.nameKeys, REG.loadedAt = list, byId, keys, getTickCount()
    end, [[SELECT c.id, c.name, c.founder_account, c.value_cache, c.created_at, a.display_name,
              (SELECT u.property_id FROM biz_units u WHERE u.id = c.hq_unit_id) AS hq_property,
              (SELECT GROUP_CONCAT(u2.property_id) FROM biz_units u2 WHERE u2.company_id = c.id) AS props
           FROM biz_companies c LEFT JOIN accounts a ON a.account_name = c.founder_account
           WHERE c.status = 'active']])
end

--- registry entry with live data where the company is loaded here
local function entry(e)
    local c = CO.byId[e.id]
    local out = {
        id = e.id, name = c and c.name or e.name, founder = e.founder, value = c and c.valueCache or e.value,
        createdAt = e.createdAt, hq = nil, hqCity = nil, activities = {},
    }
    local props = e.properties
    local hq = e.hqProperty
    if c then
        props = {}
        for _, u in pairs(c.units) do props[#props + 1] = u.propertyId end
        hq = c.units[c.hqUnit] and c.units[c.hqUnit].propertyId or hq
    end
    if hq then
        out.hq = BIZ.propertyName(hq)
        local p = BIZ.property(hq)
        local b = p and BIZ.BUILDINGS[p.building]
        out.hqCity = b and b.city or nil
    end
    local seen = {}
    for _, pid in ipairs(props) do
        local p = BIZ.property(pid)
        if p and p.activity and not seen[p.activity] then
            seen[p.activity] = true
            out.activities[#out.activities + 1] = p.activity
        end
    end
    table.sort(out.activities)
    return out
end

--- name taken by an active company (registry cache + loaded companies)
function REG.nameTaken(name, exceptId)
    local key = tostring(name):lower()
    local id = REG.nameKeys[key]
    if id and id ~= exceptId then return true end
    for _, c in pairs(CO.byId) do
        if c.id ~= exceptId and c.name:lower() == key then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

--- search by organization or founder name; sorted by name
function getRegistry(query, limit)
    query = tostring(query or ""):lower()
    limit = math.min(math.max(tonumber(limit) or 100, 1), 500)
    local out = {}
    for _, e in ipairs(REG.list) do
        if query == "" or e.name:lower():find(query, 1, true) or e.founder:lower():find(query, 1, true) then
            out[#out + 1] = entry(e)
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    while #out > limit do table.remove(out) end
    return out
end

--- by company value, highest first
function getTopList(limit)
    limit = math.min(math.max(tonumber(limit) or 25, 1), 100)
    local out = {}
    for _, e in ipairs(REG.list) do out[#out + 1] = entry(e) end
    table.sort(out, function(a, b) return a.value > b.value end)
    while #out > limit do table.remove(out) end
    for i, e in ipairs(out) do e.rank = i end
    return out
end

--- active organization founded by an account (registry cache / loaded) or false
function getCompanyOfAccount(account)
    if type(account) ~= "string" then return false end
    local key = account:lower()
    local c = CO.byAccount[key]
    if c then
        local n = 0
        for _ in pairs(c.units) do n = n + 1 end
        return { id = c.id, name = c.name, value = c.valueCache, properties = n, online = isElement(c.founder) }
    end
    for _, e in ipairs(REG.list) do
        if e.founderAccount:lower() == key then
            return { id = e.id, name = e.name, value = e.value, properties = #e.properties, online = false }
        end
    end
    return false
end

function getRegistryEntry(companyId)
    local e = REG.byId[tonumber(companyId)]
    return e and entry(e) or false
end
