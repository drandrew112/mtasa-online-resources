if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/admin.lua
-- Data and actions of the v_admin "Organizations" page. v_admin checks the
-- admin levels; this file only does the work. Asynchronous (REMOTE.call):
--
--   exports.biz_core:adminCall(requestId, action, args, adminAccount)
--   answers triggerEvent("v_admin:remoteResult", <v_admin root>, requestId, result)
--
-- actions: list {query, status} | detail {id} | rename {id, name} |
--          adjust {id, amount, dirty, reason} | transfer {id, account} |
--          forcesell {id} | removeunit {id, unitId} | giveunit {id, propertyId} |
--          kick {id, player}
-- result: { ok = true, ... } | { ok = false, error = "<code>" }

local int = DB.int

local function answer(root, id, result)
    if isElement(root) then triggerEvent("v_admin:remoteResult", root, id, result) end
end

local function summary(r)
    local c = CO.byId[int(r.id)]
    return {
        id = int(r.id), name = c and c.name or tostring(r.name), founder = tostring(r.founder_account),
        status = tostring(r.status), value = c and c.valueCache or int(r.value_cache),
        balance = c and CO.balance(c) or int(r.balance_clean) + int(r.balance_dirty),
        online = c ~= nil, associates = c and MEM.count(c.id) or 0, createdAt = int(r.created_at),
        hq = r.hq_property and BIZ.propertyName(r.hq_property) or "", properties = int(r.props),
    }
end

local A = {}

