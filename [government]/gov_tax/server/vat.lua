-- gov_tax / server/vat.lua
-- VAT rates per product group (setting tax.vat) and the property tax rate (tax.property).
-- The VAT rates are published as root element data "gov_tax.vat" so shops show the same gross
-- price on the client as the server charges (shared/vat.lua).

local function publish()
    local rates = {}
    local set = GOV.get("tax.vat") or GOV_DEFAULTS["tax.vat"]
    for _, g in ipairs(GOV_VAT_GROUPS) do rates[g] = tonumber(set[g]) or 0 end
    setElementData(root, "gov_tax.vat", rates)
end

-- the setting changed on /gov or was (re)loaded by gov_core
addEventHandler("onGovSettingChanged", root, function(key)
    if key == "tax.vat" then publish() end
end)
GOV.onReady(publish)
addEventHandler("gov_core:ready", root, publish)   -- gov_core restarted
addEventHandler("onResourceStop", resourceRoot, function()
    removeElementData(root, "gov_tax.vat")
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

--- the VAT part of a purchase to the tax's state account (the buyer already paid net + vat); with
--- no account set the VAT simply disappears -> true | false, err
function bookVat(group, net, vat, item)
    vat, net = math.floor(tonumber(vat) or 0), math.floor(tonumber(net) or 0)
    if vat <= 0 then return false, "bad_amount" end
    local bank = GOV.bank()
    if not bank then return false, "unavailable" end
    local tid = getTaxTarget("vat")
    if not tid then return true end
    local rate = net > 0 and math.floor(vat / net * 1000 + 0.5) / 10 or 0
    local ok, err = bank:credit(tid, vat, "tax.vat",
        { group = tostring(group), item = DB.clip(item or group, 48), net = net, rate = rate }, "v_gov")
    if not ok then outputDebugString("[gov_tax] VAT booking failed: " .. tostring(err), 2) end
    return ok == true, err
end

--- property tax rate: part of the property price, every 24 online hours (biz_core)
function getPropertyTaxRate()
    return tonumber(GOV.get("tax.property")) or 0
end
