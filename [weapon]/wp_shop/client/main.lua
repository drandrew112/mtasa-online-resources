if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- wp_shop / client/main.lua
-- Shop markers: WS.key inside one opens the weapon browser. The camera looks at a 3D weapon above
-- the counter, the top-left panel (client/panel.lua) names it; arrows switch, Enter picks,
-- Backspace leaves. A picked weapon opens a ui_inac temp menu (buy the weapon, ammo by the
-- magazine); Backspace there goes back to the browser.

ShopMarker = nil   -- shop marker the local player stands in
Browse     = nil   -- { shop, int, list, index, obj, state = "browse" | "menu", menuId, alpha }

local GUARD_MS = 200   -- a key press that closed the temp menu must not also leave the browser
local guardTick = 0
local openTimer = nil

addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEvent("wp_shop:result", true)

local function notify(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("wp_shop.title"), text)
    end
end

local function alert(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:setAlert(text, 218, 54, 51, 3000)
    end
end

-- id -> ammo of the owned weapons (active set)
function ownedWeapons()
    local out = {}
    local res = getResourceFromName("wp_manager")
    if not res or getResourceState(res) ~= "running" then return out end
    for _, w in ipairs(exports.wp_manager:getWeapons() or {}) do out[tonumber(w.id)] = tonumber(w.ammo) or 0 end
    return out
end

function weaponName(id)
    return L("wp_manager.weapon." .. id)
end

function currentWeapon()
    return Browse and Browse.list[Browse.index]
end

---------------------------------------------------------------- preview + camera

local function setPreviewModel()
    local id = currentWeapon()
    local def = id and WS.weapons[id]
    if not def or not isElement(Browse.obj) then return end
    setElementModel(Browse.obj, def.model)
end

local function camLoop()
    if not Browse or not isElement(Browse.obj) then return end
    local p, c, cfg = Browse.int.preview, Browse.int.camera, WS.preview
    local dx, dy, dz = c.x - p.x, c.y - p.y, c.z - p.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.01 then dx, dy, dz, len = 0, 1, 0, 1 end

    -- side view: the weapon's long axis across the view direction, swinging a little
    local base = math.deg(math.atan2(dy, dx)) + 90 + (cfg.rotOffset or 0)
    local swing = math.sin(getTickCount() * cfg.swingSpeed) * cfg.swing
    setElementRotation(Browse.obj, 0, 0, base + swing)

    local r = getElementRadius(Browse.obj) or 0.4
    local dist = math.max(cfg.minDist, math.min(cfg.maxDist, r * cfg.distK))
    setCameraMatrix(p.x + dx / len * dist, p.y + dy / len * dist, p.z + dz / len * dist,
        p.x, p.y, p.z, 0, cfg.fov)
end

---------------------------------------------------------------- browser keys

local onPrev, onNext, onEnter, onBack

local function bindBrowseKeys(on)
    local f = on and bindKey or unbindKey
    f("arrow_l", "down", onPrev)
    f("arrow_u", "down", onPrev)
    f("arrow_r", "down", onNext)
    f("arrow_d", "down", onNext)
    f("enter", "down", onEnter)
    f("num_enter", "down", onEnter)
    f("backspace", "down", onBack)
end

local function lockControls()
    toggleAllControls(false, true, false)
end

function closeShop()
    if not Browse then return end
    local b = Browse
    Browse = nil
    if isTimer(openTimer) then killTimer(openTimer) end
    openTimer = nil
    bindBrowseKeys(false)
    removeEventHandler("onClientPreRender", root, camLoop)
    if b.state == "menu" and exports.ui_inac:isTempMenuOpen() then exports.ui_inac:closeTempMenu() end
    if isElement(b.obj) then destroyElement(b.obj) end
    setElementAlpha(localPlayer, b.alpha or 255)
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, false)
end

local function openShop()
    local shop = WS.shopById[getElementData(ShopMarker, "wp_shop:shop")]
    local int = shop and WS.interiors[shop.interior]
    if not WS.isComplete(int) then return end
    local list = WS.catalog(shop)
    if #list == 0 then return end

    local wm = getResourceFromName("wp_manager")
    if wm and getResourceState(wm) == "running" and exports.wp_manager:hasTempLoadout() then
        notify(L("wp_shop.msg.temp_loadout"))
        return
    end

    local p = int.preview
    local obj = createObject(WS.weapons[list[1]].model, p.x, p.y, p.z)
    if not obj then return end
    setElementInterior(obj, getElementInterior(localPlayer))
    setElementDimension(obj, getElementDimension(localPlayer))
    setElementCollisionsEnabled(obj, false)

    Browse = { shop = shop, int = int, list = list, index = 1, obj = obj, state = "browse",
        alpha = getElementAlpha(localPlayer) }
    setElementAlpha(localPlayer, 0)   -- local only: the player is not in the way of the camera
    lockControls()
    bindBrowseKeys(true)
    addEventHandler("onClientPreRender", root, camLoop)
    playSoundFrontEnd(1)
