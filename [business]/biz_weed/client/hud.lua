if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_weed / client/hud.lua
-- Supply / product / value in the bottom-right corner (ui_core stat trackers
-- with progress bars) while the player is inside a weed farm. The server
-- sends the data on entry and on every change, false on leaving.

local shown = false

local function money(n)
    return L("biz_weed.hud.money", { amount = n })
end

addEvent("bizweed:hud", true)
addEventHandler("bizweed:hud", resourceRoot, function(d)
    local ui = exports.ui_core
    if not d then
        if shown then
            ui:removeStatTracker("bizweed_supply")
            ui:removeStatTracker("bizweed_product")
            ui:removeStatTracker("bizweed_value")
        end
        shown = false
        return
    end
    local cap = math.max(1, d.capacity or 100)
    local supply = ("%d / %d"):format(d.supply, cap)
    if (d.pending or 0) > 0 then supply = supply .. "  (+" .. d.pending .. ")" end
    local product = ("%d / %d"):format(d.product, cap)
    if not shown then
        ui:addStatTracker("bizweed_value", L("biz_weed.hud.value"), money(d.value), { order = 1 })
        ui:addStatTracker("bizweed_product", L("biz_weed.hud.product"), product, { order = 2, progress = d.product / cap, barColor = { 210, 153, 34 } })
        ui:addStatTracker("bizweed_supply", L("biz_weed.hud.supply"), supply, { order = 3, progress = d.supply / cap, barColor = { 63, 185, 80 } })
        shown = true
    else
        ui:updateStatTracker("bizweed_value", money(d.value))
        ui:updateStatTracker("bizweed_product", product, nil, d.product / cap)
        ui:updateStatTracker("bizweed_supply", supply, nil, d.supply / cap)
    end
end)
