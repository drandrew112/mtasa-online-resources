-- Static monitor screen (removable: delete this file and fx/screen.fx from meta.xml, or set
-- BAG.STATIC_SCREEN = false). One render target, drawn once (and again after a minimise), is put
-- on the screen texture of every monitor object. No live data.

if not BAG.STATIC_SCREEN then return end

local RT_W, RT_H = 512, 256
local rt, shader, textureName
local applied = {} -- object -> true

local function pickTextureName(model)
    local names = engineGetModelTextureNames(tostring(model)) or {}
    local wanted = BAG.MONITOR_SCREEN_TEXTURE
    for _, name in ipairs(names) do
        if wanted and name:lower() == wanted:lower() then return name end
    end
    for _, pattern in ipairs({ "screen", "monitor", "display", "tv" }) do
        for _, name in ipairs(names) do
            if name:lower():find(pattern, 1, true) then return name end
        end
    end
    outputDebugString(("[med_bag] no screen texture found on model %d, textures: %s - set BAG.MONITOR_SCREEN_TEXTURE"):format(
        model, table.concat(names, ", ")), 2)
    return nil
end

-- A Lifepak-like picture: HR + a flat ECG, SpO2, NIBP
local function drawPicture()
    if not rt then return end
    dxSetRenderTarget(rt, true)
    dxDrawRectangle(0, 0, RT_W, RT_H, tocolor(8, 10, 9))
    local green, cyan, orange, grey = tocolor(80, 220, 150), tocolor(110, 190, 245), tocolor(240, 150, 120), tocolor(130, 130, 125)
    dxDrawText("HR", 14, 10, 0, 0, green, 1.4, "default-bold")
    dxDrawText("78", 14, 30, 0, 0, green, 4, "default-bold")
    -- ECG trace
    local baseY, x = 70, 140
    local pts = { { 0, 0 }, { 30, 0 }, { 38, -8 }, { 44, 0 }, { 56, 0 }, { 62, -50 }, { 68, 22 }, { 74, 0 }, { 100, 0 } }
    while x < RT_W - 20 do
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            dxDrawLine(x + a[1], baseY + a[2], x + b[1], baseY + b[2], green, 2)
        end
        x = x + 100
    end
    dxDrawLine(0, 128, RT_W, 128, tocolor(40, 44, 42), 1)
    dxDrawText("SpO2", 14, 138, 0, 0, cyan, 1.4, "default-bold")
    dxDrawText("98", 14, 160, 0, 0, cyan, 3.5, "default-bold")
    dxDrawText("NIBP", 260, 138, 0, 0, orange, 1.4, "default-bold")
    dxDrawText("122/78", 260, 160, 0, 0, orange, 3, "default-bold")
    dxDrawText("LIFEPAK 15", 14, RT_H - 24, 0, 0, grey, 1.2, "default-bold")
    dxDrawText("200 J", RT_W - 70, RT_H - 24, 0, 0, grey, 1.2, "default-bold")
    dxSetRenderTarget()
end

local function isMonitorObject(obj)
    local model = getElementModel(obj)
    local def = BAG.MODELS.monitor
    return model == def.id or model == def.fallback
end

local function applyTo(obj)
    if applied[obj] or not shader then return end
    if not textureName then
        textureName = pickTextureName(getElementModel(obj))
        if not textureName then return end
    end
    engineApplyShaderToWorldTexture(shader, textureName, obj)
    applied[obj] = true
end

local function scan()
    for obj in pairs(applied) do
        if not isElement(obj) then applied[obj] = nil end
    end
    -- server objects of this resource (on the ground) and the local hand objects (client/carry.lua)
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        if not applied[obj] and isMonitorObject(obj) and getElementData(obj, BAG_DATA.KIND) ~= "anchor" then
            applyTo(obj)
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    rt = dxCreateRenderTarget(RT_W, RT_H, false)
    shader = dxCreateShader("fx/screen.fx", 0, 0, false, "object")
    if not rt or not shader then
        outputDebugString("[med_bag] static monitor screen disabled (render target / shader failed)", 2)
        return
    end
    dxSetShaderValue(shader, "gTexture", rt)
    drawPicture()
    setTimer(scan, 1000, 0)
end)

-- /bagscreen: puts the picture on the next texture of the monitor model and names it, to find the
-- screen texture of a model (then set BAG.MONITOR_SCREEN_TEXTURE)
local cycleNames, cycleIndex

addCommandHandler("bagscreen", function()
    if not shader then return end
    local model = BAG.MODELS.monitor.id
    for obj in pairs(applied) do
        if isElement(obj) then model = getElementModel(obj) break end
    end
    cycleNames = cycleNames or engineGetModelTextureNames(tostring(model)) or {}
    if #cycleNames == 0 then return end
    cycleIndex = (cycleIndex or 0) % #cycleNames + 1
    for obj in pairs(applied) do
        if isElement(obj) and textureName then engineRemoveShaderFromWorldTexture(shader, textureName, obj) end
    end
    applied = {}
    textureName = cycleNames[cycleIndex]
    scan()
    showBagNotification("Monitor screen test", ("%d/%d: %s"):format(cycleIndex, #cycleNames, textureName))
end)

-- render targets lose their content on minimise
addEventHandler("onClientRestore", root, function(cleared)
    if cleared then drawPicture() end
end)
