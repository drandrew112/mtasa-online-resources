if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/units.lua
-- Properties owned by companies (biz_units rows). One unit per property per
-- company; the dimension of a unit is BIZ.DIM_BASE + unit id (biz_int).

-- (UNITS is the id -> unit index of loaded companies, see companies.lua)
UNIT = {}

local function desc(fmt, ...) return fmt:format(...) end

--- buys a property for a loaded company; cb(unit | false, err)
function UNIT.buy(c, propertyId, actor, cb, opts)
    cb = cb or function() end
    opts = opts or {}
    local p = BIZ.property(propertyId)
    if not c or not p then return cb(false, "unknown_property") end
    if CO.hasProperty(c, propertyId) then return cb(false, "already_owned") end
    if p.kind == "office" and not opts.office then return cb(false, "use_move_hq") end
    if p.activity and not ACT.list[p.activity] then return cb(false, "activity_offline") end

    local price = opts.free and 0 or p.price
    if price > 0 then
        local ok, err = MONEY.debit(c, price, "property.buy", desc("Bought %s", BIZ.propertyName(propertyId)), actor)
        if not ok then return cb(false, err) end
    end
    local now = BIZ.now()
    DB.insert(function(id, err)
        if not id or id == true then
            if price > 0 and CO.byId[c.id] == c then
                MONEY.credit(c, price, "property.refund", desc("Refund: %s", BIZ.propertyName(propertyId)), actor)
            end
            outputDebugString("[biz_core] unit insert failed: " .. tostring(err), 1)
            return cb(false, "db")
        end
        local u = { id = id, companyId = c.id, propertyId = propertyId, pricePaid = price, upgradesPaid = 0, purchasedAt = now, data = {} }
        if CO.byId[c.id] ~= c then return cb(u) end   -- unloaded meanwhile (row stays, loads next time)
        c.units[id] = u
        UNITS[id] = u
        triggerEvent("onBizUnitAdded", resourceRoot, id, propertyId, c.id)
        CO.accessChanged(c)
        CO.saveValue(c)
        cb(u)
    end, "INSERT INTO biz_units (company_id, property_id, price_paid, purchased_at) VALUES (?, ?, ?, ?)", c.id, propertyId, price, now)
end

--- removes a unit (sold / admin / company sold). refund = euro credited back
function UNIT.remove(c, u, reason, refund, actor)
    if not c or not u or c.units[u.id] ~= u then return false end
    c.units[u.id] = nil
    UNITS[u.id] = nil
    DB.exec("DELETE FROM biz_units WHERE id = ?", u.id)
    triggerEvent("onBizUnitRemoved", resourceRoot, u.id, u.propertyId, c.id, reason or "sold")
    if refund and refund > 0 then
        MONEY.credit(c, refund, "property.sell", desc("Sold %s", BIZ.propertyName(u.propertyId)), actor)
    end
    CO.accessChanged(c)
    CO.saveValue(c)
    return true
end

--- what selling a unit back pays (price + upgrades at PROPERTY_SELL_RATIO)
function UNIT.refundOf(u)
    return math.floor((u.pricePaid + u.upgradesPaid) * BIZ.PROPERTY_SELL_RATIO)
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getUnit(unitId)
    local u = UNITS[tonumber(unitId)]
    return u and CO.unitPublic(u) or false
end

function getUnitCompany(unitId)
    local u = UNITS[tonumber(unitId)]
    return u and u.companyId or false
end

