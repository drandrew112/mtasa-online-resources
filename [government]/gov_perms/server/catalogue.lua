-- gov_perms / server/catalogue.lua
-- The catalogue: every right that exists (DESIGN.md 3.1). The modules declare it in GOV.module
-- (perms = static keys, families = patterns with one "*" filled with the targets the module
-- reports through GOV.setTargets); gov_core hands both over (getGovPermDefs). The table gov_perms
-- mirrors it: rows are upserted, rows nobody declares any more become inactive (never deleted
-- automatically - their grants stay, greyed on the Permissions page).

CATALOGUE = {}    -- [perm] = { perm, module, area, family, target, targetName, danger, sort }
local FAMILY = {} -- [family pattern] = { row, ... }
local lastSig = ""
local lastBranchSig = ""

function PERMS.familyRows(family) return FAMILY[tostring(family)] or {} end

--- is a key / pattern a known right (or a pattern that covers at least one)?
function PERMS.known(pattern)
    if pattern == "*" then return true end
    if CATALOGUE[pattern] or FAMILY[pattern] then return true end
    for key in pairs(CATALOGUE) do
        if GOV.permMatch(pattern, key) then return true end
    end
    return false
end

local function validKey(k) return type(k) == "string" and #k <= 64 and k:match("^[%w_]+[%w_%.]*$") ~= nil end

--- builds the catalogue from the running modules -> true when it changed
function PERMS.buildCatalogue()
    local ok, defs = pcall(function() return exports.gov_core:getGovPermDefs() end)
    if not ok or type(defs) ~= "table" then return false end
    local cat, fam = {}, {}
    for res, d in pairs(type(defs.modules) == "table" and defs.modules or {}) do
        for i, p in ipairs(type(d.perms) == "table" and d.perms or {}) do
            local key = p[1] or p.key
            if validKey(key) and not key:find("*", 1, true) then
                cat[key] = { perm = key, module = res, area = tostring(p[2] or p.area or "other"), family = "", target = "",
                    targetName = "", danger = DB.int(p[3] or p.danger or 1), sort = i }
            end
        end
        for i, f in ipairs(type(d.families) == "table" and d.families or {}) do
            local pattern = f[1] or f.pattern
            local prefix = type(pattern) == "string" and pattern:match("^([%w_]+)%.%*%.") or nil
            if prefix and #pattern <= 48 then
                local exclude = {}
                for _, x in ipairs(type(f.exclude) == "table" and f.exclude or {}) do exclude[tostring(x)] = true end
                fam[pattern] = {}
                for _, t in ipairs((type(defs.targets) == "table" and defs.targets[prefix]) or {}) do
                    if not exclude[t.id] then
                        local key = prefix .. "." .. t.id .. pattern:sub(#prefix + 3)
                        if validKey(key) then
                            local row = { perm = key, module = res, area = tostring(f[2] or f.area or "other"), family = pattern,
                                target = t.id, targetName = t.name, danger = DB.int(f[3] or f.danger or 1), sort = 100 + i }
                            cat[key] = row
                            fam[pattern][#fam[pattern] + 1] = row
                        end
                    end
                end
            end
        end
    end
    CATALOGUE, FAMILY = cat, fam
    local parts = {}
    for k, r in pairs(cat) do parts[#parts + 1] = k .. "|" .. r.module .. "|" .. r.area .. "|" .. r.danger .. "|" .. r.targetName end
    table.sort(parts)
    local sig = table.concat(parts, ";")
    if sig == lastSig then return false end
    lastSig = sig
    PERMS.storeCatalogue()
    return true
end

--- writes the catalogue into gov_perms (50 rows per statement) and marks the missing rows inactive
function PERMS.storeCatalogue()
    local now = GOV.now()
    local rows = {}
    for _, r in pairs(CATALOGUE) do rows[#rows + 1] = r end
    for i = 1, #rows, 50 do
        local marks, args = {}, {}
        for k = i, math.min(i + 49, #rows) do
            local r = rows[k]
            marks[#marks + 1] = "(?, ?, ?, ?, ?, ?, ?, 1, ?, ?)"
            for _, v in ipairs({ r.perm, r.module, DB.clip(r.area, 24), r.family, r.target, r.danger, r.sort, now, now }) do
                args[#args + 1] = v
            end
        end
        DB.exec("INSERT INTO gov_perms (perm, module, area, family, target, danger, sort, active, first_seen, last_seen) VALUES "
            .. table.concat(marks, ", ") .. " ON DUPLICATE KEY UPDATE module = VALUES(module), area = VALUES(area), "
            .. "family = VALUES(family), target = VALUES(target), danger = VALUES(danger), sort = VALUES(sort), active = 1, "
            .. "last_seen = VALUES(last_seen)", unpack(args))
    end
    DB.query(function(dbRows)
        local gone = {}
        for _, r in ipairs(dbRows or {}) do
            if not CATALOGUE[tostring(r.perm)] then gone[#gone + 1] = tostring(r.perm) end
        end
        for i = 1, #gone, 50 do
            local marks, args = {}, {}
            for k = i, math.min(i + 49, #gone) do marks[#marks + 1] = "?"; args[#args + 1] = gone[k] end
            DB.exec("UPDATE gov_perms SET active = 0 WHERE perm IN (" .. table.concat(marks, ",") .. ")", unpack(args))
        end
    end, "SELECT perm FROM gov_perms WHERE active = 1")
end

--- every gov_perms row (also the inactive ones) for the Catalogue tab -> cb(list)
function PERMS.catalogueRows(cb)
    DB.query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local key = tostring(r.perm)
            local live = CATALOGUE[key]
            list[#list + 1] = { perm = key, module = tostring(r.module), area = tostring(r.area), family = tostring(r.family),
                target = tostring(r.target), targetName = live and live.targetName or tostring(r.target),
                danger = DB.int(r.danger), sort = DB.int(r.sort), active = live ~= nil }
        end
        cb(list)
    end, "SELECT perm, module, area, family, target, danger, sort FROM gov_perms ORDER BY area, module, sort, perm")
end

--- a module / target list / company branch changed (gov_core): rebuild, then the rights again
local rebuildTimer
local function rebuild()
    local changed = PERMS.buildCatalogue()
    PERMS.refreshBranchOf()
    local parts = {}
    for id, b in pairs(BRANCH_OF) do parts[#parts + 1] = id .. "=" .. b end
    table.sort(parts)
    local bsig = table.concat(parts, ",")
    if (changed or bsig ~= lastBranchSig) and PERMS.ready then PERMS.changed(false) end
    lastBranchSig = bsig
end
PERMS.rebuildCatalogue = rebuild

addEventHandler("onGovModulesChanged", root, function()
    if isTimer(rebuildTimer) then killTimer(rebuildTimer) end
    rebuildTimer = setTimer(rebuild, 500, 1)
end)