end

local function step(d)
    if not Browse or Browse.state ~= "browse" then return end
    local n = #Browse.list
    Browse.index = (Browse.index - 1 + d) % n + 1
    setPreviewModel()
    playSoundFrontEnd(1)
end
onPrev = function() step(-1) end
onNext = function() step(1) end

onBack = function()
    if not Browse or Browse.state ~= "browse" then return end
    if getTickCount() - guardTick < GUARD_MS then return end
    closeShop()
end

---------------------------------------------------------------- temp menu (buy)

local function buildMenu()
    local id = currentWeapon()
    local def = WS.weapons[id]
    local own = ownedWeapons()[id]
    local items = {}

    if def.thrown then
        for _, n in ipairs(WS.thrownPacks) do
            items[#items + 1] = {
                label = L("wp_shop.menu.pieces", { count = n, name = weaponName(id) }),
                desc = own and L("wp_shop.menu.thrown_have", { count = own }) or L("wp_shop.menu.thrown_desc"),
                value = { k = "thrown", n = n }, price = VAT.gross("weapons", def.price * n), closeOnSelect = false,
            }
        end
    else
        items[1] = {
            label = L("wp_shop.menu.buy_weapon", { name = weaponName(id) }),
            desc = own and L("wp_shop.menu.weapon_owned") or (def.mag and L("wp_shop.menu.weapon_desc_empty") or L("wp_shop.menu.weapon_desc")),
            value = { k = "weapon" }, price = VAT.gross("weapons", def.price), checked = own ~= nil or nil, closeOnSelect = false,
        }
        if def.mag then
            for _, n in ipairs(WS.ammoPacks) do
                local key = def.box and "wp_shop.menu.boxes" or "wp_shop.menu.magazines"
                items[#items + 1] = {
                    label = L(key, { count = n, rounds = def.mag * n }),
                    desc = own and L("wp_shop.menu.ammo_have", { ammo = own }) or L("wp_shop.menu.buy_weapon_first"),
                    value = { k = "ammo", n = n }, price = VAT.gross("weapons", def.magPrice * n), closeOnSelect = false,
                }
            end
        end
    end
    return { title = L.upper(weaponName(id)), items = items }
end

local function openMenu()
    openTimer = nil
    if not Browse or Browse.state ~= "browse" then return end
    local id = exports.ui_inac:createTempMenu(buildMenu())
    if not id then return end
    Browse.state, Browse.menuId = "menu", id
end

-- The temp menu opens a moment later, so ui_inac's own Enter handler of this same key press
-- cannot pick its first row.
onEnter = function()
    if not Browse or Browse.state ~= "browse" or isTimer(openTimer) then return end
    playSoundFrontEnd(1)
    openTimer = setTimer(openMenu, 50, 1)
end

addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if not Browse or Browse.state ~= "menu" or id ~= Browse.menuId or type(value) ~= "table" then return end
    triggerServerEvent("wp_shop:buy", resourceRoot, Browse.shop.id, currentWeapon(), value.k, value.n)
end)

-- Backspace at the menu root: back to the browser
addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if not Browse or Browse.state ~= "menu" or id ~= Browse.menuId then return end
    Browse.state, Browse.menuId = "browse", nil
    guardTick = getTickCount()
    lockControls()   -- ui_inac turned the move controls back on
end)

addEventHandler("wp_shop:result", resourceRoot, function(ok, text, id, reason)
    if reason == "no_money" then
        alert(tostring(text or ""))
        playSoundFrontEnd(4)
        return
    end
    notify(tostring(text or ""))
    if ok and Browse and Browse.state == "menu" and tonumber(id) == currentWeapon()
        and not WS.weapons[currentWeapon()].thrown then
        exports.ui_inac:updateTempMenuItem("1", { checked = true })
    end
end)

---------------------------------------------------------------- markers

local function onKey()
    if Browse or not isElement(ShopMarker) then return end
    if isCursorShowing() or isChatBoxInputActive() or isMTAWindowActive() then return end
    if isPedInVehicle(localPlayer) or isPedDead(localPlayer) then return end
    if exports.ui_inac:isTempMenuOpen() or getElementData(localPlayer, "interactionMenuOpen") then return end
    openShop()
end

addEventHandler("onClientMarkerHit", resourceRoot, function(hit, matchingDim)
    if hit ~= localPlayer or not matchingDim or not getElementData(source, "wp_shop:shop") then return end
    ShopMarker = source
    bindKey(WS.key, "down", onKey)
end)

addEventHandler("onClientMarkerLeave", resourceRoot, function(left)
    if left ~= localPlayer or source ~= ShopMarker then return end
    ShopMarker = nil
    unbindKey(WS.key, "down", onKey)
    closeShop()
end)

-- the clerk cannot be hurt
addEventHandler("onClientPedDamage", resourceRoot, function()
    if getElementData(source, "wp_shop:clerk") then cancelEvent() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, closeShop)
addEventHandler("onClientResourceStop", resourceRoot, closeShop)
