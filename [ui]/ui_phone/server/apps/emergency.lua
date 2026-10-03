--[[
    ui_phone / server/apps/emergency.lua
    "Emergency Services" contact. Only EMS works for now: the caller types a
    title and a description (ui_core text input, see "contacts:prompt" in
    client/apps/contacts.lua) and a med_erm task is created with the caller's
    name and position. med_erm_auto (if running) prioritizes and dispatches it
    as soon as a unit is free.

    Refused when:
      - med_erm is not running or no ambulance unit is signed in at all
        (a busy unit is fine - it takes the call after its current case),
      - the caller stands at an open med_scenemanager scene (that scene already
        has its own task, an ambulance is on its way),
      - the caller's previous call is still open.
]]

local ERM = "med_erm"
local SCENES = "med_scenemanager"

local pending = {}   -- [player] = { title = string | nil }
local openCalls = {} -- [player] = taskId of the caller's last call

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function contact()
    return PHONE_CONFIG.contactByKey("emergency")
end

local function say(player, text)
    PhoneServer.toast(player, "Emergency Services: " .. text)
end

local function clean(text, maxLen)
    text = tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("[%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, maxLen)
end

-- true | false, reason (already worded for the caller)
local function canCallEms(player)
    if not running(ERM) then return false, "Nobody answers the line." end
    if #(exports[ERM]:getUnits() or {}) == 0 then
        return false, "There are no ambulance crews on duty right now."
    end

    local taskId = openCalls[player]
    if taskId then
        local t = exports[ERM]:getTask(taskId)
        if t and t.status ~= "closed" then
            return false, ("Your call (case #%d) is already being handled."):format(taskId)
        end
        openCalls[player] = nil
    end

    if running(SCENES) then
        local x, y, z = getElementPosition(player)
        if exports[SCENES]:getSceneAt(x, y, z) then
            return false, "An ambulance is already on its way to this location."
        end
    end
    return true
end

local function prompt(player, step, title, maxLen)
    PhoneServer.push(player, "contacts:prompt", "emergency", step, title, maxLen)
end

local function submitEms(player, title, description)
    local ok, reason = canCallEms(player)
    if not ok then say(player, reason) return end

    local x, y, z = getElementPosition(player)
    local caller = getPlayerName(player):gsub("#%x%x%x%x%x%x", "")
    local taskId, err = exports[ERM]:createTask(title, description, x, y, z, caller, nil, {
        phoneCall = true,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
    })
    if not taskId then
        say(player, "The call could not be registered.")
        outputDebugString("[phone] EMS call failed: " .. tostring(err), 2)
        return
    end

    openCalls[player] = taskId
    if #(exports[ERM]:getFreeUnits() or {}) > 0 then
        say(player, ("Call registered (case #%d). An ambulance is being dispatched."):format(taskId))
    else
        say(player, ("Call registered (case #%d). All crews are busy - an ambulance will come as soon as one is free."):format(taskId))
    end
    PhoneServer.close(player)
end

-- Called by the "contacts:action" router (server/apps/contacts.lua).
function emergencyCall(player, actionKey)
    if actionKey == "pd" then
        say(player, "The police line is not available yet.")
    elseif actionKey == "fd" then
        say(player, "The fire department line is not available yet.")
    elseif actionKey == "ems" then
        local ok, reason = canCallEms(player)
        if not ok then say(player, reason) return end
        pending[player] = {}
        prompt(player, "title", "What is the emergency? (short title)", contact().titleMax)
    end
end

-- text == false: the caller cancelled the input.
PhoneServer.on("contacts:promptResult", function(player, contactKey, step, text)
    if contactKey ~= "emergency" then return end
    local p = pending[player]
    if not p then return end
    local c = contact()

    if text == false then
        pending[player] = nil
        return
    end

    if step == "title" then
        local title = clean(text, c.titleMax)
        if title == "" then
            pending[player] = nil
            say(player, "The call was cancelled - no emergency was given.")
            return
        end
        p.title = title
        prompt(player, "description", "Describe the situation (patients, injuries, ...)", c.descMax)
    elseif step == "description" and p.title then
        pending[player] = nil
        submitEms(player, p.title, clean(text, c.descMax))
    end
end)

addEventHandler("onPlayerQuit", root, function()
    pending[source] = nil
    openCalls[source] = nil
end)
