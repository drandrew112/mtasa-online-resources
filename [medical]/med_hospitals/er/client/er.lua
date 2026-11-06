-- ER client: notifications, the mandatory handover description, the stretcher point menu and the
-- small patient card above every ER patient (only for the hospital staff on duty).

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function notify(text, alert)
    if running("ui_core") then
        exports.ui_core:addNotification(L("med_hospitals.er.title"), text, alert == true)
    else
        outputChatBox(text)
    end
end

addEvent("hosp:er:notify", true)
addEventHandler("hosp:er:notify", resourceRoot, notify)

---------------------------------------------------------------- handover description

local askToken
addEvent("hosp:er:askHandoverText", true)
addEventHandler("hosp:er:askHandoverText", resourceRoot, function(maxLen)
    if not running("ui_core") or exports.ui_core:isTextInputOpen() then return end
    askToken = exports.ui_core:openTextInput(L("med_hospitals.er.handover_text_title"), maxLen or 300, "",
        L("med_hospitals.er.handover_text_placeholder"))
end)

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if not askToken or token ~= askToken then return end
    askToken = nil
    if text == false then return end -- closed: asked again a bit later while still in the marker
    triggerServerEvent("hosp:er:handoverText", resourceRoot, text or "")
end)

---------------------------------------------------------------- stretcher point

-- Inside the stretcher point marker E requests a stretcher (pushed at once) or hands back the empty
-- hospital stretcher being pushed. The server checks everything again.
local pointHospital = false
local lastKey = 0
addEvent("hosp:er:stretcherPoint", true)
addEventHandler("hosp:er:stretcherPoint", resourceRoot, function(hospitalId, inside)
    pointHospital = inside and hospitalId or false
end)

bindKey("e", "down", function()
    if not pointHospital or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    if getElementData(localPlayer, "textInputOpen") or getPedOccupiedVehicle(localPlayer) then return end
    if getTickCount() - lastKey < 800 then return end
    lastKey = getTickCount()
    triggerServerEvent("hosp:er:stretcherKey", resourceRoot, pointHospital)
end)
-- the E key hint is the marker card's hint line (er/server/menus.lua), no own screen text

---------------------------------------------------------------- case info

addEvent("hosp:er:caseInfo", true)
addEventHandler("hosp:er:caseInfo", resourceRoot, function(info)
    local lines = {
        ("%s%s"):format(info.name or L("med_hospitals.er.unknown_patient"), info.age and (", " .. info.age) or ""),
        L("med_hospitals.er.info_triage", { level = info.triage > 0 and info.triage or "-" }) .. " · " ..
            L("med_hospitals.er.info_treating", { name = info.treating or "-" }) .. " · " .. tostring(info.location or ""),
        info.arrival,
    }
    if info.text and info.text ~= "" then lines[#lines + 1] = "„" .. info.text .. "”" end
    notify(table.concat(lines, "\n"))
end)

---------------------------------------------------------------- patient cards

local TRIAGE_COLORS = { { 211, 57, 43 }, { 229, 130, 42 }, { 224, 180, 28 }, { 51, 148, 90 } }
local RANGE = 10       -- K30: on duty, 10 m, line of sight
local cards = {}       -- peds to draw (refreshed every 400 ms)
local fontB, font

local function isStaff() return getElementData(localPlayer, "hosp.staff") ~= false and getElementData(localPlayer, "hosp.staff") ~= nil end

local interactOn = false -- ui_interactobject running (its open menu hides the card of its ped)

local function collect()
    cards = {}
    interactOn = running("ui_interactobject")
    if not isStaff() then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        local v = getElementData(ped, "er.case")
        if type(v) == "table" then
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= RANGE then cards[#cards + 1] = ped end
        end
    end
end
setTimer(collect, 400, 0)

local function draw()
    if #cards == 0 then return end
    if not fontB then
        fontB = dxCreateFont(":med_hospitals/client/fonts/RobotoB.ttf", 10) or "default-bold"
        font = dxCreateFont(":med_hospitals/client/fonts/Roboto.ttf", 9) or "default"
    end
    local cx, cy, cz = getCameraMatrix()
    local menuPed
    if interactOn then
        local target, open = exports.ui_interactobject:getInteractTarget()
        if open then menuPed = target end
    end
    for _, ped in ipairs(cards) do
        if isElement(ped) and ped ~= menuPed and isElementOnScreen(ped) then
            local v = getElementData(ped, "er.case")
            -- the card sits on the middle of the body (spine bone), below the ui_interactobject
            -- menu, which is drawn above the ped
            local x, y, z = getPedBonePosition(ped, 3)
            if v and x and isLineOfSightClear(cx, cy, cz, x, y, z + 0.15, true, false, false, true, false, true, false) then
                local sx, sy = getScreenFromWorldPosition(x, y, z)
                if sx then
                    local name = v.name or L("med_hospitals.er.unknown_patient")
                    local sub = v.treating and L("med_hospitals.er.card_treating", { name = v.treating }) or L("med_hospitals.er.card_no_treating")
                    local w = math.max(dxGetTextWidth(name, 1, fontB) + 40, dxGetTextWidth(sub, 1, font) + 40, 150)
                    local h = 40
                    local bx, by = sx - w / 2, sy - h / 2
                    dxDrawRectangle(bx, by, w, h, tocolor(14, 18, 22, 170))
                    local tc = TRIAGE_COLORS[v.triage or 0]
                    dxDrawRectangle(bx + 6, by + 6, 24, 16, tc and tocolor(tc[1], tc[2], tc[3], 235) or tocolor(125, 138, 149, 235))
                    dxDrawText(v.triage and v.triage > 0 and ("T" .. v.triage) or "?", bx + 6, by + 6, bx + 30, by + 22,
                        tocolor(255, 255, 255), 1, font, "center", "center")
                    dxDrawText(name, bx + 36, by + 4, bx + w - 6, by + 22, tocolor(241, 244, 247), 1, fontB, "left", "center", true)
                    dxDrawText(sub, bx + 8, by + 22, bx + w - 6, by + h - 3, tocolor(184, 194, 204), 1, font, "left", "center", true)
                    -- open orders: a small badge with their number in the top right corner
                    if (v.orders or 0) > 0 then
                        dxDrawRectangle(bx + w - 26, by + 5, 20, 16, tocolor(47, 134, 232, 235))
                        dxDrawText(tostring(v.orders), bx + w - 26, by + 5, bx + w - 6, by + 21, tocolor(255, 255, 255), 1, font, "center", "center")
                    end
                end
            end
        end
    end
end
addEventHandler("onClientRender", root, draw)
