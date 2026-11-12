-- wx_snow :: roof map upload (/snowbake on an admin client -> data/roofmap.png + data/roofmap.json)
--
-- The client sends the png in CHUNK sized latent events (bigger latent events get lost), then
-- "done" with the grid info. Written here; a resource restart sends the new file to everybody.

local uploads = {} -- player -> { parts = {}, count }

local function adminOk(player)
    local ok, v = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    return ok and (tonumber(v) or 0) >= SNOW.ADMIN_LEVEL
end

addEvent("wx_snow:bakeChunk", true)
addEventHandler("wx_snow:bakeChunk", resourceRoot, function(index, total, data)
    if not client or not adminOk(client) then return end
    index, total = tonumber(index), tonumber(total)
    if not index or not total or type(data) ~= "string" or total > 400 then return end
    local u = uploads[client]
    if not u or index == 1 then u = { parts = {}, total = total, got = 0 }; uploads[client] = u end
    if not u.parts[index] then u.got = u.got + 1 end
    u.parts[index] = data
    triggerClientEvent(client, "wx_snow:bakeAck", resourceRoot, index, total)
end)

addEvent("wx_snow:bakeDone", true)
addEventHandler("wx_snow:bakeDone", resourceRoot, function(info)
    if not client or not adminOk(client) then return end
    local u = uploads[client]
    uploads[client] = nil
    if not u or u.got ~= u.total or type(info) ~= "table" then
        return snowNotify(client, "wx_snow.bake.upload_failed")
    end
    local png = table.concat(u.parts)
    if png:sub(2, 4) ~= "PNG" then return snowNotify(client, "wx_snow.bake.upload_failed") end

    if fileExists(SNOW.ROOF.FILE) then fileDelete(SNOW.ROOF.FILE) end
    local f = fileCreate(SNOW.ROOF.FILE)
    if not f then return snowNotify(client, "wx_snow.bake.upload_failed") end
    fileWrite(f, png)
    fileClose(f)

    local meta = {
        minX = tonumber(info.minX), minY = tonumber(info.minY), size = tonumber(info.size),
        cells = tonumber(info.cells), zMin = tonumber(info.zMin), zMax = tonumber(info.zMax),
        baked = getRealTime().timestamp, by = getPlayerName(client), tiles = tonumber(info.tiles),
        hits = tonumber(info.hits),
    }
    if fileExists(SNOW.ROOF.INFO) then fileDelete(SNOW.ROOF.INFO) end
    f = fileCreate(SNOW.ROOF.INFO)
    if f then
        fileWrite(f, toJSON(meta, true))
        fileClose(f)
    end
    outputServerLog(("[wx_snow] roof map saved by %s: %d bytes, %dx%d cells"):format(
        getPlayerName(client), #png, meta.cells or 0, meta.cells or 0))
    snowNotify(client, "wx_snow.bake.saved", { kb = math.floor(#png / 1024) })
end)

addEventHandler("onPlayerQuit", root, function() uploads[source] = nil end)
