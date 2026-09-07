--[[
    v_phone / client/core/phone.lua
    The shell: open / close, the status + header bars, the home grid, the input
    router and the render loop. Apps plug in through PhoneApp (registry.lua).
]]

local u   = PhoneUI.u
local cfg = PHONE_CONFIG

local state = { open = false, view = "home", appId = nil, home = 1, list = 1 }

Phone = {}
function Phone.isOpen()        return state.open end
function Phone.selectedIndex() return state.list end
function Phone.currentAppId()  return state.appId end

-- Apps use this to move the list cursor themselves (e.g. when opening a
-- sub-screen and wanting the current value pre-selected).
function Phone.setSelected(i)  state.list = math.max(1, math.floor(tonumber(i) or 1)) end

--------------------------------------------------------------------------------
-- Controls / gating
--------------------------------------------------------------------------------

local FROZEN_CONTROLS = {
    "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "next_weapon", "previous_weapon", "action", "enter_exit",
    "change_camera", "vehicle_fire", "vehicle_secondary_fire", "accelerate",
    "brake_reverse", "steer_forward", "steer_back", "vehicle_left", "vehicle_right",
    "handbrake", "horn",
}

local function freezeControls(frozen)
    for _, c in ipairs(FROZEN_CONTROLS) do toggleControl(c, not frozen) end
end

-- A jatekos egy job-lobbyban var (v_jobmanager varo-panel) -> nincs telefon.
local function inJobLobby()
    local res = getResourceFromName("v_jobmanager")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_jobmanager:jobmanagerInLobby() and true or false
end

local function blocked()
    return getElementData(localPlayer, "interactionMenuOpen")
        or getElementData(localPlayer, "socialPanelOpen")
        or getElementData(localPlayer, "paused")
        or getElementData(localPlayer, "showChatInput")
        or getElementData(localPlayer, "reportPanelOpen")
        or isPedDead(localPlayer)
        or inJobLobby()
end

local function wallpaperRGB()
    if PhoneWallpaper then return PhoneWallpaper.rgb() end
    return 18, 20, 26
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function closeCurrentApp()
    local app = state.appId and PhoneApp.get(state.appId)
    if app and app.close then app:close() end
end

local function setOpen(open)
    open = open and true or false
    if open == state.open then return end
    state.open = open
    setElementData(localPlayer, "phoneOpen", open, false)
    freezeControls(open)
    if open then
        closeCurrentApp()
        state.view, state.appId, state.list = "home", nil, 1
        state.home = state.home or 1
        PhoneSound.select()
        phonePull()
    else
        closeCurrentApp()
        state.view, state.appId = "home", nil
    end
end

function Phone.close() setOpen(false) end
function Phone.open()
    if not state.open and not blocked() then setOpen(true) end
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local COLS = 3

local function currentApp()
    return state.appId and PhoneApp.get(state.appId) or nil
end

local function rowsOf(app)
    return (app and app.items) and app:items() or {}
end

local function enterApp(app)
    if not app then return end
    if app.open and app:open() == false then return end  -- Browser refuses entry
    state.view, state.appId, state.list = "app", app.id, 1
    PhoneSound.select()
end

local function navHome(dx, dy)
    local n = #PhoneApp.list()
    local i = state.home + (dx ~= 0 and dx or dy * COLS)
    if i >= 1 and i <= n and i ~= state.home then
        state.home = i
        PhoneSound.click()
    end
end

local function navList(app, delta)
    local rows = rowsOf(app)
    if #rows == 0 then return end
    local i = state.list + delta
    if i < 1 then i = #rows elseif i > #rows then i = 1 end
    if i ~= state.list then
        state.list = i
        PhoneSound.click()
    end
end

local function handleKey(key)
    local app = currentApp()

    -- Give the app first refusal (used by Contacts for its call overlay).
    if state.view == "app" and app and app.key and app:key(key) then
        return
    end

    if state.view == "home" then
        if     key == "arrow_l"   then navHome(-1, 0)
        elseif key == "arrow_r"   then navHome(1, 0)
        elseif key == "arrow_u"   then navHome(0, -1)
        elseif key == "arrow_d"   then navHome(0, 1)
        elseif key == "enter"     then enterApp(PhoneApp.list()[state.home])
        elseif key == "backspace" then setOpen(false)
        end
        return
    end

    if     key == "arrow_u" then navList(app, -1)
    elseif key == "arrow_d" then navList(app, 1)
    elseif key == "enter" then
        local row = rowsOf(app)[state.list]
        if row and app.onSelect then
            if app.selectSound ~= false then PhoneSound.select() end
            app:onSelect(row, state.list)
        end
    elseif key == "backspace" then
        if app and app.close then app:close() end
        state.view, state.appId = "home", nil
        PhoneSound.select()
    end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local NAV = {
    arrow_u = true, arrow_d = true, arrow_l = true, arrow_r = true,
    enter = true, backspace = true,
}

bindKey(cfg.openKey, "down", function()
    if state.open then setOpen(false) else Phone.open() end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not state.open or not press then return end
    if NAV[key] then
        cancelEvent()
        handleKey(key)
    elseif key == "escape" then
        cancelEvent()
        setOpen(false)
    end
end)

