-- The unit tablet: frame, header, hamburger menu, input.
-- Pages live in client/pages/*.lua and register themselves in Pages.

Tablet = {
    open    = false,
    page    = "home",
    menu    = false,
    confirm = nil,     -- { title, text, action, label }
}
Pages = {}

local s = Gfx.s
local W, H = 720, 470          -- design size (scaled by Gfx.s)
local HEADER_H = 46

local function frame()
    local w, h = s(W), s(H)
    local margin = s(24)
    return Gfx.screenW - w - margin, Gfx.screenH - h - margin, w, h
end

local function canUseKeys()
    return not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
        and not getElementData(localPlayer, "textInputOpen")
        and not getElementData(localPlayer, "browserOpen")
        and not (Admin and Admin.open)
end

local function inTabletVehicle()
    local veh = getPedOccupiedVehicle(localPlayer)
    return veh and Config.TABLET_VEHICLES[getElementModel(veh)] and veh or false
end

function Tablet.setPage(page)
    Tablet.page = page
    Tablet.menu = false
end

---------------------------------------------------------------- header

local function drawHeader(x, y, w, h)
    Gfx.round(x, y, w, h, s(8), Theme.header)
    dxDrawRectangle(x, y + h - s(8), w, s(8), Theme.header)
    dxDrawRectangle(x, y + h - 1, w, 1, Theme.line)

    -- logo
    local ls = s(26)
    Gfx.round(x + s(12), y + (h - ls) / 2, ls, ls, s(5), Theme.accent)
    Gfx.cross(x + s(12) + s(6), y + (h - ls) / 2 + s(6), ls - s(12), tocolor(255, 255, 255))

    local tx = x + s(12) + ls + s(10)
    local u = State.unit
    if u then
        Gfx.text(u.callsign, tx, y, s(120), h, Theme.text, Gfx.font(13, true))
        local cw = dxGetTextWidth(u.callsign, 1, Gfx.font(13, true))
        Gfx.text(u.type .. "  ·  " .. u.plate, tx + cw + s(10), y, s(200), h, Theme.dim, Gfx.font(9))
    else
        Gfx.text("EMS Unit Terminal", tx, y, s(220), h, Theme.text, Gfx.font(12, true))
    end

    -- clock
    local t = getRealTime()
    Gfx.text(string.format("%02d:%02d:%02d", t.hour, t.minute, t.second), x, y, w, h, Theme.dim, Gfx.font(10, true), "center")

    -- status pill
    local bw = s(44)
    local mx = x + w - bw
    if u then
        local st = Config.STATUS[u.status]
        local label = st.label:upper()
        local pw = dxGetTextWidth(label, 1, Gfx.font(8, true)) + s(20)
        Gfx.round(mx - pw - s(4), y + (h - s(22)) / 2, pw, s(22), s(11), Gfx.rgb(st.color))
        Gfx.text(label, mx - pw - s(4), y + (h - s(22)) / 2, pw, s(22), tocolor(255, 255, 255), Gfx.font(8, true), "center")
    end

    -- hamburger
    local hov = Gfx.hover(mx, y, bw, h)
    if hov or Tablet.menu then Gfx.round(mx + s(4), y + s(6), bw - s(10), h - s(12), s(6), Theme.panel2) end
    for i = 0, 2 do
        dxDrawRectangle(mx + s(13), y + h / 2 - s(7) + i * s(6), s(18), s(2), Theme.text)
    end
    if State.unread > 0 then
        dxDrawCircle(mx + s(34), y + s(12), s(4), 0, 360, Theme.accent, Theme.accent, 12)
    end
    Gfx.hit(mx, y, bw, h, function() Tablet.menu = not Tablet.menu end)
    Tablet.menuAnchor = { mx + bw, y + h }
end

---------------------------------------------------------------- menu

local function drawMenu(screen)
    local items = {}
    if State.unit then
        items = {
            { "Home",        function() Tablet.setPage("home") end,     "home" },
            { "Active Case", function() Tablet.setPage("case") end,     "case" },
            { "Messages",    function() Tablet.setPage("messages") end, "messages", State.unread },
            false,
            { "End Shift", function()
                Tablet.menu = false
                Tablet.confirm = {
                    title = "End shift?",
                    text  = "Your unit will be signed out and released from its active case.",
                    label = "End Shift",
                    action = function() triggerServerEvent("erm:signOut", resourceRoot) end,
                }
            end, nil, nil, true },
        }
    end
    items[#items + 1] = { "Close Tablet", function() Tablet.close() end }

    local iw, ih = s(200), s(38)
    local total = 0
    for _, it in ipairs(items) do total = total + (it and ih or s(9)) end

    local ax, ay = Tablet.menuAnchor[1], Tablet.menuAnchor[2]
    local x, y = ax - iw - s(6), ay + s(4)

    -- click anywhere else closes the menu
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() Tablet.menu = false end)

    Gfx.round(x - 1, y - 1, iw + 2, total + s(8) + 2, s(8), Theme.line)
    Gfx.round(x, y, iw, total + s(8), s(8), Theme.panel)

    local cy = y + s(4)
    for _, it in ipairs(items) do
        if not it then
            dxDrawRectangle(x + s(10), cy + s(4), iw - s(20), 1, Theme.line)
            cy = cy + s(9)
        else
            local label, fn, page, badge, danger = it[1], it[2], it[3], it[4], it[5]
            local hov = Gfx.hover(x, cy, iw, ih)
            if hov then Gfx.rect(x + s(4), cy, iw - s(8), ih, Theme.panel2) end
            if page and page == Tablet.page then
                dxDrawRectangle(x + s(4), cy + s(8), s(3), ih - s(16), Theme.accent)
            end
            Gfx.text(label, x + s(18), cy, iw - s(36), ih, danger and Gfx.rgb({ 240, 90, 80 }) or Theme.text, Gfx.font(10, page == Tablet.page))
            if badge and badge > 0 then
                local bw = s(24)
                Gfx.round(x + iw - bw - s(12), cy + (ih - s(18)) / 2, bw, s(18), s(9), Theme.accent)
                Gfx.text(tostring(badge), x + iw - bw - s(12), cy + (ih - s(18)) / 2, bw, s(18), Theme.text, Gfx.font(8, true), "center")
            end
            Gfx.hit(x, cy, iw, ih, fn)
            cy = cy + ih
        end
    end
end

local function drawConfirm(sx, sy, sw, sh)
    local c = Tablet.confirm
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)

    local w, h = s(360), s(170)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x, y, w, h, s(10), Theme.panel)
    Gfx.text(c.title, x + s(20), y + s(16), w - s(40), s(26), Theme.text, Gfx.font(13, true))
    Gfx.text(c.text, x + s(20), y + s(46), w - s(40), s(50), Theme.dim, Gfx.font(10), "left", "top", true)

    local bw = (w - s(52)) / 2
    Gfx.button(x + s(20), y + h - s(56), bw, s(38), "Cancel", {}, function() Tablet.confirm = nil end)
    Gfx.button(x + s(32) + bw, y + h - s(56), bw, s(38), c.label, { color = { 200, 50, 45 } }, function()
        Tablet.confirm = nil
        c.action()
    end)
end

---------------------------------------------------------------- render

local function render()
    if getElementData(localPlayer, "browserOpen") or (not State.unit and not inTabletVehicle()) then
        Tablet.close()
        return
    end

    Gfx.hits, Gfx.scrollAreas = {}, {}
    local overlay = Tablet.menu or Tablet.confirm or (not State.unit and Login.picker)
    Gfx.blockHover = overlay and true or false

    local x, y, w, h = frame()
    Tablet.bounds = { x, y, w, h }

    -- device
    Gfx.round(x - 1, y - 1, w + 2, h + 2, s(24), Theme.edge)
    Gfx.round(x, y, w, h, s(24), Theme.bezel)
    dxDrawCircle(x + w / 2, y + s(9), s(2.5), 0, 360, tocolor(46, 50, 58), tocolor(46, 50, 58), 12)

    local sx, sy, sw, sh = x + s(16), y + s(18), w - s(32), h - s(34)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.bg)

    drawHeader(sx, sy, sw, s(HEADER_H))
    local cy, ch = sy + s(HEADER_H), sh - s(HEADER_H)

    if State.unit then
        local page = Pages[Tablet.page] or Pages.home
        page.draw(sx, cy, sw, ch)
    else
        Login.draw(sx, cy, sw, ch)
    end

    Gfx.blockHover = false
    if not State.unit and Login.picker then
        Gfx.hits = {}
        Login.drawPicker(sx, sy, sw, sh)
    end
    if Tablet.confirm then
        Gfx.hits = {}
        drawConfirm(sx, sy, sw, sh)
    end
    if Tablet.menu then
        Gfx.hits = {}
        drawMenu()
    end
end

---------------------------------------------------------------- open / close

local function onClick(button, state, ax, ay)
    if button ~= "left" or state ~= "down" then return end
    if getElementData(localPlayer, "textInputOpen") then return end
    Gfx.click(ax, ay)
end

local function onKey(key, press)
    if not press then return end
    if key == "mouse_wheel_up" then
        Gfx.wheel(Tablet.page == "messages" and 1 or -1)
    elseif key == "mouse_wheel_down" then
        Gfx.wheel(Tablet.page == "messages" and -1 or 1)
    end
end

-- While the tablet is open, clicks must not shoot and F / Enter must not get
-- in or out of the vehicle. Only controls that were enabled get re-enabled.
local LOCKED_CONTROLS = { "fire", "action", "aim_weapon", "vehicle_fire", "vehicle_secondary_fire", "enter_exit" }
local lockedControls = {}

local function lockControls()
    for _, control in ipairs(LOCKED_CONTROLS) do
        if isControlEnabled(control) then
            toggleControl(control, false)
            lockedControls[#lockedControls + 1] = control
        end
    end
end

local function unlockControls()
    for _, control in ipairs(lockedControls) do toggleControl(control, true) end
    lockedControls = {}
end

addEventHandler("onClientResourceStop", resourceRoot, unlockControls)

function Tablet.show()
    if Tablet.open then return end
    Tablet.open = true
    Tablet.menu, Tablet.confirm = false, nil
    showCursor(true, false)
    lockControls()
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientClick", root, onClick)
    addEventHandler("onClientKey", root, onKey)
    playSoundFrontEnd(1)
end

function Tablet.close()
    if not Tablet.open then return end
    Tablet.open = false
    Tablet.menu, Tablet.confirm = false, nil
    Login.picker = false
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientClick", root, onClick)
    removeEventHandler("onClientKey", root, onKey)
    unlockControls()
    if not getElementData(localPlayer, "textInputOpen") then showCursor(false) end
end

function Tablet.toggle()
    if Tablet.open then Tablet.close() return end
    if not canUseKeys() then return end

    if State.unit then
        Tablet.show()
        return
    end

    local veh = inTabletVehicle()
    if not veh then
        State.notify("EMS Tablet", "The tablet can only be used inside an ambulance until you sign in.")
        return
    end
    Login.reset(veh)
    Tablet.show()
end

bindKey(Config.TABLET_KEY, "down", function()
    if Tablet.open or canUseKeys() then Tablet.toggle() end
end)

-- ui_core's text input hides the cursor when it closes; bring it back.
addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function()
    if Tablet.open then
        setTimer(function() if Tablet.open then showCursor(true, false) end end, 50, 1)
    end
end)
