-- gov_core / server/companies.lua
-- State companies live in gov_companies; their money stays a v_bank state account (kind 'state',
-- owner_ref = the company code). The State Treasury is a state account too but not a company.
-- Creating a company whose code already has a state account (one made before this table
-- existed) links that account instead of opening a new one. The other gov_* resources read them
-- through the exports at the bottom (lib: GOV.companyList / companyByCode / companyById).

GOVCO = {}       -- [code] = { id, code, name, description, accountId, status, createdAt, createdBy }

local function int(v) return DB.int(v) end

local function fromRow(r)
    return { id = int(r.id), code = tostring(r.code), name = tostring(r.name), description = tostring(r.description or ""),
        accountId = tonumber(r.account_id), status = tostring(r.status), createdAt = int(r.created_at),
        createdBy = tostring(r.created_by or "") }
end

function GOV.loadCompanies(cb)
    DB.query(function(rows)
        if rows then
            local fresh = {}
            for _, r in ipairs(rows) do
                local c = fromRow(r)
                fresh[c.code] = c
            end
            GOVCO = fresh
        end
        if cb then cb() end
    end, "SELECT id, code, name, description, account_id, status, created_at, created_by FROM gov_companies WHERE status = 'active'")
end

--- active companies with their bank info: { {id, code, name, description, account = info}, ... }
function GOV.companyList()
    local bank = GOV.bank()
    local list = {}
    for _, c in pairs(GOVCO) do
        local info = bank and c.accountId and bank:getAccountInfo(c.accountId) or nil
        list[#list + 1] = { id = c.id, code = c.code, name = c.name, description = c.description,
            accountId = c.accountId, balance = info and info.balance or 0, number = info and info.number or "",
            allowNegative = info and info.allowNegative or false, createdAt = c.createdAt }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function GOV.companyByCode(code) return GOVCO[tostring(code or "")] end

function GOV.companyById(id)
    id = tonumber(id)
    for _, c in pairs(GOVCO) do if c.id == id then return c end end
end

--- cb(true) | cb(false, err)
function GOV.createCompany(code, name, description, allowNegative, actor, cb)
    code = tostring(code or ""):lower()
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    description = DB.clip(tostring(description or ""):gsub("^%s+", ""):gsub("%s+$", ""), 255)
    if not code:match("^[a-z0-9_]+$") or #code < 3 or #code > 24 or code == "treasury" then return cb(false, "bad_code") end
    if name == "" or #name > 64 then return cb(false, "bad_name") end
    local bank = GOV.bank()
    if not bank then return cb(false, "unavailable") end
    -- a company whose bank account is gone (row deleted by hand) may be created again
    if GOVCO[code] and bank:getAccountInfo(GOVCO[code].accountId) then return cb(false, "code_taken") end

    local function insert(accountId)
        DB.query(function(ok, err)
            if ok == false then
                outputDebugString("[gov_core] company insert failed: " .. tostring(err), 1)
                return cb(false, "db")
            end
            GOV.log(actor, "company.create", { code = code, name = name })
            GOV.loadCompanies(function() cb(true) end)
        end, "INSERT INTO gov_companies (code, name, description, account_id, status, created_at, created_by) VALUES (?, ?, ?, ?, 'active', ?, ?) "
            .. "ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description), account_id = VALUES(account_id), "
            .. "status = 'active', created_at = VALUES(created_at), created_by = VALUES(created_by), closed_at = 0",
            code, name, description, accountId, GOV.now(), DB.clip(actor, 64))
    end

    -- an existing state account of this code is kept (v_bank cannot reopen a closed one)
    local existing = bank:getStateAccount(code)
    if existing then
        local info = bank:getAccountInfo(existing)
        if info and info.status == "closed" then return cb(false, "code_closed") end
        bank:renameAccount(existing, name)
        return insert(existing)
    end
    GOV.bankCall("createState", { code = code, name = name, allowNegative = allowNegative == true }, actor, function(r)
        if not r.ok then return cb(false, tostring(r.error)) end
        insert(r.account and r.account.id or bank:getStateAccount(code))
    end)
end

function GOV.renameCompany(c, name, actor)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > 64 then return false, "bad_name" end
    c.name = name
    DB.exec("UPDATE gov_companies SET name = ? WHERE id = ?", name, c.id)
    local bank = GOV.bank()
    if bank and c.accountId then bank:renameAccount(c.accountId, name) end
    GOV.log(actor, "company.rename", { code = c.code, name = name })
    return true
end

function GOV.describeCompany(c, description, actor)
    c.description = DB.clip(tostring(description or ""):gsub("^%s+", ""):gsub("%s+$", ""), 255)
    DB.exec("UPDATE gov_companies SET description = ? WHERE id = ?", c.description, c.id)
    GOV.log(actor, "company.describe", { code = c.code })
    return true
end

--- closes the company row and its bank account (the caller moved the balance first)
function GOV.closeCompany(c, actor)
    local bank = GOV.bank()
    if bank and c.accountId then
        local ok, err = bank:closeAccount(c.accountId)
        if not ok then return false, err end
    end
    GOVCO[c.code] = nil
    DB.exec("UPDATE gov_companies SET status = 'closed', closed_at = ? WHERE id = ?", GOV.now(), c.id)
    GOV.log(actor, "company.delete", { code = c.code })
    return true
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getStateCompanies() return GOV.companyList() end

function getStateCompany(code) return GOV.companyByCode(code) or false end

function getStateCompanyById(id) return GOV.companyById(id) or false end
