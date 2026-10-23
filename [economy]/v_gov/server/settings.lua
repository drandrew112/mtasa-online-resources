-- v_gov / server/settings.lua
-- gov_settings cache: a key without a row uses GOV_DEFAULTS (or nil). Both server instances
-- re-read the table every GOV.RESYNC_MS; the instance that changes a value applies it at once.
-- Also the gov_members roles.

SETTINGS = {}   -- [key] = value (only the stored ones)
MEMBERS = {}    -- [account name] = role

addEvent("onGovSettingChanged", false)  -- (key, value), source = resourceRoot

local function decode(s)
    local v = fromJSON(tostring(s or ""))
    return v
end

local function encode(v)
    return toJSON(v, true) or "null"
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

--- the value of a setting (a copy for tables): stored, else the default
function GOV.get(key)
    local v = SETTINGS[key]
    if v == nil then v = GOV_DEFAULTS[key] end
    return copy(v)
end

--- stores a setting (value nil = back to the default) and logs it
function GOV.set(key, value, actor)
    local old = GOV.get(key)
    if value == nil then
        SETTINGS[key] = nil
        DB.exec("DELETE FROM gov_settings WHERE skey = ?", key)
    else
        SETTINGS[key] = copy(value)
        DB.exec("INSERT INTO gov_settings (skey, value, updated_by, updated_at) VALUES (?, ?, ?, ?) "
            .. "ON DUPLICATE KEY UPDATE value = VALUES(value), updated_by = VALUES(updated_by), updated_at = VALUES(updated_at)",
            key, encode(value), DB.clip(actor, 64), GOV.now())
    end
    GOV.log(actor, "setting", { key = key, old = old, new = value })
    triggerEvent("onGovSettingChanged", resourceRoot, key, GOV.get(key))
end

function loadSettings(cb)
    DB.query(function(rows)
        if rows then
            local fresh = {}
            for _, r in ipairs(rows) do
                local v = decode(r.value)
                if v ~= nil then fresh[tostring(r.skey)] = v end
            end
            for k, v in pairs(fresh) do
                if encode(SETTINGS[k]) ~= encode(v) then
                    SETTINGS[k] = v
                    triggerEvent("onGovSettingChanged", resourceRoot, k, copy(v))
                end
            end
            for k in pairs(SETTINGS) do
                if fresh[k] == nil then
                    SETTINGS[k] = nil
                    triggerEvent("onGovSettingChanged", resourceRoot, k, GOV.get(k))
                end
            end
        end
        DB.query(function(mrows)
            if mrows then
                MEMBERS = {}
                for _, r in ipairs(mrows) do MEMBERS[tostring(r.account_name):lower()] = tostring(r.role) end
            end
            if cb then cb() end
        end, "SELECT account_name, role FROM gov_members")
    end, "SELECT skey, value FROM gov_settings")
end

--------------------------------------------------------------------------------
-- roles
--------------------------------------------------------------------------------

--- "viewer" | "official" | "minister" | false
function getGovRole(player)
    local name = GOV.accountOf(player)
    if not name then return false end
    local level = isResourceRunning("v_mysql") and tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    if level >= GOV.ADMIN_LEVEL then return "minister" end
    return MEMBERS[name] or false
end

--- has the player at least this role?
function GOV.can(player, need)
    local role = getGovRole(player)
    return role and GOV.ROLES[role] >= (GOV.ROLES[need] or 99) or false
end

function GOV.setMember(accountName, role, actor)
    accountName = tostring(accountName or ""):lower()
    if accountName == "" then return false end
    if role ~= nil and not GOV.ROLES[role] then return false end
    if role then
        MEMBERS[accountName] = role
        DB.exec("INSERT INTO gov_members (account_name, role, granted_by, granted_at) VALUES (?, ?, ?, ?) "
            .. "ON DUPLICATE KEY UPDATE role = VALUES(role), granted_by = VALUES(granted_by), granted_at = VALUES(granted_at)",
            accountName, role, DB.clip(actor, 64), GOV.now())
    else
        MEMBERS[accountName] = nil
        DB.exec("DELETE FROM gov_members WHERE account_name = ?", accountName)
    end
    GOV.log(actor, "member.set", { account = accountName, role = role or "none" })
    return true
end
