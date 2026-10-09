-- Client side of the EMS tutorial: the texts of every step and the sub-steps the client drives
-- itself (tablet explanation through med_erm's tutorial mode, the equipment through med_bag's
-- hand data and contents window, examination panel highlights through medsys' panel layout).
-- The server owns the session (server/session.lua).

local T = {
    active = false,
    step = nil,          -- server step
    sub = 1,             -- sub-step of the tablet / equipment / examine / treat steps
    vehicle = nil,
    equipment = false,   -- med_bag runs: the equipment is taught and checked
    world = { stretcher = { state = "none" } },   -- polled by the server (worldInfo)
    done = {},           -- treatments done on the patient (server)
    games = {}, running = false, practice = false,
    note = nil, noteColor = nil,
}

local STEP_LABELS = {
    tablet = "Step 1 / 8  ·  EMS tablet",
    equipment = "Step 2 / 8  ·  Equipment",
    examine = "Step 3 / 8  ·  Examination",
    treat = "Step 4 / 8  ·  Treatment",
    stretcher = "Step 5 / 8  ·  Stretcher",
    transfer = "Step 6 / 8  ·  Transport",
    handover = "Step 6 / 8  ·  Hospital handover",
    restock = "Step 7 / 8  ·  Restock",
    done = "Step 8 / 8  ·  Finished",
}

local ITEM_STATE = {
    stowed = "in the ambulance", carried = "in your hands", ground = "on the ground",
    stretcher = "on the stretcher", none = "-",
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

local function panelLayout()
    return isRunning("medsys") and exports.medsys:getExaminationPanelLayout() or nil
end

local function panelRect(key)
    local layout = panelLayout()
    return layout and layout[key] or nil
end

local function actionRect(action)
    local layout = panelLayout()
    for _, b in ipairs(layout and layout.buttonList or {}) do
        if b.action == action then return { b.x, b.y, b.w, b.h } end
    end
end

-- The medicine card while the medication grid is open, otherwise the Medication button
local function drugRect(id)
    local layout = panelLayout()
    for _, card in ipairs(layout and layout.drugCards or {}) do
        if card.id == id then return { card.x, card.y, card.w, card.h } end
    end
    return actionRect("medication")
end

-- med_bag: what the player carries ({ bag = model, monitor = model } or nil)
local function carrying(kind)
    local hands = getElementData(localPlayer, "medbag.hands")
    return type(hands) == "table" and hands[kind] ~= nil
end

local function itemState(kind)
    local items = T.world.items
    return items and items[kind] and items[kind].state or "none"
end

local function itemsLine()
    if not T.world.items then return nil end
    return ("Medical bag: %s  ·  Monitor: %s"):format(ITEM_STATE[itemState("bag")] or "-",
        ITEM_STATE[itemState("monitor")] or "-")
end

local function noEquipment() return not T.equipment end

local refresh -- forward
local STEP_SUBS -- step -> its sub-step list (the steps the client drives)

local function currentList()
    return T.step and STEP_SUBS and STEP_SUBS[T.step]
end

-- Moves to the next sub-step, past the ones that do not apply (skip)
local function nextSub()
    local list = currentList()
    T.sub = T.sub + 1
    while list and list[T.sub] and list[T.sub].skip and list[T.sub].skip() do T.sub = T.sub + 1 end
    T.note = nil
    refresh()
end

local function firstSub()
    local list = currentList()
    T.sub = 1
    while list and list[T.sub] and list[T.sub].skip and list[T.sub].skip() do T.sub = T.sub + 1 end
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

---------------------------------------------------------------- step 2: equipment (med_bag)

local EQUIPMENT = {
    { text = "Your patient is standing next to the ambulance. Before you go to them, take your equipment: "
          .. "with bare hands you can only examine.\n\nGet out (F) and go to the side door on the right side of "
          .. "the ambulance. Press X there to open the Ambulance equipment menu and choose Check contents.",
      wait = "bag:contents" },
    { text = "The contents of the medical bag (the window on the right): IV kits, the oxygen cylinder and every "
          .. "medicine as left / full.\n\nThey run out as you use them: one IV kit per attempt (a failed one too), "
          .. "one dose per medicine, and the oxygen drains while a mask or a tube is on. You restock the bag "
          .. "in a hospital's ambulance bay - you will do it at the end of the tutorial.",
      next = true },
    { text = "Now take the equipment: in the same menu choose Take both. The medical bag goes into your left "
          .. "hand, the monitor / defibrillator into your right.",
      check = function() return carrying("bag") and carrying("monitor") end },
    { text = "The panel on the right shows what you carry and the bag's IV kits and oxygen. While carrying you "
          .. "cannot jump or get into another vehicle; getting into your own ambulance puts everything back.\n\n"
          .. "Carry them to the patient: they work within 4 m. Never leave them at a scene - when the ambulance "
          .. "drives away without them, the crew is warned.\n\nAt the patient press X, then 1: Examine patient.",
      wait = "panel:open",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 3: examination

local EXAMINE = {
    { text = "Look at the patient and press X to open the world menu (Q / E switch between nearby menus), "
          .. "then press 1: Examine patient.",
      check = panelOpen },
    { text = "This is the examination panel. The top bar is the consciousness: Stable, Dazed, Unconscious, "
          .. "Clinical death or Dead. In clinical death a countdown runs next to it.",
      next = true, panel = "consciousness" },
    { text = "These chips show the equipment within reach (4 m) of the patient: the MONITOR, the BAG and the "
          .. "oxygen left in it. Green = here, grey = missing.\n\nWithout equipment you can still examine, do a "
          .. "Neuro exam, CPR and request transport - every other button is grey, hover it to see why.",
      next = true, panel = "equipment", skip = noEquipment },
    { text = "Without the monitor you only see what you can feel and see: the pulse (heart rate), the bleeding "
          .. "and the skin (pale = blood loss, blue = too little oxygen).\n\nGreen is normal; yellow, orange and "
          .. "red are worse. The values change live.",
      next = true, panel = "vitals" },
    { text = "IV access, airway and pain. Most medicines need an IV access; the ones marked oral do not.",
      next = true, panel = "status" },
    { text = "The injuries: their severity and whether they are treated. This patient has a minor burn and a "
          .. "fracture. You will treat both in the next step.",
      next = true, panel = "injuries" },
    { text = "The treatments, in rows. A grey button cannot be used now - hover it to see why.\n\n"
          .. "AB (airway, breathing): Intubate - after Ketamine, then Rocuronium (or in cardiac arrest)  ·  "
          .. "O2 mask.\nCD (circulation): Bandage - wounds, burns  ·  Splint - fractures  ·  "
          .. "CPR - stopped heart  ·  IV access  ·  Medication - a list of medicines, point at one to read what it does.\n"
          .. "Transport: a vehicle for a stable, intubated or dead patient (off in the tutorial).",
      next = true, panel = "buttons" },
    { text = "Blood pressure, oxygen level (SpO2) and the heart rhythm (ECG) need the monitor.\n\n"
          .. "Click Attach monitor / defibrillator in the heart rate tile.",
      check = function() return panelRect("lifepak") ~= nil end, panel = "monitorButton" },
    { text = "The Lifepak 15 monitor. Top: the heart rate with the ECG and the name of the rhythm under it - "
          .. "you do not have to read the ECG. Bottom: SpO2 with its wave and the blood pressure (NIBP: the "
          .. "upper value big, the lower one under it, the mean in brackets).\n\nThe monitor beeps on every heart beat. "
          .. "It stays connected up to 6 m: do not walk away with it.",
      next = true, panel = "lifepakScreen" },
    { text = "The defibrillator. CHARGE (200 J), then SHOCK when it flashes. Only two rhythms need a shock: VF and "
          .. "pulseless VT. ANALYZE checks an unresponsive patient for you and charges if a shock is needed. SYNC is "
          .. "for VT with a pulse, SOUND mutes the beep and the alarm.\n\n"
          .. "Never shock a patient with a normal rhythm - it stops the heart. Do not shock this patient.",
      next = true, panel = "lifepakKeypad",
      leave = function() serverNext() end },
}

---------------------------------------------------------------- step 4: treatment

local function treated(key) return function() return T.done[key] == true end end

local TREAT = {
    { text = "Treat the injuries. Start with the burn: press Bandage.\n\n"
          .. "Press the matching arrow key when an arrow reaches the target.",
      check = treated("bandage"), panel = "action:bandage" },
    { text = "The burn is dressed. Now the fracture: press Splint.\n\n"
          .. "A needle swings across a gauge: press SPACE while it is inside the centre window to tighten each "
          .. "wrap. A miss is not a failure, wait for the next pass.",
      check = treated("splint"), panel = "action:splint" },
    { text = "The fracture still hurts a lot - the pain needs a medicine through a vein. First: press IV access.\n\n"
          .. "Push the needle into the vein, then pull it back. Every attempt uses one IV kit from the bag.",
      check = treated("iv"), panel = "action:iv" },
    { text = "Now press Medication and choose Fentanyl (a strong painkiller).\n\n"
          .. "The number on each medicine card is the doses left in the bag (x3 = three). A medicine at 0 cannot "
          .. "be given until you restock.",
      check = treated("painkiller"), panel = "drug:" .. TUTORIAL.PAINKILLER },
    { text = "Last: press O2 mask.\n\nThe O2 chip in the header drops while the mask is on - also in the "
          .. "ambulance. If the bag is farther than 6 m from the patient or the cylinder runs empty, the mask "
          .. "comes off (an intubated patient keeps the tube, but it does nothing without oxygen).",
      check = treated("oxygen"), panel = "action:oxygen" },
    { text = "Well done: the burn is dressed, the leg splinted, the pain treated and the patient gets oxygen.\n\n"
          .. "Close the panel (the X in its corner, or Backspace) whenever you like. The patient goes to the "
          .. "hospital next.",
      next = true,
      leave = function() serverNext() end },
}

STEP_SUBS = { tablet = TABLET, equipment = EQUIPMENT, examine = EXAMINE, treat = TREAT }

---------------------------------------------------------------- card builders

local function subRect(panel)
    if not panel then return nil end
    local action = panel:match("^action:(.+)$")
    if action then return actionRect(action) end
    local drug = panel:match("^drug:(.+)$")
    if drug then return drugRect(drug) end
    return panelRect(panel)
end

local function subCard(list, step)
    local def = list[T.sub]
    if not def then return nil end
    local spec = { step = STEP_LABELS[step], title = def.title, text = def.text, note = T.note, noteColor = T.noteColor }
    -- the Lifepak window opens left of the panel, where the card would cover it
    if (step == "examine" or step == "treat") and panelOpen() then spec.side = "right" end

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
        -- the tablet and the panel show the cursor themselves, otherwise the card does
        spec.modal = not tabletOpen() and not panelOpen()
        spec.buttons = { { label = "Next", primary = true, disabled = blocked ~= nil, fn = function()
            if def.leave then def.leave() end
            nextSub()
        end } }
    end

    Card.highlight(not blocked and subRect(def.panel) or nil)
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
    return {
        step = STEP_LABELS.done,
        title = "Practice the minigames",
        text = "Every treatment of the panel is a minigame. Here they run without a patient: play any of them "
            .. "as many times as you like. CPR and intubation are worth a try - you did not need them today.",
        note = T.note, noteColor = T.noteColor,
        rows = rows,
        buttons = { { label = "Back", primary = true, disabled = T.running ~= false, fn = function()
            T.practice, T.note = false, nil
            refresh()
        end } },
        modal = true, noSkip = true,
    }
end

-- The item that is still out of the ambulance, in words ("the medical bag" / "the monitor" / both)
local function itemsOutside()
    local out = {}
    if itemState("bag") ~= "stowed" then out[#out + 1] = "the medical bag" end
    if itemState("monitor") ~= "stowed" then out[#out + 1] = "the monitor" end
    return #out > 0 and table.concat(out, " and ") or nil
end

local function stretcherCard()
    local st = T.world.stretcher
    local text
    if st.loaded and st.state == "stowed" then
        text = "The patient is in the ambulance, but " .. (itemsOutside() or "something")
            .. " is still outside. Bring it back: go to the side door, press X and put it back "
            .. "(or simply get into the ambulance while holding it)."
    elseif st.patient and st.state ~= "stowed" then
        text = "The patient is on the stretcher. Now the equipment: it rides on the side of the stretcher, so the "
            .. "oxygen and the monitor travel with the patient.\n\nIn the stretcher menu choose Put medical bag on "
            .. "stretcher and Put monitor on stretcher (the items must lie within 2 m of it). Then Push stretcher "
            .. "to the rear doors and choose Load into ambulance."
    elseif st.state == "ground" or st.state == "pushing" then
        text = "The stretcher is out. Bring it next to the patient if needed (Push stretcher, then Release "
            .. "stretcher to put it down).\n\nThen choose Place patient on stretcher in its menu and click the patient."
    elseif st.state == "moving" then
        text = T.lastStretcherText or "..."
    else
        text = "Your patient is treated and goes to the hospital. Your equipment lies next to them - a treatment "
            .. "put it down there.\n\nGo to the rear doors of the ambulance, press X and choose Take out stretcher."
    end
    if not T.equipment and st.patient and st.state ~= "stowed" then
        text = "The patient is on the stretcher. Choose Push stretcher, walk back to the rear doors of the "
            .. "ambulance and choose Load into ambulance."
    end
    T.lastStretcherText = text
    return { step = STEP_LABELS.stretcher, title = "Load the patient", text = text, note = itemsLine() }
end

local function handoverCard()
    local st = T.world.stretcher
    local text
    if st.patient and st.state ~= "stowed" then
        text = "Push the stretcher into the blue Patient Handover marker and stay in it for 5 seconds."
    elseif st.state == "moving" then
        text = T.lastHandoverText or "..."
    else
        text = "You arrived at the hospital. On a real case, parking in a yellow ambulance bay with the patient "
            .. "starts the Handover status.\n\nGet out, go to the rear doors and take out the stretcher - "
            .. "the patient comes out on it."
        if T.equipment then
            text = text .. " The equipment that went in on the stretcher comes out with it: the oxygen and the "
                .. "monitor stay connected."
        end
    end
    T.lastHandoverText = text
    return { step = STEP_LABELS.handover, title = "Hand over the patient", text = text, note = itemsLine() }
end

local function restockCard()
    local st = T.world.stretcher
    local text
    if st.state ~= "stowed" then
        text = "The patient is handed over. The equipment stays on the stretcher (in a bay the ambulance shows "
            .. "EQUIPMENT MISSING while something is out).\n\nPush the empty stretcher back to the rear doors and "
            .. "choose Load into ambulance: the equipment on it goes back in."
    elseif itemsOutside() then
        text = "The stretcher is in, but " .. itemsOutside() .. " is still outside. Put it back at the side door "
            .. "(X, Put ... back)."
    else
        text = "Everything is back in the ambulance. You used an IV kit, a dose of Fentanyl and oxygen.\n\n"
            .. "Go to the side door, press X and choose Restock bag. It works only while the ambulance stands in "
            .. "a hospital's ambulance bay; stand still for a few seconds. Restocking is free."
    end
    return { step = STEP_LABELS.restock, title = "Restock the bag", text = text, note = itemsLine() }
end

local function doneCard()
    local lines = {
        "·  Go on duty, take an ambulance at the vehicle point and sign in on the tablet (" .. TABLET_KEY .. ").",
        "·  Cases come from the dispatchers or the automatic dispatcher. Press Start Response and follow the route.",
    }
    if T.equipment then
        lines[#lines + 1] = "·  Take the bag and the monitor at the side door. Keep them within 4 m of the patient, "
            .. "and never leave them at the scene."
    end
    lines[#lines + 1] = "·  Examine the patient (X, 1), attach the monitor, and treat what the panel shows: bandage, "
        .. "splint, IV access, medicines, oxygen. Shock only VF and pulseless VT."
    lines[#lines + 1] = "·  Load the patient with the stretcher, park in a hospital's ambulance bay and push the "
        .. "stretcher into the handover marker."
    if T.equipment then
        lines[#lines + 1] = "·  Load the empty stretcher and restock the bag in the bay."
    end
    return {
        step = STEP_LABELS.done,
        title = "Tutorial complete",
        text = "You know the basics now:\n\n" .. table.concat(lines, "\n") .. "\n\n"
            .. "You can practice the minigames here, or watch this tutorial again any time with /"
            .. TUTORIAL.COMMAND .. ".",
        note = T.note, noteColor = T.noteColor,
        buttons = {
            { label = "Practice minigames", fn = function()
                T.practice, T.note = true, nil
                refresh()
            end },
            { label = "Finish", primary = true, fn = serverNext },
        },
        modal = true, noSkip = true,
    }
end

function refresh()
    if not T.active then return end
    Card.highlight(nil)
    local spec
    local list = currentList()
    if list then
        spec = subCard(list, T.step)
    elseif T.step == "stretcher" then
        spec = stretcherCard()
    elseif T.step == "transfer" then
        spec = { step = STEP_LABELS.transfer, title = "Off to the hospital",
                 text = "The patient is in the ambulance. Driving to the hospital...", noSkip = true }
    elseif T.step == "handover" then
        spec = handoverCard()
    elseif T.step == "restock" then
        spec = restockCard()
    elseif T.step == "done" then
        spec = T.practice and gamesCard() or doneCard()
    end
    if spec then Card.show(spec) else Card.hide() end
    Card.setHidden(T.running ~= false and T.running ~= nil)
end

-- Something happened that a "wait" sub-step may be waiting for
local function signal(name)
    if not T.active then return end
    local list = currentList()
    local def = list and list[T.sub]
    if def and def.wait == name then
        if def.leave then def.leave() end
        return nextSub()
    end
    refresh()
end

-- The panel / tablet / hands state changes the notes and highlights: keep the card current, and move
-- on from a "check" sub-step once its condition holds (also when it was done before the step came)
setTimer(function()
    if not T.active then return end
    local list = currentList()
    if not list then return end
    local def = list[T.sub]
    if def and def.check and def.check() then
        if def.leave then def.leave() end
        return nextSub()
    end
    refresh()
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
        text = "Is this your first shift? The tutorial shows you the EMS tablet, your equipment, the examination "
            .. "panel and the monitor / defibrillator, the treatments, the stretcher, the hospital handover and "
            .. "restocking. It takes about 15 minutes in a private copy of the world.\n\nIt is not required: you "
            .. "can skip it now and start it any time later with /" .. TUTORIAL.COMMAND .. ".",
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

handle("ems:tut:begin", function(vehicle, equipment)
    T.active, T.vehicle, T.step, T.sub = true, vehicle, nil, 1
    T.equipment = equipment == true
    T.games, T.running, T.practice, T.note, T.tabletOpen = {}, false, false, nil, false
    T.world, T.done = { stretcher = { state = "none" } }, {}
    tablet("startTabletTutorial")
    bindKey(TUTORIAL.CURSOR_KEY, "down", toggleCursor)
    Card.onSkip = function() triggerServerEvent("ems:tut:skip", resourceRoot) end
end)

handle("ems:tut:step", function(step)
    T.step, T.note = step, nil
    if step == "examine" then T.tabletOpen, T.done = false, {} end
    firstSub()
    refresh()
end)

local TREATMENT_LABELS = {
    bandage = "The bandage did not hold", splint = "The splint did not hold", iv = "The IV access failed",
    painkiller = "The medicine was not given", oxygen = "The oxygen mask was not changed",
}

handle("ems:tut:info", function(kind, data)
    if kind == "treatment" then
        T.done = data.done or T.done
        if data.success then
            T.note = nil
        elseif TREATMENT_LABELS[data.key] then
            T.note, T.noteColor = TREATMENT_LABELS[data.key] .. ". The panel is open again - try once more.", Card.colors.bad
        end
        refresh()
    elseif kind == "world" then
        T.world = data
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

-- med_bag opened its contents window (Check contents in the side-door menu)
addEvent("bag:contents", true)
addEventHandler("bag:contents", root, function()
    signal("bag:contents")
end)

-- tutorial patients cannot be hurt
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "ems.tutorialPed") then cancelEvent() end
end)

-- med_erm restarted: its tutorial mode is gone, switch it on again
addEventHandler("onClientResourceStart", root, function(res)
    if T.active and getResourceName(res) == "med_erm" then tablet("startTabletTutorial") end
end)
