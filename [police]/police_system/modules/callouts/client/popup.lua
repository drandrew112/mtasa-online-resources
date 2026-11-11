-- police_system / modules/callouts/client/popup.lua
-- The call offer of the CalloutManager as a ui_core pinned notification (2026-11-11 - the own popup window is gone):
-- title = call number · kind · priority, subtitle = call title, description = text + zone · distance, hint = Y accept /
-- N decline, a countdown bar until the offer expires. Infinite: the server ends it (answer, expiry, withdrawal sends
-- false), a local safety timer drops it a few seconds after the deadline. The keys are handled here.

local CP = POL.module("callout", { offer = nil, deadline = 0 })
local PIN = "pol.callout"
local expireTimer

local KINDS = { phone = "police_system.callouts.kind_phone", scene = "police_system.callouts.kind_scene",
                agency = "police_system.callouts.kind_agency" }

local function uic()
    local res = getResourceFromName("ui_core")
    return res and getResourceState(res) == "running" and exports.ui_core or nil
end

local function safe(s) return (tostring(s or ""):gsub("#(%x%x%x%x%x%x)", "# %1")) end

local function opts(o, left)
    local head = L.upper(L("police_system.callouts.offer_header", { id = o.id }))
    if KINDS[o.kind] then head = head .. " · " .. L.upper(L(KINDS[o.kind])) end
    head = head .. "  ·  P" .. tostring(o.priority or 2)
    local desc = safe(o.description)
    local where = "#8C9EBE" .. safe(o.zone) .. "  ·  " .. L("police_system.callouts.distance", { m = o.distance or 0 })
    desc = desc ~= "" and (desc .. "\n" .. where) or where
    return {
        id = PIN,
        title = head,
        subtitle = safe(o.title),
        description = desc,
        hint = "#40C86EY  #E1E8F5" .. L("police_system.callouts.accept") .. "#8C9EBE     ·     #EB4040N  #E1E8F5"
            .. L("police_system.callouts.decline"),
        accent = o.priority == 1 and "#EB4040" or "#468CFF",
        infinite = true,
        countdown = left,
        countdownTotal = (o.total or 30) * 1000,
        silent = true,
    }
end

local function show(o)
    CP.offer = o or nil
    if isTimer(expireTimer) then killTimer(expireTimer) end
    expireTimer = nil
    local ui = uic()
    if CP.offer then
        local left = (o.left or o.total or 30) * 1000
        CP.deadline = getTickCount() + left
        if ui then ui:addPinnedNotification(opts(o, left)) end
        local offer = CP.offer
        expireTimer = setTimer(function() if CP.offer == offer then show(nil) end end, left + 3000, 1)
        playSoundFrontEnd(5)
    elseif ui then
        ui:removePinnedNotification(PIN)
    end
end

POL.handle("callout:offer", show)
POL.on("unit", function(u) if not u then show(nil) end end)
POL.on("right", function(on) if not on then show(nil) end end)

-- language change: the same offer again in the new language (no sound, the countdown goes on)
L.onChange(function()
    local o, ui = CP.offer, uic()
    if not o or not ui then return end
    local left = math.max(0, CP.deadline - getTickCount())
    ui:updatePinnedNotification(PIN, opts(o, left))
end)

POL.key("callout", function(button, press)
    local o = CP.offer
    if not o or (button ~= "y" and button ~= "n") then return false end
    if press then
        POL.send("callout:answer", o.id, button == "y")
        show(nil)
    end
    return true
end, 90)
