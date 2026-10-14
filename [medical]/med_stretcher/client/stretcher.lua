-- Client side of the stretchers: size (scale), visibility and collisions follow the synced
-- "stretcher.state" element data; the ground snap after the stretcher is put down is measured
-- here, because only the client knows the ground height. Pushing is in client/push.lua.

addEvent("stretcher:snap", true)

local D = STRETCHER_DATA

-- ---------------------------------------------------------------------------------------------
-- Scale: the model is fitted so its longest side is STRETCHER.TARGET_LENGTH metres
-- ---------------------------------------------------------------------------------------------

local fitScale -- computed once from the first stretcher's unscaled bounding box

local function getFitScale(obj)
    if fitScale then return fitScale end
    local x0, y0, _, x1, y1 = getElementBoundingBox(obj)
    local length = x0 and math.max(x1 - x0, y1 - y0)
    if not length or length < 0.1 then return STRETCHER.FALLBACK_SCALE end
    fitScale = STRETCHER.TARGET_LENGTH / length
    return fitScale
end

-- ---------------------------------------------------------------------------------------------
-- Visibility / collisions
-- ---------------------------------------------------------------------------------------------

-- Vehicle-local y of the rear doors: the rear door dummies of the (possibly modded) model, or the
-- back of its bounding box. nil if neither can be read.
local function rearDoorY(vehicle)
    local sum, count = 0, 0
    for _, name in ipairs({ "door_lr_dummy", "door_rr_dummy" }) do
        local _, y = getVehicleComponentPosition(vehicle, name)
        if y and y < 0 then sum, count = sum + y, count + 1 end
    end
    if count > 0 then return sum / count end
    local _, y0 = getElementBoundingBox(vehicle)
    return y0
end

-- The server parks the stowed (hidden) stretcher at an estimated rear point (STOWED_MENU_POINT);
-- here it is moved locally onto the real rear doors, so its menu appears on them.
local function placeStowed(obj)
    local vehicle = getElementAttachedTo(obj)
    if not vehicle or getElementType(vehicle) ~= "vehicle" or not isElementStreamedIn(vehicle) then return end
    local y = rearDoorY(vehicle)
    if not y then return end
    local o = STRETCHER.STOWED_MENU_POINT
    setElementAttachedOffsets(obj, o[1], y, o[3], o[4], o[5], o[6])
end

local function applyStretcher(obj)
    if not isElement(obj) then return end
    local state = getElementData(obj, D.STATE)
    if not state then return end

    setObjectScale(obj, getFitScale(obj))
    if state == "stowed" then placeStowed(obj) end
    -- stowed: invisible and without collisions, so it cannot push the ambulance around;
    -- moving / pushing: no collisions with the vehicle, the pusher, the patient or anybody on the way
    setElementAlpha(obj, state == "stowed" and 0 or 255)
    setElementCollisionsEnabled(obj, state == "ground")
end

-- ---------------------------------------------------------------------------------------------
-- Patients: no collisions, and the heading follows the stretcher
-- ---------------------------------------------------------------------------------------------

local patients = {} -- ped -> stretcher

-- The patient lying on a stretcher must not collide with it or with the pusher
local function applyPatient(ped)
    if not isElement(ped) then return end
    local stretcher = getElementData(ped, D.ON)
    setElementCollisionsEnabled(ped, not stretcher)
    patients[ped] = isElement(stretcher) and stretcher or nil
end

-- attachElements moves an attached ped with its parent but never turns it, so the heading is set
-- here every frame: stretcher yaw + PATIENT_OFFSET rz
addEventHandler("onClientPreRender", root, function()
    if not next(patients) then return end
    local offset = STRETCHER.PATIENT_OFFSET[6]
    for ped, stretcher in pairs(patients) do
        if not isElement(ped) or not isElement(stretcher) then
            patients[ped] = nil
        elseif isElementStreamedIn(ped) then
            local _, _, rz = getElementRotation(stretcher)
            setElementRotation(ped, 0, 0, (rz + offset) % 360, "default", true)
        end
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    local elementType = getElementType(source)
    if elementType == "object" then
        applyStretcher(source)
    elseif elementType == "vehicle" then
        -- the stowed stretcher may have streamed in before its ambulance
        for _, obj in ipairs(getAttachedElements(source)) do
            if getElementType(obj) == "object" and getElementData(obj, D.STATE) == "stowed" then placeStowed(obj) end
        end
    elseif elementType == "ped" or elementType == "player" then
        applyPatient(source)
    end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == D.STATE then
        applyStretcher(source)
    elseif key == D.ON then
        applyPatient(source)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, obj in ipairs(getElementsByType("object", root, true)) do applyStretcher(obj) end
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, ped in ipairs(getElementsByType(elementType, root, true)) do
            if getElementData(ped, D.ON) then applyPatient(ped) end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Ground snap: the server placed the stretcher at an estimated height, correct it
-- ---------------------------------------------------------------------------------------------

addEventHandler("stretcher:snap", resourceRoot, function(obj)
    if not isElement(obj) then return end
    local x, y, z = getElementPosition(obj)
    -- ray down from above the estimate, ignoring the stretcher itself
    local hit, _, _, groundZ = processLineOfSight(x, y, z + 1.5, x, y, z - 3,
        true, false, false, true, false, false, false, false, obj)
    if not hit then
        groundZ = getGroundPosition(x, y, z + 1.5)
        if not groundZ or groundZ == 0 then return end
    end
    triggerServerEvent("stretcher:snapResult", resourceRoot, obj, groundZ + STRETCHER.GROUND_Z)
end)
