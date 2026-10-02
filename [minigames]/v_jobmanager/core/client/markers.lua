-- 3D DX labels above every job marker (same card style as the medical / work markers)
-- and the E key inside a marker, which joins a waiting lobby of that job or opens a new one.

local sw, sh = guiGetScreenSize()
local function s(v) return v * sh / 1080 end

local LABEL_HEIGHT = 1.6        -- above the marker position (ground level)
local LABEL_DISTANCE = 40       -- fully hidden beyond this
local LABEL_FULL_DISTANCE = 12  -- full size up to this
local LABEL_MIN_SCALE = 0.55
local KEY = "e"

local TYPE_STYLE = {
    race       = { color = { 56, 132, 244 }, icon = "R", title = "Race" },
    deathmatch = { color = { 218, 54, 51 },  icon = "DM", title = "Deathmatch" },
}
local DEFAULT_STYLE = { color = { 230, 190, 40 }, icon = "J", title = "Job" }

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "assets/fonts/RobotoB.ttf" or "assets/fonts/Roboto.ttf", s(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local nearbyJobId = nil -- job id of the marker the local player stands in

local function rgb(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

local function round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 12)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 12)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 12)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 12)
end

local function drawLabel(sx, sy, k, alpha, job, inside)
    local st = TYPE_STYLE[job.type] or DEFAULT_STYLE
    local fTitle, fSub, fHint = font(13, true), font(9, true), font(9)
    local a = alpha / 255

    local subStr = (st.title .. "  -  " .. job.minPlayers .. "-" .. job.maxPlayers .. " players"):upper()
    local hint = inside and "Press  E  to start a lobby" or "Step into the marker to start a lobby"
    local pad, icon, gap = s(10) * k, s(34) * k, s(10) * k
    local textW = math.max(dxGetTextWidth(job.name, k, fTitle), dxGetTextWidth(subStr, k, fSub),
        dxGetTextWidth(hint, k, fHint))
    local w = pad + icon + gap + textW + pad * 1.4
    local headH = s(46) * k
    local hintH = s(22) * k
    local h = headH + hintH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, s(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, rgb(st.color, 235 * a))

    -- icon tile
    local ix, iy = x + pad, y + (headH - icon) / 2 + s(2) * k
    round(ix, iy, icon, icon, s(5) * k, rgb(st.color, 240 * a))
    dxDrawText(st.icon, ix, iy, ix + icon, iy + icon, tocolor(255, 255, 255, 255 * a), k,
        font(#st.icon > 1 and 12 or 16, true), "center", "center")

    -- type line / job name
    local tx = ix + icon + gap
    dxDrawText(subStr, tx, y + s(6) * k, tx + textW, y + headH * 0.45, rgb(st.color, 255 * a), k, fSub, "left", "center")
    dxDrawText(job.name, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), k, fTitle, "left", "center")

    -- hint (key highlighted while standing in the marker)
    local hy = y + headH
    dxDrawText(hint, x + pad, hy, x + w - pad, hy + hintH,
        inside and rgb(st.color, 255 * a) or tocolor(200, 205, 212, 220 * a), k, inside and font(9, true) or fHint, "left", "center")

    -- pointer
    dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
end

addEventHandler("onClientRender", root, function()
    if isPlayerMapVisible() or getElementData(localPlayer, "paused") or jobmanagerInLobby() then return end
    if getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0 then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)

    for _, job in ipairs(jobs) do
        local x, y, z = job.marker[1], job.marker[2], job.marker[3]
        local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
        if dist <= LABEL_DISTANCE then
            local lz = z + LABEL_HEIGHT
            if isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                if sx then
                    local k = 1
                    if dist > LABEL_FULL_DISTANCE then
                        k = 1 - (dist - LABEL_FULL_DISTANCE) / (LABEL_DISTANCE - LABEL_FULL_DISTANCE) * (1 - LABEL_MIN_SCALE)
                    end
                    local alpha = 255
                    if dist > LABEL_DISTANCE * 0.8 then alpha = 255 * (LABEL_DISTANCE - dist) / (LABEL_DISTANCE * 0.2) end
                    drawLabel(sx, sy, k, alpha, job, nearbyJobId == job.id)
                end
            end
        end
    end
end)

---------------------------------------------------------------- E in the marker

local function onKey()
    if not nearbyJobId or isCursorShowing() or isChatBoxInputActive() or isMainMenuActive() then return end
    if getElementData(localPlayer, "paused") or jobmanagerInLobby() then return end
    -- in a running match (own dimension) the marker binding is stale
    if getElementDimension(localPlayer) ~= 0 then return end
    playSound("assets/sounds/click.wav")
    jobmanagerJoinJob(nearbyJobId)
end

addEvent("jobmanager:showJoinHint", true)
addEventHandler("jobmanager:showJoinHint", resourceRoot, function(jobId)
    if type(jobId) ~= "string" or not jobsById[jobId] then return end
    if not nearbyJobId then bindKey(KEY, "down", onKey) end
    nearbyJobId = jobId
end)

addEvent("jobmanager:hideJoinHint", true)
addEventHandler("jobmanager:hideJoinHint", resourceRoot, function()
    if nearbyJobId then unbindKey(KEY, "down", onKey) end
    nearbyJobId = nil
end)
