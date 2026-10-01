-- Duty state. A player can be on duty in one work at a time (this is what "having a work"
-- means). Going on duty saves the civilian skin and puts on the chosen work outfit, going off
-- duty restores it and removes the player's work vehicle.
--
-- Events (source = the player):
--   onPlayerWorkDutyRequest (workId)          cancellable; cancelEvent(true, "reason") is shown to the player
--   onPlayerWorkDutyStart   (workId, skin)
--   onPlayerWorkSkinChange  (workId, skin)
--   onPlayerWorkDutyEnd     (workId, reason)  reason: "player" | "script" | "quit" | "unregistered" | "shutdown"

local duty = {}                    -- player -> { work, skin, civilSkin }

addEvent("onPlayerWorkDutyRequest")
addEvent("onPlayerWorkDutyStart")
addEvent("onPlayerWorkSkinChange")
addEvent("onPlayerWorkDutyEnd")

---------------------------------------------------------------- queries

function getPlayerWork(player)
    local d = duty[player]
    return d and d.work or false
end

-- isPlayerOnDuty(player)          -> on duty in any work
-- isPlayerOnDuty(player, workId)  -> on duty in that work
function isPlayerOnDuty(player, workId)
    local d = duty[player]
    if not d then return false end
    return workId == nil or d.work == workId
end

function getWorkPlayers(workId)
    local list = {}
    for p, d in pairs(duty) do
        if d.work == workId and isElement(p) then list[#list + 1] = p end
    end
    return list
end

function getPlayerWorkSkin(player)
    local d = duty[player]
    return d and d.skin or false
end

---------------------------------------------------------------- work-only element visibility

-- Elements (markers, blips, radar areas...) visible only to the players on duty in a work.
-- Kept in sync as players go on / off duty. workId = false makes it visible to everyone again.
local visible = {}                 -- workId -> { [element] = true }

function setElementVisibleToWork(element, workId)
    if not isElement(element) then return false end
    for _, set in pairs(visible) do set[element] = nil end
    if not workId then
        setElementVisibleTo(element, root, true)
        return true
    end
    visible[workId] = visible[workId] or {}
    visible[workId][element] = true
    setElementVisibleTo(element, root, false)
    for _, p in ipairs(getWorkPlayers(workId)) do
        setElementVisibleTo(element, p, true)
    end
    return true
end

local function applyVisibility(player)
    for workId, set in pairs(visible) do
        local v = isPlayerOnDuty(player, workId)
        for el in pairs(set) do
            if isElement(el) then
                setElementVisibleTo(el, player, v)
            else
                set[el] = nil
            end
        end
    end
end

---------------------------------------------------------------- duty changes

-- -> true | false, errorText
function startDuty(player, workId, skin)
    local work = Works[workId]
    if not work then return false, "This work is not available." end
    local d = duty[player]
    if d then
        if d.work == workId then return false, "You are already on duty." end
        local other = Works[d.work]
        return false, ("You are already working as %s. Go off duty first."):format(other and other.name or d.work)
    end

    skin = tonumber(skin) or work.skins[1].model
    if not isWorkSkin(work, skin) then return false, "This outfit does not belong to this work." end

    if not triggerEvent("onPlayerWorkDutyRequest", player, workId) then
        local reason = getCancelReason()
        return false, (reason and reason ~= "") and reason or "You cannot go on duty right now."
    end
    -- a handler may have changed things
    if duty[player] or not Works[workId] or not isElement(player) then
        return false, "You cannot go on duty right now."
    end

    local civil = getElementModel(player)
    duty[player] = { work = workId, skin = skin, civilSkin = civil }
    setElementData(player, WORK_DATA.CIVIL_SKIN, civil, false)
    setElementModel(player, skin)
    setElementData(player, WORK_DATA.PLAYER_WORK, workId)
    applyVisibility(player)
    triggerEvent("onPlayerWorkDutyStart", player, workId, skin)
    return true
end

function endDuty(player, reason)
    local d = duty[player]
    if not d then return false end
    destroyPlayerWorkVehicle(player)
    duty[player] = nil
    if isElement(player) then
        setElementModel(player, d.civilSkin)
        removeElementData(player, WORK_DATA.CIVIL_SKIN)
        setElementData(player, WORK_DATA.PLAYER_WORK, false)
        applyVisibility(player)
    end
    triggerEvent("onPlayerWorkDutyEnd", player, d.work, reason or "script")
    return true
end

function changeDutySkin(player, skin)
    local d = duty[player]
    if not d then return false, "You are not on duty." end
    skin = tonumber(skin)
    if not skin or not isWorkSkin(Works[d.work], skin) then
        return false, "This outfit does not belong to this work."
    end
    d.skin = skin
    setElementModel(player, skin)
    triggerEvent("onPlayerWorkSkinChange", player, d.work, skin)
    return true
end

function endDutyForWork(workId, reason)
    for _, p in ipairs(getWorkPlayers(workId)) do endDuty(p, reason) end
end

function endAllDuties(reason)
    for p in pairs(duty) do endDuty(p, reason) end
end

---------------------------------------------------------------- script exports

-- Puts the player on duty without the marker (skin = nil -> the work's first outfit).
-- The request event still runs. -> true | false, errorText
function setPlayerOnDuty(player, workId, skin)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "bad player" end
    return startDuty(player, workId, skin)
end

function setPlayerOffDuty(player)
    return endDuty(player, "script")
end

function setPlayerWorkSkin(player, skin)
    return changeDutySkin(player, skin)
end

---------------------------------------------------------------- engine events

addEventHandler("onPlayerQuit", root, function()
    endDuty(source, "quit")
end)

-- A respawn (death, admin) may set another model: put the uniform back on
addEventHandler("onPlayerSpawn", root, function()
    local d = duty[source]
    if d and getElementModel(source) ~= d.skin then
        setElementModel(source, d.skin)
    end
end)

-- The work.* element data is server-owned: revert any client attempt to set it
addEventHandler("onElementDataChange", root, function(key, old)
    if client and type(key) == "string" and key:sub(1, 5) == "work." then
        if old == nil then removeElementData(source, key) else setElementData(source, key, old) end
    end
end)