function getCompanyUnits(companyId, kind)
    local c = CO.byId[tonumber(companyId)]
    if not c then return false end
    local out = {}
    for _, u in ipairs(CO.unitsOfKind(c, kind)) do out[#out + 1] = CO.unitPublic(u) end
    return out
end

function getUnitDimension(unitId)
    unitId = tonumber(unitId)
    return unitId and BIZ.DIM_BASE + unitId or false
end

--- unit id of a biz dimension, or false
function getUnitOfDimension(dim)
    dim = tonumber(dim)
    if not dim or dim < BIZ.DIM_BASE or dim > BIZ.DIM_MAX then return false end
    return dim - BIZ.DIM_BASE
end

function getCatalog()
    local out = {}
    for _, p in ipairs(BIZ.PROPERTIES) do
        local b = BIZ.BUILDINGS[p.building] or {}
        out[#out + 1] = {
            id = p.id, kind = p.kind, tier = p.tier, activity = p.activity, building = p.building,
            template = p.template, price = p.price, upkeep = p.upkeep, illegal = p.illegal and true or false,
            name = BIZ.propertyName(p.id), city = b.city, x = b.x, y = b.y, z = b.z,
        }
    end
    return out
end

function getProperty(propertyId)
    local p = BIZ.property(propertyId)
    if not p then return false end
    local b = BIZ.BUILDINGS[p.building] or {}
    return {
        id = p.id, kind = p.kind, tier = p.tier, activity = p.activity, building = p.building,
        template = p.template, price = p.price, upkeep = p.upkeep, illegal = p.illegal and true or false,
        name = BIZ.propertyName(p.id), city = b.city, x = b.x, y = b.y, z = b.z,
    }
end

function getBuildings()
    local out = {}
    for id, b in pairs(BIZ.BUILDINGS) do
        out[id] = { id = id, name = b.name, city = b.city, x = b.x, y = b.y, z = b.z, rot = b.rot }
    end
    return out
end

--- moves an entrance (biz_int /bizpos overrides); z is the ground. Not saved
--- here: biz_int pushes its overrides again on every start / biz_core:ready.
function setBuildingPosition(id, x, y, z, rot)
    local b = BIZ.BUILDINGS[id]
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not b or not x or not y or not z then return false end
    b.x, b.y, b.z, b.rot = x, y, z, tonumber(rot) or b.rot
    return true
end

--- units this player may enter in a building: own company (founder) and the
--- company he is an associate of. { {unitId, propertyId, kind, template, name,
--- companyId, companyName, role, dimension}, ... }
function getAccessibleUnits(player, buildingId)
    local out = {}
    local function add(c, role)
        if not c then return end
        for _, u in pairs(c.units) do
            local p = BIZ.property(u.propertyId)
            if p and (not buildingId or p.building == buildingId) then
                out[#out + 1] = {
                    unitId = u.id, propertyId = u.propertyId, kind = p.kind, template = p.template,
                    building = p.building, name = BIZ.propertyName(u.propertyId),
                    companyId = c.id, companyName = c.name, role = role, dimension = BIZ.DIM_BASE + u.id,
                }
            end
        end
    end
    local own = CO.ofPlayer(player)
    if own and own.founder == player then add(own, "founder") end
    local mid = MEM.of[player]
    if mid then add(CO.byId[mid], "associate") end
    table.sort(out, function(a, b)
        if a.role ~= b.role then return a.role == "founder" end
        return a.unitId < b.unitId
    end)
    return out
end

--- may this player be inside this unit right now
function canAccessUnit(player, unitId)
    local u = UNITS[tonumber(unitId)]
    if not u then return false end
    local c = CO.byId[u.companyId]
    if not c then return false end
    if c.founder == player then return "founder" end
    if MEM.of[player] == c.id then return "associate" end
    return false
end

--- adds the price of an upgrade bought for a unit (already debited by the caller
--- through buyUnitUpgrade) to the company value
function buyUnitUpgrade(unitId, amount, label, actor)
    local u = UNITS[tonumber(unitId)]
    local c = u and CO.byId[u.companyId]
    amount = math.floor(tonumber(amount) or 0)
    if not c or amount <= 0 then return false, "invalid" end
    local ok, err = MONEY.debit(c, amount, "property.upgrade",
        desc("%s: %s", BIZ.propertyName(u.propertyId), tostring(label or "upgrade")), actor or "")
    if not ok then return false, err end
    u.upgradesPaid = u.upgradesPaid + amount
    DB.exec("UPDATE biz_units SET upgrades_paid = upgrades_paid + ? WHERE id = ?", amount, u.id)
    CO.saveValue(c)
    return true
end

--- free-form per-unit data of activity resources (small JSON, e.g. settings)
function setUnitData(unitId, key, value)
    local u = UNITS[tonumber(unitId)]
    if not u or type(key) ~= "string" then return false end
    u.data[key] = value
    DB.exec("UPDATE biz_units SET data_json = ? WHERE id = ?", toJSON(u.data, true), u.id)
    return true
end

function getUnitData(unitId, key)
    local u = UNITS[tonumber(unitId)]
    if not u then return nil end
    return u.data[key]
end
