-- Finds the elements around the player that have a usable menu, keeps the focused one, and opens /
-- closes the menu. A timer rescans every IO.SCAN_INTERVAL ms; registry changes rescan right away.

State = {
    candidates = {},  -- { element, distance, menus, sx }, sorted left -> right on screen
    focus = nil,      -- focused element
    open = false,
    stack = {},       -- submenu path: { { menuId, path }, ... }
    page = 1,
}

local controlsSuppressed = false
local savedControls = {}
local WEAPON_CONTROLS = { "next_weapon", "previous_weapon" }

local function isBlocked()
    if isInteractionDisabled() then return true end
    if isPedDead(localPlayer) or getElementHealth(localPlayer) <= 0 then return true end
    if isCursorShowing() or isMainMenuActive() or isConsoleActive() or isChatBoxInputActive() then return true end
    for _, key in ipairs(IO.BLOCKING_DATA) do
        if getElementData(localPlayer, key) then return true end
    end
    return false
end

local function menuUsable(menu, element, distance)
    local def = menu.def
    if not def.enabled or distance > def.range then return false end
    if def.selfDataKey and not ioTruthy(getElementData(localPlayer, def.selfDataKey)) then return false end
    if isPedInVehicle(localPlayer) and not def.allowInVehicle then return false end
    return ioDataMatches(def, element)
end

local function byPriority(a, b)
    if a.def.priority ~= b.def.priority then return a.def.priority > b.def.priority end
    return a.order < b.order
end

-- Every usable menu on the element (bound + type menus), highest priority first.
local function collectMenus(element, distance)
    local list = {}
    local function addFrom(set)
        if not set then return end
        for id in pairs(set) do
            local menu = Menus[id]
            if menu and menuUsable(menu, element, distance) then list[#list + 1] = menu end
        end
    end
    addFrom(ElementMenus[element])
    addFrom(TypeMenus[getElementType(element)])
    table.sort(list, byPriority)
    return list
end

-- World point the marker / panel hangs from: above the head for peds, on top of the bounding box
-- for everything else, plus the top menu's def.offset.
function getAnchor(element, menu)
    local x, y, z
    local elementType = getElementType(element)
    if elementType == "ped" or elementType == "player" then
        x, y, z = getPedBonePosition(element, 8)
        if x then z = z + 0.35 end
    end
    if not x then
        x, y, z = getElementPosition(element)
        local _, _, _, _, _, maxZ = getElementBoundingBox(element)
        z = z + (maxZ and maxZ + 0.2 or 0.6)
    end
    local offset = menu and menu.def.offset
    if offset then x, y, z = x + offset[1], y + offset[2], z + offset[3] end
    return x, y, z
end

local function hasLineOfSight(element)
    local sx, sy, sz = getPedBonePosition(localPlayer, 8)
    if not sx then
        sx, sy, sz = getElementPosition(localPlayer)
        sz = sz + 0.6
    end
    local ex, ey, ez = getElementPosition(element)
    local hit, _, _, _, hitElement = processLineOfSight(sx, sy, sz, ex, ey, ez,
        true, true, false, true, false, true, false, false, localPlayer)
    return not hit or hitElement == element
end

local function setWeaponSwitchSuppressed(state)
    if not IO.SUPPRESS_WEAPON_SWITCH or state == controlsSuppressed then return end
    controlsSuppressed = state
    for _, control in ipairs(WEAPON_CONTROLS) do
        if state then
            savedControls[control] = isControlEnabled(control)
            toggleControl(control, false)
        elseif savedControls[control] ~= false then
            toggleControl(control, true)
        end
    end
end

-- Only while Q/E mean something here: the menu is open or there are several menus to switch between.
local function updateWeaponSwitch()
    setWeaponSwitchSuppressed(State.open or #State.candidates >= 2)
end

function getFocusCandidate()
    for _, candidate in ipairs(State.candidates) do
        if candidate.element == State.focus then return candidate end
    end
end

function openMenu()
    if State.open or not State.focus then return end
    State.open, State.stack, State.page = true, {}, 1
    updateWeaponSwitch()
    triggerEvent("onClientInteractMenuOpen", localPlayer, State.focus)
end

function closeMenu()
    if not State.open then return end
    local target = State.focus
    State.open, State.stack, State.page = false, {}, 1
    updateWeaponSwitch()
    triggerEvent("onClientInteractMenuClose", localPlayer, isElement(target) and target or nil)
end

function scan()
    local candidates = {}

    if not isBlocked() then
        local px, py, pz = getElementPosition(localPlayer)
        local interior, dimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
        local seen = {}

        local function consider(element)
            if seen[element] or element == localPlayer or not isElement(element) then return end
            seen[element] = true
            if getElementDimension(element) ~= dimension or getElementInterior(element) ~= interior then return end
            if isElementStreamable(element) and not isElementStreamedIn(element) then return end

            local ex, ey, ez = getElementPosition(element)
            local distance = getDistanceBetweenPoints3D(px, py, pz, ex, ey, ez)
            if distance > IO.MAX_RANGE then return end

            local menus = collectMenus(element, distance)
            if #menus == 0 then return end

            local needsSight = false
            for _, menu in ipairs(menus) do
                if menu.def.lineOfSight then needsSight = true break end
            end
            if needsSight and not hasLineOfSight(element) then return end

            -- off-screen elements cannot be focused, except the one whose menu is open
            local sx = getScreenFromWorldPosition(getAnchor(element, menus[1]))
            if not sx and not (State.open and element == State.focus) then return end

            candidates[#candidates + 1] = { element = element, distance = distance, menus = menus, sx = sx or 0 }
        end

        for element in pairs(ElementMenus) do consider(element) end

        local typeRange = {}
        for elementType, set in pairs(TypeMenus) do
            for id in pairs(set) do
                local menu = Menus[id]
                if menu then typeRange[elementType] = math.max(typeRange[elementType] or 0, menu.def.range) end
            end
        end
        for elementType, range in pairs(typeRange) do
            for _, element in ipairs(getElementsWithinRange(px, py, pz, range, elementType, interior, dimension)) do
                consider(element)
            end
        end
    end

    -- left -> right on screen, so Q/E move the focus in the direction you would expect
    table.sort(candidates, function(a, b) return a.sx < b.sx end)
    State.candidates = candidates

    if not getFocusCandidate() then
        closeMenu()
        local nearest
        for _, candidate in ipairs(candidates) do
            if not nearest or candidate.distance < nearest.distance then nearest = candidate end
        end
        State.focus = nearest and nearest.element or nil
    end

    updateWeaponSwitch()
end

local scanPending = false

-- Coalesces bursts of registry changes (e.g. the initial server sync) into one scan.
function requestScan()
    if scanPending then return end
    scanPending = true
    setTimer(function()
        scanPending = false
        scan()
    end, 50, 1)
end

-- Q / E
function cycleFocus(direction)
    local candidates = State.candidates
    if #candidates < 2 then return false end
    local index = 1
    for i, candidate in ipairs(candidates) do
        if candidate.element == State.focus then index = i break end
    end
    index = (index - 1 + direction) % #candidates + 1

    local wasOpen = State.open
    closeMenu()
    State.focus = candidates[index].element
    if wasOpen then openMenu() end
    return true
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(scan, IO.SCAN_INTERVAL, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeMenu()
    setWeaponSwitchSuppressed(false)
end)
