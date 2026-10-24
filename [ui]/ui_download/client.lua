if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
local uicore = exports["ui_core"]
local sw,sh = uicore:getScreenWH()
local safe_x, safe_y = uicore:getSafeZone()

local isDownloading = false
local res_name = "res_name"
local file_name = "file_name"
local file_size = "file_size"
local progresz = "80"
local downloaded = "69"
local total = "96"

local discord = "https://discord.gg/pGagxbRkS4"

local bg_img = "bgs/1.png"

local roundedShader = dxCreateShader("rounded.fx")
local logoTex = dxCreateTexture("freev.png")
local logosize = uicore:ui(200)
local radius = 32

dxSetShaderValue(roundedShader, "radius", radius)
dxSetShaderValue(roundedShader, "size", logosize, logosize)
dxSetShaderValue(roundedShader, "sourceTexture", logoTex)

local debug_ds = false
local TEST_ADMIN_LEVEL = 5

-- Kulso letoltes (pl. v_modloader jarmu modellek, downloadFile): a resource maga
-- adja a haladast, nem a transfer box. { owner, title, done, total, label, cancellable }
local external = nil

local function screenActive()
    return isTransferBoxActive() or external ~= nil or debug_ds
end

-- A letolto kepernyo alatt elrejtjuk a HUD-ot (hideHUD = true). Amikor a
-- transfer box eltunik, EL kell engedni a flag-et (false), nem pedig a letoltes
-- kezdetekor rogzitett erteket visszaadni: ha a letoltes atfedett a login
-- panellel, az az ertek "true" volt, es belepes utan beragadt volna a rejtett
-- HUD/minimap. A HUD-ot elrejteni akaro resource-ok (login panel, pause menu)
-- ugyis minden kepkockaban / minden allapotvaltasnal ujra beallitjak.
local hudHiddenByUs = false

-- Letoltes kozben latszik az egermutato (minijatekok / menu). Csak akkor
-- kapcsoljuk ki, ha mi kapcsoltuk be, es a download:finished elott, hogy a
-- login panel mar a sajat kurzorallapotat allitsa be.
local cursorOn, cursorOwned = false, false

local function setCursor(on)
    if on then
        if not cursorOn then
            cursorOn = true
            cursorOwned = not isCursorShowing()
        end
        if not isCursorShowing() then
            showCursor(true)
            cursorOwned = true
        end
    elseif cursorOn then
        cursorOn = false
        if cursorOwned then showCursor(false) end
        cursorOwned = false
    end
end

-- minijatekok: csak letoltes kozben (vagy /downloadtest alatt) jatszhatok
MG.allowed = function() return screenActive() end
-- a teljes tartalom (logo + menu + kartyak, ~545 ui) a kepernyo kozepere kerul
local logoY = math.max(uicore:ui(20), (sh - uicore:ui(545)) / 2)
local gameAreaBottom = sh - safe_y - uicore:ui(120)

local function restoreHud()
    if not hudHiddenByUs then return end
    hudHiddenByUs = false
    setElementData(localPlayer, "hideHUD", false)
end

function render()
    if debug_ds and not isTransferBoxActive() then
        -- fake, animated progress a "letoltes" teszthez
        local pct = (getTickCount() / 60) % 100
        progresz = math.ceil(pct)
        total = 96
        downloaded = tonumber(string.format("%.2f", tostring(total * pct / 100)))
    end

    if screenActive() then
        hudHiddenByUs = true
        setElementData(localPlayer, "hideHUD", true)

        fadeCamera(false)
        setElementData(localPlayer, "download_screen", true)
        showChat(false)

        setCursor(true)

        dxDrawImage(0,0, sw,sh, bg_img)

        -- a jatek kozben a fejlec (logo + szoveg) helyet ad a jateknak
        local playing = MG.isPlaying()
        if not playing then
            dxDrawImage(
                sw/2-logosize-10,
                logoY,
                logosize,
                logosize,
                roundedShader
            )
            dxDrawText(L("ui_download.client.welcome_to_freev_while_you_wait"), sw/2+10, logoY+logosize/2, _,_, tocolor(255,255,255), uicore:ui(1.5), "default", "left", "center", false,false,false,true)
        end

        MG.draw(logoY + logosize + uicore:ui(95), gameAreaBottom)

        dxDrawText( L("ui_download.client.join_our_discord_community_press_c", { discord = discord }), sw/2, sh-safe_y, _,_, tocolor(255,255,255), uicore:ui(1.1), "default", "center", "bottom", false,false,false,true)

        local downloadtext
        if external and not isTransferBoxActive() then
            local pct = external.total > 0 and math.floor(external.done / external.total * 100) or 0
            downloadtext = L("ui_download.client.downloading_external", { label = external.label or external.title or "", progresz = pct })
        else
            downloadtext = L("ui_download.client.downloading_mb", { downloaded = downloaded, total = total, progresz = (progresz or "0") })
        end
        uicore:drawLoadingText(downloadtext)

        -- a megszakitas lehetosege, egy sorral a Downloading sor felett
        if external and external.cancellable then
            local hint = playing and L("ui_download.client.cancel_leave_game") or L("ui_download.client.cancel_hint")
            local scale = uicore:ui(1.4)
            local rowH = 25 * uicore:ui(1.7)
            local h = 25 * scale
            local w = L.width(hint, scale, "default", true) + 20
            local x, y = sw - safe_x - w, sh - safe_y - rowH - uicore:ui(6) - h
            dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 160))
            dxDrawText(hint, x + 10, y, x + w - 10, y + h, tocolor(255, 200, 90), scale, "default", "left", "center", false, false, false, true)
        end

        if getKeyState("c") then
            setClipboard(discord)
        end
    else
        -- nincs aktiv letoltes: visszaadjuk a HUD-ot, ha mi rejtettuk el
        restoreHud()
        setCursor(false)
        if MG.isPlaying() then MG.stop() end
    end
