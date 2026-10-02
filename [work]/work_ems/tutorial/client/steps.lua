-- Client side of the EMS tutorial: the texts of every step and the sub-steps the client drives
-- itself (tablet explanation through med_erm's tutorial mode, examination panel highlights
-- through medsys' panel layout). The server owns the session (server/session.lua).

local T = {
    active = false,
    step = nil,          -- server step
    sub = 1,             -- sub-step of the tablet / examine steps
    vehicle = nil,
    stretcher = { state = "none" },
    games = {}, running = false, lastGame = nil,
    note = nil, noteColor = nil,
}

local STEP_LABELS = {
    tablet = "Step 1 / 6  ·  EMS tablet",
    examine = "Step 2 / 6  ·  Examination",
    minigames = "Step 3 / 6  ·  Treatments",
    stretcher = "Step 4 / 6  ·  Stretcher",
    transfer = "Step 5 / 6  ·  Transport",
    handover = "Step 5 / 6  ·  Hospital handover",
    done = "Step 6 / 6  ·  Finished",
}

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function tablet(fn, ...)
    if isRunning("med_erm") then return exports.med_erm[fn](exports.med_erm, ...) end
end

local function tabletOpen()
    return isRunning("med_erm") and exports.med_erm:isTabletTutorial() and T.tabletOpen == true
end

local function panelOpen()
    return isRunning("medsys") and exports.medsys:isExaminationOpen() == true
end

local function panelRect(key)
    if not isRunning("medsys") then return nil end
    local layout = exports.medsys:getExaminationPanelLayout()
    return layout and layout[key] or nil
end

local function bandageRect()
    if not isRunning("medsys") then return nil end
    local layout = exports.medsys:getExaminationPanelLayout()
    for _, b in ipairs(layout and layout.buttonList or {}) do
        if b.action == "bandage" then return { b.x, b.y, b.w, b.h } end
    end
end

local refresh -- forward
local function nextSub()
    T.sub = T.sub + 1
    T.note = nil
    refresh()
end

local function serverNext()
    triggerServerEvent("ems:tut:next", resourceRoot, T.step)
end

---------------------------------------------------------------- step 1: tablet

local TABLET_KEY = "J"

local TABLET = {
    { text = "You are sitting in your ambulance. Every EMS unit works with the EMS tablet: "
          .. "you sign in on it, get your cases and talk to the dispatchers.\n\nPress " .. TABLET_KEY .. " to open the tablet.",
      wait = "tablet:open" },
    { text = "This is the sign-in screen. Pick a unit type: SOLO (single responder), DOC (physician), "
          .. "BLS / ALS (basic / advanced life support ambulance) or HELI (air ambulance). An ambulance crew "
          .. "is usually BLS or ALS.\n\nYou can also set a unit number and add the crew mates sitting near you. "
          .. "Then press Sign In.",
      wait = "tablet:signIn", tablet = true },
    { text = "You are signed in. The header shows your callsign, unit type, plate and status "
          .. "(green = Available).\n\nThe Home page shows your shift and your active case. Cases are assigned to "
          .. "free units by the dispatchers, or automatically by the system.",
      next = true, tablet = true,
      leave = function()
          tablet("setTabletTutorialCase", TUTORIAL.CASE)
      end },
    { text = "A case was assigned to you - that was the alert sound.\n\nOpen it: click the case card on the "
          .. "Home page, or open the menu (top right) and choose Active Case.",
      wait = "tablet:page:case", tablet = true },
    { text = "The Active Case page: the priority (P1 is the most urgent, P4 the least), the title, the location "
          .. "and distance, the caller and the description. On a real case a yellow route on the GPS leads you "
          .. "to the scene.\n\nStart Response means lights & siren and status En Route. It switches on by itself "
          .. "when you drive off (to the scene or away from it), but you can also press it - do it now.",
      wait = "tablet:caseAction:start", tablet = true },
    { text = "The rest is automatic: your status becomes On Scene when you arrive, and Handover when you park "
          .. "in a hospital's ambulance bay with the patient.\n\nLeave Case releases your unit while another unit "
          .. "stays on the case. Close Case ends a false call (a reason is needed). End Shift is in the menu.",
      next = true, tablet = true,
      leave = function()
          tablet("setTabletTutorialUnit", { status = "onscene", reachedScene = true, responding = false })
          tablet("addTabletTutorialMessage", "The caller says the patient is waiting right next to your ambulance.", "case")
      end },
    { text = "You got a message. Messages has two channels: Dispatch (your unit and the dispatchers) and "
          .. "Case (every unit on the case and the dispatchers).\n\nOpen the menu and choose Messages.",
      wait = "tablet:page:messages", tablet = true },
    { text = "Here you read and send messages. Switch between the two channels at the top, and write with the "
          .. "button at the bottom. Try it if you like.",
      next = true, tablet = true },
    { text = "You arrived at the scene, so your status is On Scene.\n\nClose the tablet with " .. TABLET_KEY .. ".",
      wait = "tablet:close",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 2: examination

local EXAMINE = {
    { text = "Your patient is standing next to the ambulance. Get out (F) and walk to them.\n\n"
          .. "Look at the patient and press X to open the world menu (Q / E switch between nearby menus), "
          .. "then press 1: Examine patient.",
      wait = "panel:open" },
    { text = "This is the examination panel. The top bar is the consciousness: Stable, Dazed, Unconscious, "
          .. "Clinical death or Dead.",
      next = true, panel = "consciousness" },
    { text = "The vital signs: heart rate with the ECG, blood pressure, oxygen saturation (SpO2) and bleeding "
          .. "with the skin colour. Green is normal; yellow, orange and red are worse. They change live.",
      next = true, panel = "vitals" },
    { text = "IV access, airway and pain. Medicines can only be given through an IV access.",
      next = true, panel = "status" },
    { text = "The injuries: their severity and whether they are treated. This patient has a minor burn.",
      next = true, panel = "injuries" },
    { text = "The treatments. A grey button cannot be used now - hover it to see why.\n\n"
          .. "Bandage: wounds, burns, fractures  ·  CPR: stopped heart  ·  IV access  ·  Intubate: unconscious "
          .. "patient  ·  Medication  ·  Transport: calls a vehicle for a stable or dead patient (off in the tutorial).",
      next = true, panel = "buttons" },
    { text = "Dress the burn: press Bandage.\n\nPress the matching arrow key when an arrow reaches the target.",
      wait = "bandage:ok", panel = "bandage" },
    { text = "Well done, the burn is dressed - the injury list shows it as Dressed.\n\nClose the panel "
          .. "(the X in its corner, or Backspace) whenever you like.",
      next = true,
      leave = function() serverNext() end },
}
local EXAMINE_DONE = #EXAMINE

---------------------------------------------------------------- card builders

local function successTotal()
    local n = 0
    for _, g in pairs(T.games) do n = n + (g.success or 0) end
    return n
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = STEP_LABELS[step], title = def.title, text = def.text, note = T.note, noteColor = T.noteColor }

    local blocked
    if def.tablet and not tabletOpen() then
        blocked = "Press " .. TABLET_KEY .. " to open the tablet again."
    elseif def.panel and not panelOpen() then
        blocked = "Open the examination panel again: look at the patient, press X, then 1."
    end
    if blocked then
        spec.note, spec.noteColor = blocked, Card.colors.bad
    end

    if def.next then
        spec.buttons = { { label = "Next", primary = true, disabled = blocked ~= nil, fn = function()
            if def.leave then def.leave() end
            nextSub()
        end } }
    end

    local rect
    if def.panel == "bandage" then rect = bandageRect() elseif def.panel then rect = panelRect(def.panel) end
    Card.highlight(not blocked and rect or nil)
    return spec
end

local function gamesCard()
    local rows = {}
    for _, g in ipairs(TUTORIAL.GAMES) do
        local stats = T.games[g.id]
        local status, color
        if stats then
            status = ("%d / %d successful"):format(stats.success or 0, stats.played or 0)
            color = (stats.success or 0) > 0 and Card.colors.good or Card.colors.muted
        end
        rows[#rows + 1] = {
            title = g.label, desc = g.desc, status = status, statusColor = color,
            button = { label = "Practice", disabled = T.running ~= false, fn = function()
                T.note = nil
                triggerServerEvent("ems:tut:game", resourceRoot, g.id)
            end },
        }
    end
    local need = TUTORIAL.MIN_GAMES
    local done = successTotal()
    return {
        step = STEP_LABELS.minigames,
        title = "Practice the treatments",
        text = "These minigames are the treatments of the examination panel. Here they run without a patient: "
            .. "play any of them as many times as you like.\n\n"
            .. ("Complete at least %d successfully to continue (%d so far)."):format(need, math.min(done, need)),
        note = T.note, noteColor = T.noteColor,
        rows = rows,
        buttons = { { label = "Continue", primary = true, disabled = done < need or T.running ~= false,
            fn = serverNext } },
        modal = true,
    }
end

local function stretcherCard()
    local st = T.stretcher
    local text
    if st.patient and st.state ~= "stowed" then
        text = "The patient is on the stretcher. Choose Push stretcher, walk back to the rear doors of the "
            .. "ambulance and choose Load into ambulance."
    elseif st.state == "ground" or st.state == "pushing" then
        text = "The stretcher is out. Bring it next to the patient if needed (Push stretcher, then Release "
            .. "stretcher to put it down).\n\nThen choose Place patient on stretcher in its menu and click the patient."
    elseif st.state == "moving" then
        text = T.lastStretcherText or "..."
    else
        text = "Now the stretcher. A second person is waiting behind the ambulance. They are not injured and only "
            .. "need a ride.\n\nGo to the rear doors of the ambulance, press X and choose Take out stretcher."
    end
    T.lastStretcherText = text
    return { step = STEP_LABELS.stretcher, title = "Load the patient", text = text }
end

local function handoverCard()
    local st = T.stretcher
    local text
    if st.patient and st.state ~= "stowed" then
        text = "Push the stretcher into the blue Patient Handover marker and stay in it for 5 seconds."
    elseif st.state == "moving" then
        text = T.lastHandoverText or "..."
    else
        text = "You arrived at the hospital. On a real case, parking in a yellow ambulance bay with the patient "
            .. "starts the Handover status.\n\nGet out, go to the rear doors and take out the stretcher - "
            .. "the patient comes out on it."
    end
    T.lastHandoverText = text
    return { step = STEP_LABELS.handover, title = "Hand over the patient", text = text }
end

local function doneCard()
    return {
        step = STEP_LABELS.done,
        title = "Tutorial complete",
        text = "You know the basics now:\n\n"
            .. "·  Go on duty, take an ambulance at the vehicle point and sign in on the tablet (" .. TABLET_KEY .. ").\n"
            .. "·  Cases come from the dispatchers or the automatic dispatcher. Press Start Response and follow the route.\n"
            .. "·  Examine the patient (X, 1) and treat what the panel shows.\n"
            .. "·  Load the patient with the stretcher, park in a hospital's ambulance bay and push the stretcher "
            .. "into the handover marker.\n\n"
            .. "You can watch this tutorial again any time with /" .. TUTORIAL.COMMAND .. ".",
        buttons = { { label = "Finish", primary = true, fn = serverNext } },
        modal = true, noSkip = true,
    }
end

function refresh()
    if not T.active then return end
    Card.highlight(nil)
    local spec
    if T.step == "tablet" then
        spec = subCard(TABLET, "tablet")
    elseif T.step == "examine" then
        spec = subCard(EXAMINE, "examine")
    elseif T.step == "minigames" then
        spec = gamesCard()
    elseif T.step == "stretcher" then
        spec = stretcherCard()
    elseif T.step == "transfer" then
        spec = { step = STEP_LABELS.transfer, title = "Off to the hospital",
                 text = "The patient is in the ambulance. Driving to the hospital...", noSkip = true }
    elseif T.step == "handover" then
        spec = handoverCard()
    elseif T.step == "done" then
        spec = doneCard()
    end
    if spec then Card.show(spec) else Card.hide() end
    Card.setHidden(T.running ~= false and T.running ~= nil)
end

-- Something happened that a "wait" sub-step may be waiting for
local function signal(name)
    if not T.active then return end
    local list = T.step == "tablet" and TABLET or T.step == "examine" and EXAMINE
    if not list then return refresh() end
    local def = list[T.sub]
    if def and def.wait == name then
        if def.leave then def.leave() end
        return nextSub()
    end
    refresh()
end

-- The panel / tablet state changes the notes and highlights: keep the card current
setTimer(function()
    if T.active and (T.step == "tablet" or T.step == "examine") then refresh() end
end, 250, 0)

---------------------------------------------------------------- server events

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, fn)
end

handle("ems:tut:offer", function()
    if T.active then return end
    Card.onSkip = nil
    Card.show({
        title = "EMS tutorial",
        text = "Is this your first shift? The tutorial shows you the EMS tablet, the examination panel, "
            .. "the treatment minigames, the stretcher and the hospital handover. It takes about 10 minutes "
            .. "in a private copy of the world.\n\nIt is not required: you can skip it now and start it any "
            .. "time later with /" .. TUTORIAL.COMMAND .. ".",
        buttons = {
            { label = "Skip", fn = function()
                Card.hide()
                triggerServerEvent("ems:tut:answer", resourceRoot, false)
            end },
            { label = "Start tutorial", primary = true, fn = function()
                Card.hide()
                triggerServerEvent("ems:tut:answer", resourceRoot, true)
            end },
        },
        modal = true, noSkip = true,
    })
end)

local function toggleCursor() Card.toggleCursor() end

handle("ems:tut:begin", function(vehicle)
    T.active, T.vehicle, T.step, T.sub = true, vehicle, nil, 1
    T.games, T.running, T.note, T.tabletOpen = {}, false, nil, false
    T.stretcher = { state = "none" }
    tablet("startTabletTutorial")
    bindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("ems:tut:skip", resourceRoot) end
end)

handle("ems:tut:step", function(step)
    T.step, T.sub, T.note = step, 1, nil
    if step == "examine" then T.tabletOpen = false end
    refresh()
end)

handle("ems:tut:info", function(kind, data)
    if kind == "bandage" then
        if data then
            T.sub = EXAMINE_DONE
            T.note = nil
        else
            T.note, T.noteColor = "The bandage did not hold. The panel is open again - press Bandage once more.", Card.colors.bad
        end
        refresh()
    elseif kind == "stretcher" then
        T.stretcher = data
        refresh()
    elseif kind == "gameError" then
        T.note, T.noteColor = tostring(data), Card.colors.bad
        refresh()
    end
end)

handle("ems:tut:games", function(games, running, lastId, lastSuccess)
    T.games, T.running = games or {}, running or false
    if lastId then
        local label = lastId
        for _, g in ipairs(TUTORIAL.GAMES) do if g.id == lastId then label = g.label end end
        if lastSuccess then
            T.note, T.noteColor = label .. ": success!", Card.colors.good
        else
            T.note, T.noteColor = label .. ": not this time - try again.", Card.colors.bad
        end
    end
    refresh()
end)

handle("ems:tut:end", function()
    T.active, T.step = false, nil
    unbindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    tablet("stopTabletTutorial")
    Card.hide()
end)

---------------------------------------------------------------- other resources

addEvent("onClientErmTabletTutorial")
addEventHandler("onClientErmTabletTutorial", localPlayer, function(action, arg)
    if action == "open" then
        T.tabletOpen = true
        signal("tablet:open")
    elseif action == "close" then
        T.tabletOpen = false
        signal("tablet:close")
    elseif action == "page" then
        signal("tablet:page:" .. tostring(arg))
    elseif action == "caseAction" then
        signal("tablet:caseAction:" .. tostring(arg))
    else
        signal("tablet:" .. tostring(action))
    end
end)

addEvent("onClientMedicPanel")
addEventHandler("onClientMedicPanel", localPlayer, function(open)
    if open then signal("panel:open") else refresh() end
end)

-- tutorial patients cannot be hurt
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "ems.tutorialPed") then cancelEvent() end
end)

-- med_erm restarted: its tutorial mode is gone, switch it on again
addEventHandler("onClientResourceStart", root, function(res)
    if T.active and getResourceName(res) == "med_erm" then tablet("startTabletTutorial") end
end)