--------------------------------------------------------------------------------
-- Chrome
--------------------------------------------------------------------------------

local WHITE = PhoneShader.WHITE

local function drawStatusBar()
    local s, C = PhoneUI.status, PhoneUI.C
    PhoneUI.rounded("statusbar", s.x, s.y, s.w, s.h + PhoneUI.R, PhoneUI.R, WHITE, 0, 0, 0, 255)

    local hrs, mins = getTime()
    PhoneUI.text(("%02d:%02d"):format(hrs, mins), s.x + u(12), s.y, u(90), s.h,
        C.white, u(1.05), "default-bold", "left", "center")

    local batW, batH = u(26), u(13)
    local bx = s.x + s.w - u(12) - batW
    PhoneUI.image(bx, s.y + s.h / 2 - batH / 2, batW, batH, "img/battery.png")

    local pingStr = (getPlayerPing(localPlayer) or 0) .. " ms"
    local pingW = dxGetTextWidth(pingStr, u(0.95), "default-bold") + u(6)
    local px = bx - u(8) - pingW
    PhoneUI.text(pingStr, px, s.y, pingW, s.h, C.dim, u(0.95), "default-bold", "left", "center")

    local sig = u(15)
    PhoneUI.image(px - u(6) - sig, s.y + s.h / 2 - sig / 2, sig, sig, "img/signal.png")
end

local function headerTitle()
    if state.view == "home" then
        local a = PhoneApp.list()[state.home]
        return a and a.name or "Phone"
    end
    local a = currentApp()
    if not a then return "" end
    if a.headerTitle then
        local ok, t = pcall(a.headerTitle, a)
        if ok and t then return tostring(t) end
    end
    return a.name
end

local function drawHeader()
    local h, C = PhoneUI.header, PhoneUI.C
    dxDrawRectangle(h.x, h.y, h.w, h.h, C.header)
    dxDrawRectangle(h.x, h.y + h.h - 1, h.w, 1, C.line)
    PhoneUI.text(headerTitle(), h.x + u(10), h.y, h.w - u(20), h.h,
        C.white, u(1.35), "default-bold", "center", "center")
end

local function drawHome()
    local scr = PhoneUI.SCREEN
    local apps = PhoneApp.list()
    local n = #apps
    local cellW = scr.w / COLS
    local gridRows = math.ceil(n / COLS)
    local top = scr.y + math.max(u(16), (scr.h - gridRows * cellW) / 2 - u(10))

    for i, app in ipairs(apps) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local cx = scr.x + col * cellW + cellW / 2
        local cy = top + row * cellW + cellW / 2

        local selected = (state.home == i)
        local base = cellW * 0.60
        local sz = selected and base * 1.24 or base
        local ix, iy = cx - sz / 2, cy - sz / 2
        local rad = sz * 0.26

        PhoneUI.rounded("home_" .. i, ix, iy, sz, sz, rad, app.icon, 255, 255, 255, 255)

        if selected then
            PhoneUI.rounded("home_ring_" .. i, ix - u(3), iy - u(3), sz + u(6), sz + u(6),
                rad + u(3), WHITE, 255, 255, 255, 45)
        end

        if app.badge then
            local ok, count = pcall(app.badge, app)
            if ok and type(count) == "number" and count > 0 then
                local bs = sz * 0.34
                local bx, by = ix + sz - bs * 0.72, iy - bs * 0.28
                local c = PhoneUI.C.badge
                PhoneUI.rounded("home_badge_" .. i, bx, by, bs, bs, bs * 0.5, WHITE, c[1], c[2], c[3], 255)
                PhoneUI.text(math.min(99, count), bx, by, bs, bs, PhoneUI.C.white, u(0.9), "default-bold", "center", "center")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

addEventHandler("onClientRender", root, function()
    if not state.open then return end
    if blocked() then setOpen(false) return end

    local ph, C = PhoneUI.phone, PhoneUI.C
    PhoneUI.rounded("body", ph.x, ph.y, ph.w, ph.h, PhoneUI.R, WHITE, C.bezel[1], C.bezel[2], C.bezel[3], 255)

    local scr = PhoneUI.SCREEN
    local wr, wg, wb = wallpaperRGB()
    PhoneUI.rounded("screen", scr.x, scr.y - PhoneUI.R, scr.w, scr.h + PhoneUI.R, PhoneUI.R, WHITE, wr, wg, wb, 255)

    drawStatusBar()
    drawHeader()

    if state.view == "home" then
        drawHome()
    else
        local app = currentApp()
        if app then
            if app.items then
                local hint = app.hint
                if type(hint) == "function" then hint = app:hint() end
                PhoneUI.drawList(app:items(), state.list, { hint = hint, empty = app.empty })
            elseif not app.render then
                PhoneUI.drawEmpty(app.empty or "Nothing here yet")
            end
            if app.render then app:render(scr) end
        end
    end
end, false, "low")

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStart", resourceRoot, function()
    setElementData(localPlayer, "phoneOpen", false, false)
    phonePull()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if state.open then freezeControls(false) end
    setElementData(localPlayer, "phoneOpen", false, false)
end)
