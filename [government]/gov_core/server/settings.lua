-- gov_core / server/settings.lua
-- gov_settings cache: a key without a row uses the default its owner module registered (or nil).
-- Every key prefix ("tax.", "work.", ...) belongs to one module (registerModule settings.prefixes);
-- only that module may change it (export setSetting). Both server instances re-read the table
-- every GOV.RESYNC_MS; the instance that changes a value applies it at once.
-- Also the gov_members roles.

SETTINGS = {}   -- [key] = value (only the stored ones)
DEFAULTS = {}   -- [key] = value, registered by the owner modules
OWNERS = {}     -- [prefix] = resource name
MEMBERS = {}    -- [account name] = role

addEvent("onGovSettingChanged", false)  -- (key, value), source = gov_core resourceRoot
addEvent("onGovSettingsSynced", false)  -- after every re-read, source = gov_core resourceRoot

local function decode(s)
    local v = fromJSON(tostring(s or ""))
    return v
end

local function encode(v)
    if v == nil then return "null" end   -- toJSON(nil) is a bad argument
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
    if v == nil then v = DEFAULTS[key] end
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
    return true
end

--- the module that owns a key (the longest registered prefix), or nil
function GOV.ownerOf(key)
    local best, owner = 0, nil
    for prefix, res in pairs(OWNERS) do
        if #prefix > best and key:sub(1, #prefix) == prefix then best, owner = #prefix, res end
    end
    return owner
end

--- the prefixes + defaults of a module (empty lists = it stopped)
function GOV.setDefaults(resName, prefixes, defaults)
    for key in pairs(DEFAULTS) do
        if GOV.ownerOf(key) == resName then DEFAULTS[key] = nil end
    end
    for prefix, res in pairs(OWNERS) do if res == resName then OWNERS[prefix] = nil end end
    for _, prefix in ipairs(type(prefixes) == "table" and prefixes or {}) do
        if type(prefix) == "string" and prefix ~= "" then
            if OWNERS[prefix] and OWNERS[prefix] ~= resName then
                outputDebugString(("[gov_core] setting prefix %s of %s is taken by %s"):format(prefix, resName, OWNERS[prefix]), 2)
            else
                OWNERS[prefix] = resName
            end
        end
    end
    for key, v in pairs(type(defaults) == "table" and defaults or {}) do
        if GOV.ownerOf(key) == resName then DEFAULTS[key] = copy(v) end
    end
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
-- exports
--------------------------------------------------------------------------------

function getSetting(key)
    return GOV.get(tostring(key))
end

--- the stored settings (no defaults) whose key starts with `prefix`: { key = value }
function getStoredSettings(prefix)
    prefix = tostring(prefix or "")
    local out = {}
    for k, v in pairs(SETTINGS) do
        if k:sub(1, #prefix) == prefix then out[k] = copy(v) end
    end
    return out
end

--- a module changes one of its own keys -> true | false
function setSetting(key, value, actor)
    key = tostring(key or "")
    local caller = sourceResource and getResourceName(sourceResource) or "gov_core"
    local owner = GOV.ownerOf(key)
    if caller ~= "gov_core" and owner ~= caller then
        outputDebugString(("[gov_core] %s may not change the setting %s (owner: %s)"):format(caller, key, tostring(owner)), 2)
        return false
    end
    return GOV.set(key, value, actor)
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

function canGov(player, need) return GOV.can(player, need) end

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
