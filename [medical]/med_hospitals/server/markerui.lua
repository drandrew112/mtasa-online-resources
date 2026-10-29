if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The 3D cards above the hospital markers (bay / handover / heal), drawn by ui_core
-- (createMarkerUI). The card follows the marker's HOSP_DATA (call hospMarkerUI(marker) after
-- changing it). The handover cards are shown only to the HOSP.HANDOVER_WORK players on duty
-- (ui_core `work` field, checked by the client). Per player meta (sent only within the card's
-- radius): the progress bar (startProgress).

local TEXT = {
    bay           = { "hosp_ambu", "med_hospitals.config.ambulance_bay", "med_hospitals.config.park_here_to_start_handover" },
    heliBay       = { "hosp_heli", "med_hospitals.config.helipad", "med_hospitals.config.land_here_to_start_handover" },
    handover      = { "hosp_handover", "med_hospitals.config.patient_handover", "med_hospitals.config.push_patient_in_on_stretcher" },
    heliHandover  = { "hosp_handover", "med_hospitals.config.helicopter_patient_handover", "med_hospitals.config.push_patient_in_on_stretcher" },
    heal          = { "hosp_heal", "med_hospitals.config.treatment", "med_hospitals.config.stand_here_s_free_of_charge" },
    healPaid      = { "hosp_heal", "med_hospitals.config.treatment", "med_hospitals.config.stand_here_s_patient_pays" },
    bayRestricted = { "hosp_restricted", "med_hospitals.config.ambulances_only", "med_hospitals.config.leave_bay_fine_every_s" },
}

local function hintParams()
    return { bay_fine = HOSP.BAY_FINE, bay_fine_interval = HOSP.BAY_FINE_INTERVAL / 1000, heal_time = HOSP.HEAL_TIME / 1000 }
end

local ids = {}          -- marker -> ui id
local markers = {}      -- ui id -> marker
local nextId = 0
local progress = {}     -- player -> { id, duration, text, endTick }
local dirty = {}        -- markers waiting for the refresh timer
local dirtyTimer

local function uiCall(fn, ...)
    if not isResourceRunning("ui_core") then return false end
    return exports.ui_core[fn](exports.ui_core, ...)
end

-- -> card kind (TEXT key), occupied
local function kindOf(marker)
    local kind = getElementData(marker, HOSP_DATA.KIND)
    if kind == "bay" and getElementData(marker, HOSP_DATA.RESTRICTED) then return "bayRestricted", false end
    local occupied = kind == "bay" and getElementData(marker, HOSP_DATA.OCCUPIED) and true or false
    local heli = getElementData(marker, HOSP_DATA.HELI)
    if heli and kind == "bay" then kind = "heliBay" end
    if heli and kind == "handover" then kind = "heliHandover" end
    if kind == "heal" and getElementData(marker, HOSP_DATA.PAID) then kind = "healPaid" end
    return kind, occupied
end

local function isHandover(kind) return kind == "handover" or kind == "heliHandover" end

local function metaFor(player, id)
    local p = progress[player]
    if not (p and p.id == id and isElement(markers[id])) then return nil end
    return { progress = { duration = p.duration, remaining = math.max(0, p.endTick - getTickCount()), text = p.text } }
end

local function push(player, id)
    uiCall("setMarkerUIMeta", id, metaFor(player, id), player)
end

local defined = {}      -- marker -> true once createMarkerUI ran (later changes: updateMarkerUI)

local function define(marker, create)
    local id = ids[marker]
    local kind, occupied = kindOf(marker)
    local t = TEXT[kind]
    if not id or not t then return end
    local fields = {
        type = t[1],
        name = getElementData(marker, HOSP_DATA.NAME) or "",
        title = L.msg(t[2]),
        hint = L.msg(t[3], hintParams()),
        hidden = occupied,  -- occupied bays have no card
        -- handover cards only for the medics on duty (the tutorial's for its player anyway)
        work = isHandover(kind) and not getElementData(marker, HOSP_DATA.TUTORIAL) and HOSP.HANDOVER_WORK or false,
    }
    if defined[marker] and not create then
        uiCall("updateMarkerUI", id, fields)
        return
    end
    fields.element = marker
    fields.radius, fields.fullRadius = HOSP.LABEL_DISTANCE, HOSP.LABEL_FULL_DISTANCE
    fields.minScale, fields.height = HOSP.LABEL_MIN_SCALE, HOSP.LABEL_HEIGHT
    defined[marker] = uiCall("createMarkerUI", id, fields) and true or nil
end

-- (Re)defines the marker's card from its HOSP_DATA (coalesced: several data changes in a row
-- cost one update).
function hospMarkerUI(marker)
    if not isElement(marker) then return end
    if not ids[marker] then
        nextId = nextId + 1
        local id = "h" .. nextId
        ids[marker], markers[id] = id, marker
        addEventHandler("onElementDestroy", marker, function()
            ids[source], markers[id], defined[source] = nil, nil, nil
        end, false)
    end
    dirty[marker] = true
    if not dirtyTimer then
        dirtyTimer = setTimer(function()
            dirtyTimer = nil
            local list = dirty
            dirty = {}
            for m in pairs(list) do
                if isElement(m) then define(m) end
            end
        end, 50, 1)
    end
end

-- Progress bar in a marker's card, for one player
function startProgress(player, marker, duration, text)
    local id = ids[marker]
    if not id or not isElement(player) then return end
    local old = progress[player]
    progress[player] = { id = id, duration = duration, text = text, endTick = getTickCount() + duration }
    if old and old.id ~= id then push(player, old.id) end
    push(player, id)
end

function stopProgress(player)
    local p = progress[player]
    progress[player] = nil
    if p and isElement(player) then push(player, p.id) end
end

addEventHandler("onPlayerQuit", root, function() progress[source] = nil end)

-- ui_core restarted: define every card again
addEvent("onMarkerUISystemStart")
addEventHandler("onMarkerUISystemStart", root, function()
    for marker in pairs(ids) do
        if isElement(marker) then define(marker, true) end
    end
end)
