-- v_mysql :: connection guard (client)
--
-- Shows a small "database issues, reconnecting" banner while the server-side
-- guard (scripts/connguard.lua) is holding this player frozen for a lost
-- MySQL connection. Purely cosmetic - the freeze itself is server-side.

local visible = false

addEvent("mysql:guardNotice", true)
addEventHandler("mysql:guardNotice", root, function(show)
    visible = show and true or false
end)

local function draw()
    if not visible then return end

    local sx = guiGetScreenSize()
    local w, h = 460, 64
    local x = (sx - w) / 2
    local y = 36

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 190))
    dxDrawRectangle(x, y, w, 3, tocolor(220, 60, 60, 255))

    local dots = ("."):rep(math.floor(getTickCount() / 500) % 4)
    dxDrawText("Database issues - reconnecting" .. dots, x, y, x + w, y + h,
        tocolor(255, 255, 255, 255), 1.1, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, draw)
