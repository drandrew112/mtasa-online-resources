if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Weapon wheel. Hold TAB: the wheel opens, the camera stops turning and the mouse movement only
-- steers the selection. There is no visible cursor: the cursor is shown but transparent and put
-- back to the centre every frame, its offset is added to a virtual pointer, and the pointer's
-- direction picks the category. The mouse wheel steps the weapons of the selected category.
-- Releasing TAB equips the selection through wp_manager.

addEvent("onClientWeaponsChanged") -- wp_manager: source localPlayer

local KEY = "tab"
local sx, sy = guiGetScreenSize()
local CX, CY = sx / 2, sy / 2
local S = sy / 1080
local R_OUT, R_IN = 290 * S, 118 * S
local GAP_DEG = 1.6
local ARC_STEPS = 10
local POINTER_MAX = 140 * S   -- the virtual pointer is clamped to this radius
local DEAD_ZONE = 30 * S      -- below this the selection does not change

local COLOR = {
    seg      = tocolor(18, 18, 20, 200),
    segEmpty = tocolor(18, 18, 20, 120),
    segSel   = tocolor(239, 159, 39, 235),
    centre   = tocolor(0, 0, 0, 185),
    text     = tocolor(241, 239, 232, 255),
    textDim  = tocolor(255, 255, 255, 90),
    textSub  = tocolor(255, 255, 255, 140),
    textSel  = tocolor(65, 36, 2, 255),
    subSel   = tocolor(99, 56, 6, 255),
    ammo     = tocolor(250, 199, 117, 255),
    ammoOut  = tocolor(240, 149, 149, 255),
    dot      = tocolor(255, 255, 255, 80),
    dotSel   = tocolor(239, 159, 39, 255),
}

local fonts = {}
local function font(size, bold)
    local key = (bold and "b" or "r") .. size
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", math.max(7, math.floor(size * S)), false, "antialiased") or "default"
    end
    return fonts[key]
end

local isOpen = false
local cats = {}            -- { { id = "melee", items = { {id, ammo, clip}, ... } }, ... } in wheel order
local sel = 1              -- selected category index
local pick = {}            -- category index -> item index
local px, py = 0, 0        -- virtual pointer
local segments = {}        -- category index -> primitive vertices

local function managerRunning()
    local res = getResourceFromName("wp_manager")
    return res and getResourceState(res) == "running"
end

--------------------------------------------------------------------------------
-- Geometry: segment i is centred at 90 + 45*i degrees (screen y down): bottom, then clockwise
--------------------------------------------------------------------------------

local function polar(deg, r)
    local a = math.rad(deg)
    return CX + r * math.cos(a), CY + r * math.sin(a)
end

