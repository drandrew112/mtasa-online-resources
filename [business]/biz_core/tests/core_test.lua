-- biz_core unit tests (tests/run.py loads stubs.lua and the resource scripts first)

local results = { pass = 0, fail = 0, lines = {} }
local function check(name, cond, info)
    if cond then results.pass = results.pass + 1
    else
        results.fail = results.fail + 1
        results.lines[#results.lines + 1] = "FAIL " .. name .. (info and (": " .. tostring(info)) or "")
    end
end

-- a company row as MySQL would give it
local function companyRow(id, account, name, clean, dirty)
    return { id = id, owner_account = account, founder_account = account, name = name, balance_clean = clean,
             balance_dirty = dirty or 0, launder_queue = 0, hq_unit_id = 10, status = "active", active_seconds = 0,
             upkeep_seconds = 0, value_cache = 0, peak_value = 0, created_at = 1, renamed_at = 0 }
end

local function loadCompany(player, row, units)
    TEST.acc["c:" .. row.id] = row.balance_clean   -- the clean money is the bank account
    TEST.db = function(sql)
        if sql:find("FROM biz_companies") then return { row } end
        if sql:find("FROM biz_units") then return units end
        return {}
    end
    local got
    CO.load(player.account, player, function(c) got = c end)
    return got
end

DB.ready = true

---------------------------------------------------------------- load + money
local alice = TEST.player("Alice", "alice")
local c = loadCompany(alice, companyRow(1, "alice", "Alice Org", 1000, 500), {
    { id = 10, company_id = 1, property_id = "office_lv_redsands", price_paid = 250000, upgrades_paid = 0, purchased_at = 1 },
    { id = 11, company_id = 1, property_id = "weed_castillo", price_paid = 450000, upgrades_paid = 100000, purchased_at = 1 },
})
check("load", c and c.id == 1 and CO.byId[1] == c)
check("units indexed", UNITS[10] and UNITS[11])
check("published data", getElementData(alice, "biz:company") and getElementData(alice, "biz:company").name == "Alice Org")

check("clean from the bank", c.clean == 1000, c.clean)
check("debit clean first", MONEY.debit(c, 1200, "biz.upkeep", nil, "", "") and c.clean == 0 and c.dirty == 300, c.clean .. "/" .. c.dirty)
check("bank booked the clean part", TEST.acc["c:1"] == 0, TEST.acc["c:1"])
check("debit refuses", select(2, MONEY.debit(c, 1000, "biz.upkeep", nil, "", "")) == "not_enough_money")
MONEY.credit(c, 700, "biz.property_sell", nil, "", "")
check("credit clean", c.clean == 700 and TEST.acc["c:1"] == 700)
check("ledger rows (clean + dirty + clean)", #c.ledger == 3, #c.ledger)
check("withdraw dirty as cash", withdrawFromCompany(alice, 300, "dirty").ok and c.dirty == 0 and TEST.cash[alice] == 300)
check("withdraw dirty empty", not withdrawFromCompany(alice, 1, "dirty").ok)
TEST.acc["p:Alice"] = 1000
check("deposit is a bank transfer", depositToCompany(alice, 400).ok and c.clean == 1100 and TEST.acc["p:Alice"] == 600)
check("withdraw clean to the bank", withdrawFromCompany(alice, 400, "clean").ok and c.clean == 700 and TEST.acc["p:Alice"] == 1000)

---------------------------------------------------------------- sale payout: balance in full, assets at 60%
local payout, assets = CO.salePayout(c)
check("assets", assets == 250000 + 450000 + 100000, assets)
check("payout", payout == 700 + math.floor(800000 * 0.6), payout)

---------------------------------------------------------------- laundering
c.dirty = 100000
MONEY.queueLaunder(c, 60000)
local took, fee = MONEY.processLaunder(c, 40000, 0.12)
check("launder max per hour", took == 40000 and fee == 4800, took .. "/" .. fee)
check("launder balances", c.dirty == 60000 and c.clean == 700 + 40000 - 4800 and c.launder == 20000, c.dirty .. "/" .. c.clean .. "/" .. c.launder)
check("launder queue cap", not MONEY.queueLaunder(c, 50000))

---------------------------------------------------------------- associates: founder + 3
local bob, carl, dan, eve = TEST.player("Bob", "bob"), TEST.player("Carl", "carl"), TEST.player("Dan", "dan"), TEST.player("Eve", "eve")
for _, p in ipairs({ bob, carl, dan, eve }) do MEM.invite(alice, p) end
check("accept 1", MEM.accept(bob, 1))
check("accept 2", MEM.accept(carl, 1))
check("accept 3", MEM.accept(dan, 1))
local ok4, err4 = MEM.accept(eve, 1)
check("fourth associate refused", not ok4 and err4 == "full", err4)
check("roles", getPlayerRole(alice, 1) == "founder" and getPlayerRole(bob, 1) == "associate" and not getPlayerRole(eve, 1))
check("member data", getElementData(bob, "biz:member") ~= nil)
TEST.quit(bob)
check("disconnect ends membership", MEM.of[bob] == nil and MEM.count(1) == 2, MEM.count(1))
MEM.leave(carl, "left")
check("leave", MEM.of[carl] == nil and getElementData(carl, "biz:member") == nil)

-- an associate may own a company of his own
local danCo = loadCompany(dan, companyRow(2, "dan", "Dan Org", 0), {})
check("associate with own company", danCo and MEM.of[dan] == 1 and CO.byId[2] == danCo)

---------------------------------------------------------------- sale split
TEST.bank = {}
c.dirty = 0
local out = paySaleDelivery(1, alice, 60000, 40, "weed")
check("founder delivery to company", out.role == "founder" and out.toCompany == 60000 and c.dirty == 60000)
out = paySaleDelivery(1, dan, 60000, 40, "weed")
check("associate 80/20 (cash)", out.role == "associate" and out.toPlayer == 48000 and out.toCompany == 12000 and TEST.cash[dan] == 48000)
local before = c.dirty
out = paySaleDelivery(1, eve, 60000, 40, "weed")
check("stranger 60/0 (cash)", out.role == "stranger" and out.toPlayer == 36000 and c.dirty == before and TEST.cash[eve] == 36000)
setSaleMultiplier("weed", 1.5)
ACT.list.weed = { kind = BIZ.KIND_SUPPLY_DELIVER }
out = paySaleDelivery(1, alice, 60000, 40, "weed")
check("weekly multiplier", out.value == 90000)
ACT.list.casino = { kind = BIZ.KIND_PASSIVE }
setSaleMultiplier("casino", 2)
check("no multiplier for passive", getSaleMultiplier("casino") == 1)

---------------------------------------------------------------- upkeep pause
TEST.acc["c:1"], c.clean, c.dirty = 100, 100, 0
c.upkeepSeconds = BIZ.UPKEEP_INTERVAL - 10
local ticks = 0
addEventHandler("onBizCompanyTick", root, function(id) if id == 1 then ticks = ticks + 1 end end)
c.lastTick = 0
TEST.tick = 60000
TICK.finish(c)
check("unpaid upkeep pauses", c.paused == true and ticks == 0, tostring(c.paused) .. " " .. ticks)
TEST.acc["c:1"], c.clean = 100000, 100000
TEST.tick = 120000
c.lastTick = 60000
TICK.finish(c)
check("paid upkeep resumes", c.paused == false and ticks == 1 and c.clean == 100000 - (1500 + 3000), c.clean)

---------------------------------------------------------------- names
check("name trim", ACTION.cleanName("  My   Org  ") == "My Org")
check("name short", select(2, ACTION.cleanName("ab")) == "name_short")
check("name bad chars", select(2, ACTION.cleanName("Bad<Org>")) == "name_invalid")
check("name colour codes stripped", ACTION.cleanName("#FF0000Red Org") == "Red Org")

---------------------------------------------------------------- founder leaves: memberships end
TEST.quit(alice)
check("founder quit unloads", CO.byId[1] == nil)
check("founder quit ends memberships", MEM.of[dan] == nil and MEM.count(1) == 0)

TEST.result = results
