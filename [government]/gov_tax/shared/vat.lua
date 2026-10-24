-- gov_tax / shared/vat.lua
-- VAT (ÁFA) on top of every shop price, per product group (GOV_VAT_GROUPS). The rates are
-- synced to every client as root element data "gov_tax.vat" (server/vat.lua).
--
-- A shop includes gov_tax in its meta.xml and imports the small lib once:
--   if not VAT then loadstring(exports.gov_tax:importVat())() end
-- then
--   VAT.gross(group, net)          -> the price to show and to charge
--   VAT.split(group, net)          -> gross, vat (server: charge gross ...)
--   VAT.book(group, net, vat, item) -> (server, after the purchase succeeded) the VAT to the tax's account
--   VAT.rate(group) / VAT.pct(group) -> 0.27 / "27%"

local LIB = [[
VAT = {}
function VAT.rate(group)
    local r = getElementData(root, "gov_tax.vat")
    return type(r) == "table" and tonumber(r[group]) or 0
end
function VAT.of(group, net)
    net = math.floor(tonumber(net) or 0)
    if net <= 0 then return 0 end
    return math.floor(net * VAT.rate(group) + 0.5)
end
function VAT.gross(group, net)
    net = math.floor(tonumber(net) or 0)
    return net + VAT.of(group, net)
end
function VAT.split(group, net)
    local vat = VAT.of(group, net)
    return math.floor(tonumber(net) or 0) + vat, vat
end
function VAT.pct(group)
    return ("%g%%"):format(math.floor(VAT.rate(group) * 1000 + 0.5) / 10)
end
if not localPlayer then
    function VAT.book(group, net, vat, item)
        if (tonumber(vat) or 0) <= 0 then return false end
        local res = getResourceFromName("gov_tax")
        if not res or getResourceState(res) ~= "running" then return false end
        return exports.gov_tax:bookVat(group, net, vat, item)
    end
end
]]

function importVat() return LIB end