function A.list(args, done)
    local q = tostring(args.query or "")
    local status = args.status == "sold" and "sold" or (args.status == "all" and "all" or "active")
    local where, params = {}, {}
    if status ~= "all" then where[#where + 1] = "c.status = ?"; params[#params + 1] = status end
    if q ~= "" then
        where[#where + 1] = "(c.name LIKE ? OR c.founder_account LIKE ? OR c.id = ?)"
        local like = "%" .. q:gsub("[%%_\\]", "\\%0") .. "%"
        params[#params + 1] = like; params[#params + 1] = like; params[#params + 1] = tonumber(q) or -1
    end
    local sql = [[SELECT c.*, (SELECT u.property_id FROM biz_units u WHERE u.id = c.hq_unit_id) AS hq_property,
                         (SELECT COUNT(*) FROM biz_units u2 WHERE u2.company_id = c.id) AS props
                  FROM biz_companies c ]] .. (#where > 0 and ("WHERE " .. table.concat(where, " AND ")) or "") ..
                " ORDER BY c.value_cache DESC LIMIT 200"
    DB.query(function(rows)
        if not rows then return done({ ok = false, error = "db" }) end
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = summary(r) end
        done({ ok = true, rows = out })
    end, sql, unpack(params))
end

function A.detail(args, done)
    local id = tonumber(args.id)
    if not id then return done({ ok = false, error = "bad_id" }) end
    local live = CO.byId[id]
    DB.query(function(rows)
        if not rows or not rows[1] then return done({ ok = false, error = "not_found" }) end
        local c = live or CO.companyFromRow(rows[1])
        DB.query(function(urows)
            local units = {}
            if live then
                for _, u in ipairs(CO.unitsOfKind(live)) do
                    local pu = CO.unitPublic(u)
                    pu.stockValue = CO.stockValue(u)
                    units[#units + 1] = pu
                end
            else
                for _, r in ipairs(urows or {}) do units[#units + 1] = CO.unitPublic(CO.unitFromRow(r)) end
            end
            DB.query(function(lrows)
                local ledger = {}
                for _, r in ipairs(lrows or {}) do ledger[#ledger + 1] = CO.ledgerFromRow(r) end
                done({
                    ok = true,
                    company = {
                        id = c.id, name = c.name, founder = c.founderAccount, owner = c.account, status = c.status,
                        clean = c.clean, dirty = c.dirty, launder = c.launder, online = live ~= nil,
                        paused = live and live.paused or false, value = live and CO.value(live) or c.valueCache,
                        peakValue = c.peakValue, activeSeconds = c.activeSeconds, createdAt = c.createdAt,
                        hqUnit = c.hqUnit, associates = live and MEM.publicList(id) or {},
                    },
                    units = units, ledger = ledger,
                })
            end, "SELECT * FROM biz_ledger WHERE company_id = ? ORDER BY id DESC LIMIT 100", id)
        end, "SELECT * FROM biz_units WHERE company_id = ?", id)
    end, "SELECT * FROM biz_companies WHERE id = ?", id)
end

function A.rename(args, done, admin)
    local id = tonumber(args.id)
    local name, err = ACTION.cleanName(args.name)
    if not id or not name then return done({ ok = false, error = err or "bad_id" }) end
    DB.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return done({ ok = false, error = "name_taken" }) end
        local c = CO.byId[id]
        if c then
            c.name = name
            CO.publish(c)
            MONEY.apply(c, 0, 0, "admin.rename", ("Renamed by an admin to %s"):format(name), admin)
            NOTIFY.company(c, "all", L.msg("biz_core.rename.done", { name = name }))
        end
        REG.refresh()
        done({ ok = true })
    end, "UPDATE biz_companies SET name = ?, name_key = IF(status = 'active', ?, NULL) WHERE id = ?", name, name:lower(), id)
end

function A.adjust(args, done, admin)
    local id = tonumber(args.id)
    local amount = math.floor(tonumber(args.amount) or 0)
    local dirty = args.dirty and true or false
    local reason = DB.clip(args.reason, 120)
    if not id or amount == 0 then return done({ ok = false, error = "bad_amount" }) end
    if reason == "" then return done({ ok = false, error = "reason_required" }) end
    local desc = ("Admin adjustment: %s"):format(reason)
    local c = CO.byId[id]
    if c then
        if amount < 0 and (dirty and c.dirty or c.clean) < -amount then return done({ ok = false, error = "not_enough_money" }) end
        MONEY.apply(c, dirty and 0 or amount, dirty and amount or 0, "admin.adjust", desc, admin)
        NOTIFY.company(c, "founder", L.msg("biz_core.admin.adjusted", { amount = amount }))
        return done({ ok = true })
    end
    -- offline company: delta on the row, ledger row with the new balance
    local col = dirty and "balance_dirty" or "balance_clean"
    DB.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return done({ ok = false, error = "not_enough_money" }) end
        DB.query(function(rows)
            local r = rows and rows[1]
            local bal = r and (int(r.balance_clean) + int(r.balance_dirty)) or 0
            DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account) VALUES (?, ?, ?, ?, ?, 'admin.adjust', ?, ?)",
                id, BIZ.now(), amount, dirty and 1 or 0, bal, desc, DB.clip(admin, 64))
            done({ ok = true })
        end, "SELECT balance_clean, balance_dirty FROM biz_companies WHERE id = ?", id)
    end, "UPDATE biz_companies SET " .. col .. " = " .. col .. " + ? WHERE id = ? AND status = 'active' AND " .. col .. " + ? >= 0",
        amount, id, amount)
end

--- new founder account (must exist and have no active company); only while
--- the company is not loaded (founder offline), to keep the instances simple
function A.transfer(args, done, admin)
    local id = tonumber(args.id)
    local acc = tostring(args.account or "")
    if not id or acc == "" then return done({ ok = false, error = "bad_id" }) end
    if CO.byId[id] then return done({ ok = false, error = "founder_online" }) end
    local canon = BIZ.running("acc_auth") and exports.acc_auth:accountNameExists(acc)
    if not canon then return done({ ok = false, error = "no_account" }) end
    if CO.playerOf(canon) then return done({ ok = false, error = "target_online" }) end
    DB.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return done({ ok = false, error = "target_has_company" }) end
        DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account) VALUES (?, ?, 0, 0, 0, 'admin.transfer', ?, ?)",
            id, BIZ.now(), ("Founder changed to %s by an admin"):format(canon), DB.clip(admin, 64))
        REG.refresh()
        done({ ok = true })
    end, "UPDATE biz_companies SET owner_account = ?, founder_account = ? WHERE id = ? AND status = 'active'", canon, canon, id)
end