local function buildSegments(count)
    segments = {}
    local span = 360 / count
    for i = 1, count do
        local mid = 90 + span * (i - 1)
        local a1, a2 = mid - span / 2 + GAP_DEG, mid + span / 2 - GAP_DEG
        local v = {}
        for k = 0, ARC_STEPS - 1 do
            local t1 = a1 + (a2 - a1) * k / ARC_STEPS
            local t2 = a1 + (a2 - a1) * (k + 1) / ARC_STEPS
            local ox1, oy1 = polar(t1, R_OUT)
            local ox2, oy2 = polar(t2, R_OUT)
            local ix1, iy1 = polar(t1, R_IN)
            local ix2, iy2 = polar(t2, R_IN)
            v[#v + 1] = { ox1, oy1 }; v[#v + 1] = { ox2, oy2 }; v[#v + 1] = { ix1, iy1 }
            v[#v + 1] = { ix1, iy1 }; v[#v + 1] = { ox2, oy2 }; v[#v + 1] = { ix2, iy2 }
        end
        segments[i] = { mid = mid, v = v }
    end
end

local centreDisc = {}
do
    local r, n = R_IN - 8 * S, 48
    centreDisc[1] = { CX, CY }
    for k = 0, n do
        local x, y = polar(360 * k / n, r)
        centreDisc[#centreDisc + 1] = { x, y }
    end
end

local function drawPrimitive(kind, points, color)
    local v = {}
    for i, p in ipairs(points) do v[i] = { p[1], p[2], color } end
    dxDrawPrimitive(kind, false, unpack(v))
end

-- Category index of a direction, wheel order
local function indexOfAngle(deg, count)
    local span = 360 / count
    return math.floor((((deg - 90) % 360) + span / 2) / span) % count + 1
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

local function weaponName(id)
    return L("wp_manager.weapon." .. id)
end

local kinds = {} -- weapon id -> kind (wp_manager WP.LIST)

local function build()
    local categories, list = exports.wp_manager:getWeaponDefs()
    for _, row in ipairs(list) do kinds[row[1]] = row[3] end
    local owned = {}
    for _, w in ipairs(exports.wp_manager:getWeapons() or {}) do owned[w.id] = w end
    local index = {}
    cats = {}
    for i, id in ipairs(categories) do
        cats[i] = { id = id, items = {} }
        index[id] = cats[i]
    end
    if index.melee then index.melee.items[1] = { id = 0 } end -- unarmed
    for _, row in ipairs(list) do
        local w, cat = owned[row[1]], index[row[2]]
        if w and cat then cat.items[#cat.items + 1] = w end
    end
    if #segments ~= #cats then buildSegments(#cats) end
end

-- Puts the selection on the equipped weapon; keeps the other categories' picks in range
local function selectCurrent()
    local current = exports.wp_manager:getCurrentWeapon() or 0
    sel = 1
    for i, cat in ipairs(cats) do
        if not pick[i] or pick[i] > #cat.items then pick[i] = 1 end
        for k, item in ipairs(cat.items) do
            if item.id == current then sel, pick[i] = i, k end
        end
    end
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function canOpen()
    if isOpen or not managerRunning() or isCursorShowing() or isConsoleActive() or isMainMenuActive() then return false end
    if isPedDead(localPlayer) then return false end
    for _, key in ipairs({ "showChatInput", "inventoryOpen", "textInputOpen" }) do
        if getElementData(localPlayer, key) == true then return false end
    end
    return true
end

local render

local function close(confirm)
    if not isOpen then return end
    isOpen = false
    removeEventHandler("onClientRender", root, render)
    setCursorAlpha(255)
    showCursor(false)
    if confirm and managerRunning() and not isPedDead(localPlayer) then
        local cat = cats[sel]
        local item = cat and cat.items[pick[sel]]
        if item then exports.wp_manager:equipWeapon(item.id) end
    end
end

local function open()
    if not canOpen() then return end
    build()
    selectCurrent()
    px, py = 0, 0
    isOpen = true
    showCursor(true, false) -- controls stay on (walking), the visible cursor stops the camera
    setCursorAlpha(0)
    setCursorPosition(CX, CY)
    addEventHandler("onClientRender", root, render)
end

addEventHandler("onClientKey", root, function(button, press)
    if button == KEY then
        if press and not isOpen then
            if canOpen() then
                open()
                cancelEvent()
            end
        end
        return
    end
    if not isOpen then return end
    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        local cat = cats[sel]
        local n = cat and #cat.items or 0
        if n > 1 then
            local step = button == "mouse_wheel_down" and 1 or -1
            pick[sel] = (pick[sel] - 1 + step) % n + 1
        end
        cancelEvent()
    elseif button == "mouse1" or button == "mouse2" then
        cancelEvent()
    end
end)

addEventHandler("onClientWeaponsChanged", root, function()
    if not isOpen then return end
    local keepId = cats[sel] and cats[sel].id
    build()
    for i, cat in ipairs(cats) do
        if not pick[i] or pick[i] > #cat.items then pick[i] = 1 end
        if cat.id == keepId and #cat.items > 0 then sel = i end
    end
    if #cats[sel].items == 0 then selectCurrent() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() close(false) end)
addEventHandler("onClientResourceStop", resourceRoot, function() close(false) end)
addEventHandler("onClientMinimize", root, function() close(false) end)

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function updatePointer()
    local rx, ry = getCursorPosition()
    if rx then
        px, py = px + (rx * sx - CX), py + (ry * sy - CY)
        setCursorPosition(CX, CY)
    end
    local len = math.sqrt(px * px + py * py)
    if len > POINTER_MAX then
        px, py = px / len * POINTER_MAX, py / len * POINTER_MAX
        len = POINTER_MAX
    end
    if len > DEAD_ZONE then
        local i = indexOfAngle(math.deg(math.atan2(py, px)), #cats)
        if cats[i] and #cats[i].items > 0 then sel = i end
    end
end

local function ammoText(item)
    local kind = kinds[item.id] or "melee"
    if item.id == 0 or kind == "melee" then return nil end
    local ammo = tonumber(item.ammo) or 0
    if ammo <= 0 then return L("wp_selector.out_of_ammo"), COLOR.ammoOut end
    if kind == "gun" then
        local clip = math.min(tonumber(item.clip) or ammo, ammo)
        return clip .. " / " .. (ammo - clip), COLOR.ammo
    end
    return tostring(ammo), COLOR.ammo
end

render = function()
    if not getKeyState(KEY) then close(true) return end
    if isPedDead(localPlayer) then close(false) return end
    updatePointer()

    local fCat, fSub = font(15, true), font(12, false)
    local fName, fSmall, fAmmo = font(21, true), font(12, false), font(15, true)
    local midR = (R_OUT + R_IN) / 2
    local chord = 2 * midR * math.sin(math.rad(180 / #cats)) * 0.9

    for i, cat in ipairs(cats) do
        local seg = segments[i]
        local empty = #cat.items == 0
        local on = i == sel
        drawPrimitive("trianglelist", seg.v, on and COLOR.segSel or (empty and COLOR.segEmpty or COLOR.seg))
        local tx, ty = polar(seg.mid, midR)
        local title = L.fit(L("wp_selector.category." .. cat.id), chord, 1, fCat)
        local sub = empty and L("wp_selector.empty") or weaponName(cat.items[pick[i]].id)
        sub = L.fit(sub, chord, 1, fSub)
        local tc = on and COLOR.textSel or (empty and COLOR.textDim or COLOR.text)
        local sc = on and COLOR.subSel or COLOR.textSub
        dxDrawText(title, tx - chord, ty - 26 * S, tx + chord, ty, tc, 1, fCat, "center", "bottom")
        dxDrawText(sub, tx - chord, ty + 2 * S, tx + chord, ty + 24 * S, empty and COLOR.textDim or sc, 1, fSub, "center", "top")
    end

    drawPrimitive("trianglefan", centreDisc, COLOR.centre)
    local cat = cats[sel]
    local item = cat and cat.items[pick[sel]]
    if item then
        local w = (R_IN - 16 * S) * 2
        dxDrawText(L("wp_selector.category." .. cat.id), CX - w / 2, CY - 50 * S, CX + w / 2, CY - 26 * S, COLOR.textSub, 1, fSmall, "center", "bottom")
        dxDrawText(L.fit(weaponName(item.id), w, 1, fName), CX - w / 2, CY - 24 * S, CX + w / 2, CY + 6 * S, COLOR.text, 1, fName, "center", "center")
        local text, color = ammoText(item)
        if text then
            dxDrawText(text, CX - w / 2, CY + 8 * S, CX + w / 2, CY + 32 * S, color, 1, fAmmo, "center", "top")
        end
        local n = #cat.items
        if n > 1 then
            local gap, r = 12 * S, math.max(2, 3 * S)
            local x0 = CX - (n - 1) * gap / 2
            for k = 1, n do
                dxDrawCircle(x0 + (k - 1) * gap, CY + 50 * S, r, 0, 360, k == pick[sel] and COLOR.dotSel or COLOR.dot)
            end
        end
    end
end