end

-- the render handler is attached only during a download (or /downloadtest); after removing it,
-- render() runs once more for the cleanup branch
local rendering = false
local function syncRender()
    local on = screenActive() and true or false
    if on == rendering then return end
    rendering = on
    if on then
        addEventHandler("onClientRender", root, render)
    else
        removeEventHandler("onClientRender", root, render)
        render()
    end
end
syncRender()

function on_fileDownload (res, file, size, state)
    --if state=="failed" then 
        res_name = getResourceName( res )
        file_name = file
        file_size = tonumber(string.format("%.2f", tostring(size/1024/1024) ))
    --end
end
addEventHandler ("onClientResourceFileDownload", root, on_fileDownload)

addEventHandler ("onClientTransferBoxProgressChange", root, function (downloadedSize, totalSize)
    local megvan = math.min ((downloadedSize / totalSize) * 100, 100)
    progresz = math.ceil(megvan)
    downloaded = tonumber(string.format("%.2f", tostring(downloadedSize/1024/1024) ))
    total = tonumber(string.format("%.2f", tostring(totalSize/1024/1024) ))
end)

-- MTA sometimes splits a download into several small chunks: the transfer box hides and shows again
-- right away. Wait 100ms after it hides and re-check before announcing the end of the download.
local FINISH_RECHECK_MS = 100
local finishTimer

local function finishDownload()
    finishTimer = nil
    if isTransferBoxActive() then return end -- still downloading, the next hide will retry
    isDownloading = false
    -- a kulso letoltes alatt felbukkano transfer box nem a csatlakozasi letoltes:
    -- a kepernyot az endExternal zarja, a download:finished nem sul el
    if external then return end

    if not debug_ds then
        setCursor(false)
        MG.stop()
    end
    fadeCamera(true)
    setElementData(localPlayer, "download_screen", false)
    restoreHud()

    triggerEvent("download:finished", root)
end

function on_TransferBoxVisibilityChange (state)
    syncRender()
    if state==true then
        isDownloading = true
        if isTimer(finishTimer) then killTimer(finishTimer) end
        finishTimer = nil
    elseif state==false then
        if isTimer(finishTimer) then killTimer(finishTimer) end
        finishTimer = setTimer(finishDownload, FINISH_RECHECK_MS, 1)
    end
end
addEventHandler ("onClientTransferBoxVisibilityChange", root, on_TransferBoxVisibilityChange)

-- /downloadtest: a letolto kepernyo elonezete, csak admin_level 7+ szamara
addCommandHandler("downloadtest", function()
    local level = tonumber(getElementData(localPlayer, "admin_level")) or 0
    if level < TEST_ADMIN_LEVEL then
        outputChatBox("#ff4444[downloadtest]#ffffff Nincs jogosultsagod ehhez a parancshoz.", 255, 255, 255, true)
        return
    end

    debug_ds = not debug_ds
    syncRender()

    if debug_ds then
        outputChatBox("#44ff44[downloadtest]#ffffff Teszt letolto kepernyo #00ff00BEKAPCSOLVA#ffffff.", 255, 255, 255, true)
    else
        outputChatBox("#44ff44[downloadtest]#ffffff Teszt letolto kepernyo #ff4444KIKAPCSOLVA#ffffff.", 255, 255, 255, true)

        setCursor(false)
        MG.stop()
        fadeCamera(true)
        showChat(true)
        hudHiddenByUs = false
        setElementData(localPlayer, "hideHUD", false)
        setElementData(localPlayer, "download_screen", false)
    end
end)


-- exports

function isDownloadingActive()
    return isDownloading
end

-- Kulso letoltes (a hivo resource adja a haladast):
--   beginExternal(title, cancellable)            a letolto kepernyo megjelenik
--   setExternalProgress(doneBytes, totalBytes, label)
--   endExternal()                                eltunik (a hivo resource leallasakor magatol is)
-- cancellable: Backspace (minijatekon kivul) -> "onClientDownloadCancel" a hivo resource-nak
-- (source = a hivo resource root eleme).
addEvent("onClientDownloadCancel")

local function closeExternal()
    if not external then return end
    external = nil
    if isTransferBoxActive() or debug_ds then return end
    setCursor(false)
    MG.stop()
    fadeCamera(true)
    setElementData(localPlayer, "download_screen", false)
    if getElementData(localPlayer, "loaded") == true then showChat(true) end
    syncRender()
end

function beginExternal(title, cancellable)
    external = {
        owner = sourceResource, title = title, done = 0, total = 0, label = title,
        cancellable = cancellable == true,
    }
    syncRender()
    return true
end

function setExternalProgress(done, totalBytes, label)
    if not external then return false end
    external.done, external.total = tonumber(done) or 0, tonumber(totalBytes) or 0
    if label then external.label = label end
    return true
end

function endExternal()
    closeExternal()
    return true
end

addEventHandler("onClientResourceStop", root, function(res)
    if external and external.owner == res then closeExternal() end
end)

-- a minijatek Backspace-e (core.lua) elobb fut es lemondja az eventet: az a jatekbol lep ki
addEventHandler("onClientKey", root, function(key, press)
    if not press or key ~= "backspace" or not external or not external.cancellable then return end
    if wasEventCancelled() or MG.isPlaying() then return end
    cancelEvent()
    local owner = external.owner
    if owner and getResourceState(owner) == "running" then
        triggerEvent("onClientDownloadCancel", getResourceRootElement(owner))
    else
        closeExternal()
    end
end)
