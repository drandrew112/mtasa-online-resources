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

------------------------------------------------------------------------ prisoner transport offer (2026-11-12)
-- Another unit asks for a prisoner transport (transport.lua): the same highlighted pinned notification with Y / N.
-- The server never shows a call offer and a transport offer to a unit at the same time.

local TPIN = "pol.transport.offer"
CP.transport, CP.tDeadline = nil, 0
local tTimer

local function topts(o, left)
    local where = "#8C9EBE" .. safe(o.zone) .. "  ·  " .. L("police_system.callouts.distance", { m = o.distance or 0 })
    return {
        id = TPIN,
        title = L.upper(L("police_system.transport.offer_header", { callsign = o.callsign })),
        subtitle = safe(o.name),
        description = L("police_system.transport.offer_text", { callsign = o.callsign }) .. "\n" .. where,
        hint = "#40C86EY  #E1E8F5" .. L("police_system.callouts.accept") .. "#8C9EBE     ·     #EB4040N  #E1E8F5"
            .. L("police_system.callouts.decline"),
        accent = "#F58C32",
        infinite = true,
        countdown = left,
        countdownTotal = (o.total or 20) * 1000,
        silent = true,
    }
end

local function showTransport(o)
    CP.transport = o or nil
    if isTimer(tTimer) then killTimer(tTimer) end
    tTimer = nil
    local ui = uic()
    if CP.transport then
        local left = (o.left or o.total or 20) * 1000
        CP.tDeadline = getTickCount() + left
        if ui then ui:addPinnedNotification(topts(o, left)) end
        local offer = CP.transport
        tTimer = setTimer(function() if CP.transport == offer then showTransport(nil) end end, left + 3000, 1)
        playSoundFrontEnd(5)
    elseif ui then
        ui:removePinnedNotification(TPIN)
    end
end

POL.handle("transport:offer", showTransport)
POL.on("unit", function(u) if not u then showTransport(nil) end end)
POL.on("right", function(on) if not on then showTransport(nil) end end)

L.onChange(function()
    local o, ui = CP.transport, uic()
    if not o or not ui then return end
    ui:updatePinnedNotification(TPIN, topts(o, math.max(0, CP.tDeadline - getTickCount())))
end)

POL.key("callout", function(button, press)
    if button ~= "y" and button ~= "n" then return false end
    local o = CP.offer
    if o then
        if press then
            POL.send("callout:answer", o.id, button == "y")
            show(nil)
        end
        return true
    end
    if CP.transport then
        if press then
            POL.send("transport:answer", button == "y")
            showTransport(nil)
        end
        return true
    end
    return false
end, 90)
