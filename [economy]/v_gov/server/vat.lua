-- v_gov / server/vat.lua
-- VAT rates per product group (setting tax.vat) and the property tax rate (tax.property).
-- The VAT rates are published as root element data "v_gov.vat" so shops show the same gross
-- price on the client as the server charges (shared/vat.lua).

local function publish()
    local rates = {}
    local set = GOV.get("tax.vat") or {}
    for _, g in ipairs(GOV_VAT_GROUPS) do rates[g] = tonumber(set[g]) or 0 end
    setElementData(root, "v_gov.vat", rates)
end

addEventHandler("onGovSettingChanged", resourceRoot, function(key)
    if key == "tax.vat" then publish() end
end)
addEventHandler("onResourceStart", resourceRoot, publish)
addEventHandler("onResourceStop", resourceRoot, function()
    removeElementData(root, "v_gov.vat")
end)

function getVatRate(group)
    local set = GOV.get("tax.vat") or {}
    return tonumber(set[tostring(group)]) or 0
end

function getVatRates()
    local out = {}
    for _, g in ipairs(GOV_VAT_GROUPS) do out[g] = getVatRate(g) end
    return out
end

--- the VAT part of a purchase to the treasury (the buyer already paid net + vat) -> true | false, err
function bookVat(group, net, vat, item)
    vat, net = math.floor(tonumber(vat) or 0), math.floor(tonumber(net) or 0)
    if vat <= 0 then return false, "bad_amount" end
    local bank = GOV.bank()
    local tid = bank and bank:getStateAccount("treasury")
    if not tid then return false, "unavailable" end
    local rate = net > 0 and math.floor(vat / net * 1000 + 0.5) / 10 or 0
    local ok, err = bank:credit(tid, vat, "tax.vat",
        { group = tostring(group), item = DB.clip(item or group, 48), net = net, rate = rate }, "v_gov")
    if not ok then outputDebugString("[v_gov] VAT booking failed: " .. tostring(err), 2) end
    return ok == true, err
end

--- property tax rate: part of the property price, every 24 online hours (biz_core)
function getPropertyTaxRate()
    return tonumber(GOV.get("tax.property")) or 0
end
