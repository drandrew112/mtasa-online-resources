-- Admin test menu (ui_inac temp menu), opened by the server after the admin check.
--   Preview: visual only, laid over your real state on this client (medfxSetPreview)
--   On yourself: real medsys changes (checked again on the server)
--   Animation peds: test peds for the forced animations
-- /medfxstop clears the preview (e.g. from behind a blackout preview).

if not MEDFX_TEST.ENABLED then return end

addEvent("medfx:testMenu", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local menuId
local blackoutTimer

local function item(label, desc, value)
    return { label = label, desc = desc, value = value, closeOnSelect = false }
end

local function sub(label, desc, items)
    return { label = label, title = label, desc = desc, items = items }
end

local function buildItems(peds)
    local preview = {
        sub("Consciousness", "Dazed, unconscious and clinical death screens", {
            item("Dazed", "Vignette, shake, no sprint / jump", { p = "status", v = "dazed" }),
            item("Unconscious (10 s)", "Blackout + control lock, ends by itself", { p = "status", v = "unconscious" }),
            item("Clinical death (10 s)", "Blackout with the countdown", { p = "status", v = "clinical_death" }),
            item("Normal", "Removes the consciousness preview", { p = "status", v = false }),
        }),
        sub("Pain", "Red pulse with the heartbeat, shake from 70", {
            item("Pain 50", nil, { p = "pain", v = 50 }), item("Pain 90", nil, { p = "pain", v = 90 }),
            item("No pain", nil, { p = "pain", v = false }),
        }),
        sub("Bleeding", "Blood at the screen edges", {
            item("Mild", nil, { p = "bleeding", v = 1 }), item("Severe", nil, { p = "bleeding", v = 2 }),
            item("Critical", nil, { p = "bleeding", v = 3 }), item("None", nil, { p = "bleeding", v = false }),
        }),
        sub("SpO2", "Tunnel vision", {
            item("SpO2 86%", nil, { p = "spo2", v = 86 }), item("SpO2 72%", nil, { p = "spo2", v = 72 }),
            item("Normal", nil, { p = "spo2", v = false }),
        }),
        sub("Blood loss", "Pale picture", {
            item("Blood 70%", nil, { p = "blood", v = 70 }), item("Blood 55%", nil, { p = "blood", v = 55 }),
            item("Normal", nil, { p = "blood", v = false }),
        }),
        item("Leg fracture controls", "No sprint / jump (toggle)", { p = "controls" }),
        item("Injury flash", "The flash of a new injury", { flash = true }),
        item("Clear preview", "Back to your real state", { clearPreview = true }),
    }

    local real = {
        item("Dazed", "Knockout for the medsys knockout time", { self = "dazed" }),
        item("Unconscious", "Knockout - /" .. MEDFX_TEST.COMMAND .. " heal wakes you", { self = "unconscious" }),
        item("Pain 85", "Pain spike, fades", { self = "pain" }),
        item("Mild bleeding", nil, { self = "bleed1" }),
        item("Critical bleeding", "You will lose blood fast", { self = "bleed3" }),
        item("SpO2 80%", "Recovers by itself", { self = "spo2" }),
        item("Blood volume 66%", nil, { self = "blood" }),
        item("Left leg fracture", "No sprint / jump, limping", { self = "legFracture" }),
        item("Right arm fracture", "No aiming", { self = "armFracture" }),
        item("Heal completely", nil, { self = "heal" }),
    }

    local pedItems = {}
    for i, ped in ipairs(peds or {}) do pedItems[i] = item(ped.label, nil, { ped = ped.id }) end
    pedItems[#pedItems + 1] = item("Remove my test peds", nil, { clear = true })

    return {
        sub("Preview (visual only)", "Only on your screen, medsys is not changed", preview),
        sub("On yourself (medsys)", "Real medical changes on your character", real),
        sub("Animation peds", "Forced patient animations", pedItems),
    }
end

local function setPreviewField(field, value)
    local overlay = {}
    for k, v in pairs(medfxGetPreview() or {}) do overlay[k] = v end

    if field == "controls" then
        overlay.controls = not overlay.controls and { "sprint", "jump" } or nil
    else
        overlay[field] = value or nil
    end
    if field == "status" then
        overlay.deathLeft = value == "clinical_death" and 300 or nil
        if isTimer(blackoutTimer) then killTimer(blackoutTimer) end
        blackoutTimer = nil
        -- a blackout preview ends by itself, the menu is behind it
        if value == "unconscious" or value == "clinical_death" then
            blackoutTimer = setTimer(function()
                blackoutTimer = nil
                local current = medfxGetPreview()
                if current and current.status == value then setPreviewField("status", false) end
            end, 10000, 1)
        end
    end
    medfxSetPreview(next(overlay) and overlay or nil)
end

addEventHandler("medfx:testMenu", resourceRoot, function(peds)
    local uiInac = getResourceFromName("ui_inac")
    if not uiInac or not getResourceRootElement(uiInac) then
        outputChatBox(("[MEDFX] ui_inac is not running, use /%s <action>"):format(MEDFX_TEST.COMMAND), 255, 90, 90)
        return
    end
    if exports.ui_inac:isTempMenuOpen() then return end
    menuId = exports.ui_inac:createTempMenu({ title = "Medical effects test", items = buildItems(peds) })
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(rootMenuId, value)
    if not menuId or rootMenuId ~= menuId or type(value) ~= "table" then return end
    if value.p then
        setPreviewField(value.p, value.v)
    elseif value.flash then
        medfxHitFlash()
    elseif value.clearPreview then
        medfxSetPreview(nil)
    else
        triggerServerEvent("medfx:testAction", resourceRoot, value)
    end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(rootMenuId)
    if rootMenuId == menuId then menuId = nil end
end)

addCommandHandler("medfxstop", function()
    if medfxGetPreview() then
        medfxSetPreview(nil)
        outputChatBox("[MEDFX] Preview cleared.", 255, 210, 74)
    end
end)
