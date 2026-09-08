--[[
    ui_phone / server/apps/contacts.lua
    Runs (and charges for) the actions offered by the phone contacts.

      Julia / Markus : a fixed action list (PHONE_CONFIG.contacts).
      Insurance      : a per-call list built from the caller's destroyed
                       v_ownveh vehicles. "contacts:dynPull" -> push the list on
                       "contacts:dyn"; a claim comes back through "contacts:action"
                       with the vehicle id as the action key.
]]

--------------------------------------------------------------------------------
-- Insurance (dynamic contact)
--------------------------------------------------------------------------------

local function ownvehReady()
    local res = getResourceFromName("v_ownveh")
    return res and getResourceState(res) == "running"
end

local function bankReady()
    local res = getResourceFromName("v_bank")
    return res and getResourceState(res) == "running"
end

-- Which pot can cover `amount` in full - bank money first, then cash.
-- -> "bank" | "cash" | nil
local function fundingSource(player, amount)
    if bankReady() and (tonumber(getElementData(player, "bank_money")) or 0) >= amount then
        return "bank"
    end
    if (getPlayerMoney(player) or 0) >= amount then
        return "cash"
    end
    return nil
end

-- Deduct `amount` from the chosen pot. -> true | false
local function chargeFrom(player, pot, amount)
    if pot == "bank" then
        return exports.v_bank:takeBankMoney(player, amount) == true
    end
    return takePlayerMoney(player, amount) ~= false
end

local function insuranceCost()
    local c = PHONE_CONFIG.contactByKey("insurance")
    return (c and tonumber(c.claimCost)) or 1000
end

-- The caller's wrecked vehicles: { { id, modelName, plate }, ... }
local function destroyedVehicles(player)
    if not ownvehReady() then return {} end
    local out = {}
    for _, v in ipairs(exports.v_ownveh:getOwnedVehicles(player) or {}) do
        if v.isDestroyed then
            out[#out + 1] = {
                id        = v.id,
                modelName = exports.v_ownveh:getModelName(v.model) or ("Vehicle " .. tostring(v.model)),
                plate     = v.plate,
            }
        end
    end
    return out
end

local function pushInsurance(player)
    local cost = insuranceCost()
    local rows = {}
    for _, v in ipairs(destroyedVehicles(player)) do
        local plate = (v.plate and v.plate ~= "") and ("  -  " .. v.plate) or ""
        rows[#rows + 1] = {
            key   = tostring(v.id),
            label = ("%s  (ID %d)%s   -   $%d"):format(v.modelName, v.id, plate, cost),
        }
    end
    PhoneServer.push(player, "contacts:dyn", "insurance", rows)
end

local function insuranceClaim(player, idStr)
    if not ownvehReady() then
        PhoneServer.toast(player, "Insurance is unavailable right now.")
        return
    end

    local id = tonumber(idStr)
    if not id then return end

    local target
    for _, v in ipairs(destroyedVehicles(player)) do
        if v.id == id then target = v break end
    end
    if not target then
        PhoneServer.toast(player, "That is not one of your destroyed vehicles.")
        pushInsurance(player)
        return
    end

    local cost = insuranceCost()
    local pot = fundingSource(player, cost)
    if not pot then
        PhoneServer.toast(player, "Not enough money (need $" .. cost .. " in the bank or as cash).")
        return
    end

    if exports.v_ownveh:setVehicleDestroyed(id, false) ~= true then
        PhoneServer.toast(player, "The claim could not be processed.")
        pushInsurance(player)
        return
    end

    if not chargeFrom(player, pot, cost) then
        -- Funds changed between the check and the deduction - undo the unlock.
        exports.v_ownveh:setVehicleDestroyed(id, true)
        PhoneServer.toast(player, "The payment could not be taken.")
        pushInsurance(player)
        return
    end

    PhoneServer.toast(player, ("Insurance restored your %s for $%d (from %s)."):format(
        target.modelName, cost, pot == "bank" and "your bank" or "cash"))
    pushInsurance(player)   -- row disappears; the list may now be empty
end

PhoneServer.on("contacts:dynPull", function(player, contactKey)
    if contactKey == "insurance" then
        pushInsurance(player)
    end
end)

--------------------------------------------------------------------------------
-- Action router
--------------------------------------------------------------------------------

PhoneServer.on("contacts:action", function(player, contactKey, actionKey)
    if contactKey == "insurance" then
        insuranceClaim(player, actionKey)
        return
    end

    local action = PHONE_CONFIG.contactActionByKey(contactKey, actionKey)
    if not action then return end

    if action.cost and getPlayerMoney(player) < action.cost then
        PhoneServer.toast(player, "Not enough money (need $" .. action.cost .. ").")
        return
    end

    if contactKey == "julia" and actionKey == "heal" then
        takePlayerMoney(player, action.cost)
        setElementHealth(player, 100)
        PhoneServer.toast(player, "Julia patched you up.")

    elseif contactKey == "julia" and actionKey == "armor" then
        takePlayerMoney(player, action.cost)
        setPedArmor(player, 100)
        PhoneServer.toast(player, "Julia refilled your armour.")

    elseif contactKey == "markus" and actionKey == "arena" then
        local ok = getResourceFromName("v_arenawar")
            and pcall(function() exports.v_arenawar:arenawarJoin(player) end)
        if not ok then PhoneServer.toast(player, "Arena War is unavailable right now.") end
        PhoneServer.close(player)

    elseif contactKey == "markus" and actionKey == "job" then
        -- A future job-request flow hooks in here.
        PhoneServer.toast(player, "Markus will get back to you.")
        PhoneServer.close(player)
    end
end)
