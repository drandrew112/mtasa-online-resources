-- Thumbnail photos: freecam with every HUD element hidden (shared "hideHUD"
-- element data + the editor's own helpers), a 16:9 frame guide, SPACE shoots.
-- The 16:9 middle of the screen is scaled to 640x360 and sent to the server as
-- JPEG; it is stored with the game on the next Save.

Photo = {}

local T = CREATOR.THUMB
local sw, sh = guiGetScreenSize()
local state = nil           -- { prevCam, prevHideHUD, prevChat, shootIn }
local preview = nil         -- texture of the last photo
local previewUntil = 0

local function frameRect()
    local w, h = sw, sw * 9 / 16
    if h > sh then h, w = sh, sh * 16 / 9 end
    return (sw - w) / 2, (sh - h) / 2, w, h
end

function Photo.start()
    if Editor.photo or Editor.testing then return end
    Tools.cancel()
    Menus.close()
    state = {
        prevCam = Editor.camMode,
        prevHideHUD = getElementData(localPlayer, "hideHUD"),
        prevChat = isChatVisible(),
        prevPos = { getElementPosition(localPlayer) },
    }
    Editor.photo = true
    if Editor.camMode ~= "free" then Freecam.start() end
    showCursor(false)
    setElementData(localPlayer, "hideHUD", true, false)
    showChat(false)
    View.setHelpersVisible(false)
    Editor.selected = nil
end

-- silent: closing the creator (no camera switching back)
function Photo.stop(silent)
    if not Editor.photo then return end
    Editor.photo = false
    setElementData(localPlayer, "hideHUD", state.prevHideHUD == true, false)
    showChat(state.prevChat)
    View.setHelpersVisible(true)
    if not silent then
        if state.prevCam == "foot" then
            Freecam.stop()
            setElementPosition(localPlayer, unpack(state.prevPos))
        else
            showCursor(true)
        end
    end
    state = nil
end

function Photo.key(key)
    if key == "space" then
        if not state.shootIn then state.shootIn = 3 end   -- frames without the frame guide
        return true
    end
    if key == "backspace" then Photo.stop() return true end
    return false
end

local function capture()
    local fx, fy, fw, fh = frameRect()
    local source = dxCreateScreenSource(sw, sh)
    local target = dxCreateRenderTarget(T.width, T.height)
    if not source or not target then
        if source then destroyElement(source) end
        if target then destroyElement(target) end
        notify("Could not take the photo (video memory).")
        return
    end
    dxUpdateScreenSource(source, true)
    dxSetRenderTarget(target, true)
    dxDrawImageSection(0, 0, T.width, T.height, fx, fy, fw, fh, source)
    dxSetRenderTarget()
    local pixels = dxGetTexturePixels(target)
    destroyElement(source)
    destroyElement(target)
    local jpeg = pixels and dxConvertPixels(pixels, "jpeg", T.quality)
    if not jpeg then notify("Could not take the photo.") return end

    triggerLatentServerEvent("jobcreator:thumbnail", 100000, false, resourceRoot, jpeg)
    Photo.setPreview(jpeg)
    Editor.hasThumb = true
    Editor.dirty = true
    notify("Photo taken. It is stored with the game when you save.")
end

function Photo.setPreview(bytes)
    if isElement(preview) then destroyElement(preview) end
    preview = dxCreateTexture(bytes)
    previewUntil = getTickCount() + 5000
end

function Photo.remove()
    if not Editor.hasThumb then notify("There is no photo.") return end
    triggerServerEvent("jobcreator:thumbnail", resourceRoot, false)
    Photo.clear()
    Editor.dirty = true
    notify("Photo removed (on the next save).")
end

function Photo.clear()
    if isElement(preview) then destroyElement(preview) end
    preview = nil
    Editor.hasThumb = false
end

-- the saved photo of an opened game
addEvent("jobcreator:thumbnailData", true)
addEventHandler("jobcreator:thumbnailData", resourceRoot, function(bytes)
    if not Editor.doc or type(bytes) ~= "string" then return end
    Photo.setPreview(bytes)
    previewUntil = 0
    Editor.hasThumb = true
end)

addEventHandler("onClientRender", root, function()
    if Editor.photo and state then
        if state.shootIn then
            state.shootIn = state.shootIn - 1
            if state.shootIn <= 0 then
                state.shootIn = nil
                capture()
                Photo.stop()
            end
            return
        end
        -- frame guide: darken what will be cut off
        local fx, fy, fw, fh = frameRect()
        local dim = tocolor(0, 0, 0, 150)
        if fy > 0 then
            dxDrawRectangle(0, 0, sw, fy, dim)
            dxDrawRectangle(0, fy + fh, sw, sh - fy - fh, dim)
        end
        if fx > 0 then
            dxDrawRectangle(0, 0, fx, sh, dim)
            dxDrawRectangle(fx + fw, 0, sw - fx - fw, sh, dim)
        end
        local c = tocolor(255, 255, 255, 120)
        dxDrawLine(fx + fw / 3, fy, fx + fw / 3, fy + fh, c)
        dxDrawLine(fx + fw * 2 / 3, fy, fx + fw * 2 / 3, fy + fh, c)
        dxDrawLine(fx, fy + fh / 3, fx + fw, fy + fh / 3, c)
        dxDrawLine(fx, fy + fh * 2 / 3, fx + fw, fy + fh * 2 / 3, c)
        dxDrawText("PHOTO MODE   SPACE take photo   ·   BACKSPACE cancel   ·   hold RMB to look, WASD / Q / E move",
            0, sh - 40, sw, sh - 10, tocolor(255, 255, 255), 1, "default-bold", "center", "center")
        return
    end
    -- preview after shooting, and while the hub is open
    if isElement(preview) and Editor.active and Editor.doc and (getTickCount() < previewUntil or Menus.kind == "hub") then
        local w = math.floor(sw * 0.18)
        local h = math.floor(w * 9 / 16)
        local x, y = sw - w - 20, sh - h - 60
        dxDrawRectangle(x - 3, y - 3, w + 6, h + 6, tocolor(0, 0, 0, 200))
        dxDrawImage(x, y, w, h, preview)
    end
end)