function A.forcesell(args, done, admin)
    local id = tonumber(args.id)
    local c = id and CO.byId[id]
    if c and isElement(c.founder) then
        local r = sellCompany(c.founder)
        return done(r)
    end
    if not id then return done({ ok = false, error = "bad_id" }) end
    -- founder offline: the company is closed without a payout (the admin decides
    -- about a compensation); with the founder online it is a normal sale above
    DB.exec("DELETE FROM biz_units WHERE company_id = ?", id)
    DB.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return done({ ok = false, error = "not_found" }) end
        DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account) VALUES (?, ?, 0, 0, 0, 'admin.close', 'Closed by an admin (founder offline, no payout)', ?)",
            id, BIZ.now(), DB.clip(admin, 64))
        REG.refresh()
        done({ ok = true, payout = 0 })
    end, "UPDATE biz_companies SET status = 'closed', owner_account = NULL, name_key = NULL, sold_at = ?, hq_unit_id = NULL WHERE id = ? AND status = 'active'",
        BIZ.now(), id)
end

function A.removeunit(args, done, admin)
    local c = CO.byId[tonumber(args.id) or -1]
    local unitId = tonumber(args.unitId)
    if not c then
        if not unitId then return done({ ok = false, error = "bad_id" }) end
        local cid = tonumber(args.id) or -1
        DB.query(function(rows)
            if not rows or not rows[1] then return done({ ok = false, error = "not_found" }) end
            if int(rows[1].hq_unit_id) == unitId then return done({ ok = false, error = "cannot_sell_hq" }) end
            DB.query(function(res, affected)
                done({ ok = res ~= false and tonumber(affected) == 1, error = "not_found" })
            end, "DELETE FROM biz_units WHERE id = ? AND company_id = ?", unitId, cid)
        end, "SELECT hq_unit_id FROM biz_companies WHERE id = ?", cid)
        return
    end
    local u = c.units[unitId or -1]
    if not u then return done({ ok = false, error = "not_found" }) end
    if u.id == c.hqUnit then return done({ ok = false, error = "cannot_sell_hq" }) end
    UNIT.remove(c, u, "admin", 0, admin)
    done({ ok = true })
end

function A.giveunit(args, done, admin)
    local c = CO.byId[tonumber(args.id) or -1]
    local p = BIZ.property(args.propertyId)
    if not p or p.kind == "office" then return done({ ok = false, error = "unknown_property" }) end
    if not c then
        local id = tonumber(args.id)
        if not id then return done({ ok = false, error = "bad_id" }) end
        DB.insert(function(uid)
            done({ ok = uid and uid ~= true, error = "already_owned" })
        end, "INSERT INTO biz_units (company_id, property_id, price_paid, purchased_at) VALUES (?, ?, 0, ?)", id, p.id, BIZ.now())
        return
    end
    UNIT.buy(c, p.id, admin, function(u, err)
        done(u and { ok = true } or { ok = false, error = err or "db" })
    end, { free = true })
end

function A.kick(args, done)
    local c = CO.byId[tonumber(args.id) or -1]
    if not c then return done({ ok = false, error = "founder_offline" }) end
    for p in pairs(MEM.membersOf(c.id)) do
        if CO.accountOf(p) == args.player or getPlayerName(p) == args.player then
            MEM.leave(p, "removed")
            return done({ ok = true })
        end
    end
    done({ ok = false, error = "not_member" })
end

function adminCall(requestId, action, args, adminAccount)
    local root = sourceResource and getResourceRootElement(sourceResource)
    local fn = A[tostring(action)]
    if not fn or not DB.ready then return false end
    args = type(args) == "table" and args or {}
    local admin = tostring(adminAccount or "admin")
    local ok, err = pcall(fn, args, function(result) answer(root, requestId, result) end, admin)
    if not ok then
        outputDebugString("[biz_core] adminCall " .. tostring(action) .. ": " .. tostring(err), 1)
        answer(root, requestId, { ok = false, error = "failed" })
    end
    return true
end

--- property ids an admin can give (non-office)
function adminGetCatalog()
    return getCatalog()
end
