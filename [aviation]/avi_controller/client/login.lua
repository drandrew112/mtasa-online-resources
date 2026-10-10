-- Position login window (opened by the ATC marker): SACC_CTR, <ICAO>_APP, <ICAO>_TWR with their occupants.

LOGIN = { open = false }

local C = {
    dim    = tocolor(0, 0, 0, 150),
    bg     = tocolor(12, 18, 28, 250),
    head   = tocolor(22, 34, 52, 255),
    border = tocolor(70, 110, 160, 255),
    row    = tocolor(18, 26, 38, 255),
    rowAlt = tocolor(15, 22, 33, 255),
    text   = tocolor(225, 232, 242, 255),
    dim2   = tocolor(120, 130, 145, 255),
    btn    = tocolor(40, 90, 160, 255),
    btnHov = tocolor(60, 120, 200, 255),
    busy   = tocolor(150, 90, 60, 255),
    mine   = tocolor(40, 130, 70, 255),
    red    = tocolor(150, 50, 50, 255),
    redHov = tocolor(190, 70, 70, 255),
}

local buttons = {}

addEvent("avi:ctlPositions", true)
addEventHandler("avi:ctlPositions", resourceRoot, function(list, current)
    LOGIN = { open = true, list = list, current = current }
    showCursor(true)
end)

function loginClose()
    LOGIN.open = false
    if not SC.visible then showCursor(false) end
end

local function inside(r, x, y)
    return x and x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

local function button(r, label, base, hover, mx, my, act)
    dxDrawRectangle(r[1], r[2], r[3], r[4], inside(r, mx, my) and hover or base)
    dxDrawText(label, r[1], r[2], r[1] + r[3], r[2] + r[4], C.text, 1, F.uiB, "center", "center", true)
    buttons[#buttons + 1] = { rect = r, act = act }
end

local function drawLogin()
    if not LOGIN.open then return end
    buttons = {}
    local mx, my
    if isCursorShowing() then
        local cx, cy = getCursorPosition()
        mx, my = cx * SC.sx, cy * SC.sy
    end
    local rows = LOGIN.list or {}
    local w = 620 * U
    local rh = 34 * U
    local headH = 46 * U
    local h = headH + #rows * rh + 56 * U
    local x, y = (SC.sx - w) / 2, (SC.sy - h) / 2
    if not SC.visible then dxDrawRectangle(0, 0, SC.sx, SC.sy, C.dim) end
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, w, headH, C.head)
    dxDrawText("ATC - select a position", x + 14 * U, y, x + w, y + headH, C.text, 1, F.title, "left", "center")
    button({ x + w - 36 * U, y + 9 * U, 28 * U, 28 * U }, "X", C.red, C.redHov, mx, my, loginClose)

    local ry = y + headH
    for i, p in ipairs(rows) do
        dxDrawRectangle(x, ry, w, rh, i % 2 == 0 and C.rowAlt or C.row)
        dxDrawText(p.id, x + 14 * U, ry, x + 150 * U, ry + rh, C.text, 1, F.uiB, "left", "center")
        dxDrawText(p.name, x + 150 * U, ry, x + 380 * U, ry + rh, C.dim2, 1, F.ui, "left", "center", true)
        local br = { x + w - 140 * U, ry + 5 * U, 126 * U, rh - 10 * U }
        if p.mine then
            dxDrawRectangle(br[1], br[2], br[3], br[4], C.mine)
            dxDrawText("Logged in", br[1], br[2], br[1] + br[3], br[2] + br[4], C.text, 1, F.uiB, "center", "center")
        elseif p.occupant then
            dxDrawText(p.occupant, x + 380 * U, ry, br[1] - 8 * U, ry + rh, C.busy, 1, F.ui, "right", "center", true)
            dxDrawRectangle(br[1], br[2], br[3], br[4], C.busy)
            dxDrawText("Staffed", br[1], br[2], br[1] + br[3], br[2] + br[4], C.text, 1, F.uiB, "center", "center")
        elseif p.allowed == false then
            dxDrawText("No rights", br[1], br[2], br[1] + br[3], br[2] + br[4], C.dim2, 1, F.uiB, "center", "center")
        else
            local id = p.id
            button(br, "Log in", C.btn, C.btnHov, mx, my, function()
                triggerServerEvent("avi:ctlLogin", resourceRoot, id)
                loginClose()
            end)
        end
        ry = ry + rh
    end
    if LOGIN.current then
        button({ x + 14 * U, y + h - 44 * U, 160 * U, 32 * U }, "Log out " .. LOGIN.current, C.red, C.redHov, mx, my, function()
            triggerServerEvent("avi:ctlLogout", resourceRoot)
            loginClose()
        end)
    end
    dxDrawText("Altitudes in feet, speeds in knots, vertical speed in ft/min.", x, y + h - 44 * U, x + w - 14 * U,
        y + h - 12 * U, C.dim2, 1, F.ui, "right", "center")
end
addEventHandler("onClientRender", root, drawLogin, true, "low-1")

-- true when the click belonged to the login window
function loginClick(mx, my)
    if not LOGIN.open then return false end
    for _, b in ipairs(buttons) do
        if inside(b.rect, mx, my) then
            b.act()
            return true
        end
    end
    return true     -- modal: swallow every click while open
end

-- tell avi_core (ATC marker label) that the controller UI covers the screen
local uiFlag
addEventHandler("onClientRender", root, function()
    local open = (LOGIN.open or SC.visible) and true or false
    if open ~= uiFlag then
        uiFlag = open
        setElementData(localPlayer, "avi.uiOpen", open, false)
    end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    setElementData(localPlayer, "avi.uiOpen", false, false)
end)
