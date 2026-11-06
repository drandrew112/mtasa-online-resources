-- Wall monitors of the CT room and the X-ray room (er/server/wall.lua): the last study on a 3D screen.
-- One render target per screen, redrawn when its study changes or its image arrives; drawn with
-- dxDrawMaterialLine3D only within 30 m.

local screens = {}   -- { { hid, room, x, y, z, rot, w, h, dim, int, rt, study, dirty } }
local RT_W, RT_H = 640, 360
local RANGE = 30

local function screenOf(hid, room)
    for _, s in ipairs(screens) do if s.hid == hid and s.room == room then return s end end
end

addEvent("er:wallScreens", true)
addEventHandler("er:wallScreens", resourceRoot, function(list, walls)
    for _, s in ipairs(screens) do if isElement(s.rt) then destroyElement(s.rt) end end
    screens = list or {}
    for _, s in ipairs(screens) do
        s.study = walls and walls[s.hid] and walls[s.hid][s.room] or false
        s.dirty = true
    end
end)

addEvent("er:wall", true)
addEventHandler("er:wall", resourceRoot, function(hid, room, study)
    local s = screenOf(hid, room)
    if s then s.study, s.dirty = study, true end
end)

local fontB, font
local function redraw(s)
    if not s.rt then s.rt = dxCreateRenderTarget(RT_W, RT_H, false) end
    if not s.rt then return end
    fontB = fontB or dxCreateFont("client/fonts/RobotoB.ttf", 18) or "default-bold"
    font = font or dxCreateFont("client/fonts/Roboto.ttf", 14) or "default"
    dxSetRenderTarget(s.rt, true)
    dxDrawRectangle(0, 0, RT_W, RT_H, tocolor(4, 6, 8))
    local st = s.study
    if not st or not st.file then
        dxDrawText(L(s.room == "ct" and "med_hospitals.wall.ct_idle" or "med_hospitals.wall.xray_idle"), 0, 0, RT_W, RT_H, tocolor(90, 110, 130), 1, fontB, "center", "center")
        dxSetRenderTarget()
        s.dirty = false
        return
    end
    local tex = HIS.image(HIS.imagePath(st.kind, st.file))
    local iw = RT_H - 20
    if tex then
        dxDrawImage(10, 10, iw, iw, tex)
    else
        dxDrawText(L("med_hospitals.his.loading_image"), 10, 10, 10 + iw, 10 + iw, tocolor(120, 130, 140), 1, font, "center", "center")
    end
    local tx = iw + 30
    local tm = getRealTime(st.at or 0)
    dxDrawText(L("med_hospitals.erc.order_" .. tostring(st.key):gsub("%.", "_")) .. (st.side and (" · " .. L("medsys.body." .. st.side)) or ""), tx, 16, RT_W - 10, 50, tocolor(235, 240, 245), 1, fontB, "left", "top", true, true)
    dxDrawText(("%02d:%02d"):format(tm.hour, tm.minute), tx, 70, RT_W - 10, 100, tocolor(140, 160, 175), 1, font)
    dxDrawText(st.name or L("med_hospitals.his.unknown"), tx, 100, RT_W - 10, 130, tocolor(235, 240, 245), 1, fontB)
    local finding = st.finding and L("med_hospitals.erc.finding_" .. st.finding) or L("med_hospitals.his.result_negative")
    dxDrawText(finding, tx, 150, RT_W - 14, RT_H - 50, tocolor(255, 190, 160), 1, font, "left", "top", true, true)
    if st.by then dxDrawText(L("med_hospitals.wall.requested_by", { name = st.by }), tx, RT_H - 40, RT_W - 10, RT_H - 10, tocolor(140, 160, 175), 1, font) end
    dxSetRenderTarget()
    s.dirty = not tex   -- try again until the image is there
end

addEventHandler("onClientRestore", root, function() for _, s in ipairs(screens) do s.dirty = true end end)

addEventHandler("onClientRender", root, function()
    if #screens == 0 then return end
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    for _, s in ipairs(screens) do
        if s.dim == dim and s.int == int and getDistanceBetweenPoints3D(px, py, pz, s.x, s.y, s.z) <= RANGE then
            if s.dirty then redraw(s) end
            if s.rt then
                local r = math.rad(s.rot)
                local fx, fy = -math.sin(r), math.cos(r)        -- the direction the screen faces
                local x, y = s.x + fx * 0.03, s.y + fy * 0.03     -- a few cm off the wall
                dxDrawMaterialLine3D(x, y, s.z + s.h / 2, x, y, s.z - s.h / 2, s.rt, s.w, tocolor(255, 255, 255), x + fx, y + fy, s.z)
            end
        end
    end
end)
