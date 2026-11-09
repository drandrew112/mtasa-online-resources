-- Wall monitors of the imaging rooms (hospitals.json er.ct.monitor, er.xray.viewer): the last study of the
-- room is shown on a DX monitor in the world (er/client/wall.lua, render target + dxDrawMaterialLine3D).

ER.walls = {}   -- [hospitalId] = { ct = study, xray = study }

local function screens()
    local out = {}
    for hid, e in pairs(ER.byHospital) do
        local ct = e.cfg.ct and e.cfg.ct.monitor
        local xr = e.cfg.xray and e.cfg.xray.viewer
        if ct then out[#out + 1] = { hid = hid, room = "ct", x = ct.x, y = ct.y, z = ct.z, rot = ct.rot or 0, w = ct.w or 3.2, h = ct.h or 1.8, dim = e.h.dimension, int = e.h.interior } end
        if xr then out[#out + 1] = { hid = hid, room = "xray", x = xr.x, y = xr.y, z = xr.z, rot = xr.rot or 0, w = xr.w or 2.8, h = xr.h or 1.6, dim = e.h.dimension, int = e.h.interior } end
    end
    return out
end

local ready = {}
local function sendAll(p)
    triggerClientEvent(p, "er:wallScreens", resourceRoot, screens(), ER.walls)
end

addEvent("his:hello", true)
addEventHandler("his:hello", resourceRoot, function() ready[client] = true sendAll(client) end)
addEventHandler("onPlayerQuit", root, function() ready[source] = nil end)
LoadHandlers[#LoadHandlers + 1] = function() for p in pairs(ready) do if isElement(p) then sendAll(p) end end end

function ER.wallShow(c, r)
    local room = r.kind == "ct" and "ct" or "xray"
    local img = r.images and r.images[1]
    local study = { kind = r.kind, key = r.key, file = img and img.file or false, finding = img and img.finding or false,
                    name = c.name or false, at = r.at, by = c.treatingName or false, side = r.side }
    ER.walls[c.hospital] = ER.walls[c.hospital] or {}
    ER.walls[c.hospital][room] = study
    for p in pairs(ready) do
        if isElement(p) then triggerClientEvent(p, "er:wall", resourceRoot, c.hospital, room, study) end
    end
end
