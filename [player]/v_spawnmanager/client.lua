
--# Halál DX #--

local sw,sh = guiGetScreenSize()

local isDead = false
local showText = false
local bgA = 0
local deathCam = nil -- A halál pillanatában rögzített kamerapozíció.

function updateDeathCamera()
    if not deathCam then return end
    local t = (getTickCount() - deathCam.start) / 1000
    local angle = deathCam.angle + t * 8 -- lassú körbepásztázás fok/mp
    local rad = math.rad(angle)
    local dist = 4
    setCameraMatrix(
        deathCam.x + math.cos(rad) * dist, deathCam.y + math.sin(rad) * dist, deathCam.z + 5,
        deathCam.x, deathCam.y, deathCam.z - 1,
        0, 70
    )
end

-- the death camera and the WASTED screen are attached only between death and respawn
local deathRender = false
local function setDeathRender(on)
    if on == deathRender then return end
    deathRender = on
    if on then
        addEventHandler("onClientPreRender", root, updateDeathCamera)
        addEventHandler("onClientRender", root, dxHalal)
    else
        removeEventHandler("onClientPreRender", root, updateDeathCamera)
        removeEventHandler("onClientRender", root, dxHalal)
    end
end

function drawWasted()
    setElementData(localPlayer, "hideHUD", true)

    local sound = playSound("wasted.mp3")

    local px,py,pz = getElementPosition(localPlayer)
	deathCam = { x = px, y = py, z = pz, angle = 45, start = getTickCount() }
	updateDeathCamera()

    isDead = true
    setDeathRender(true)
    setTimer(function()
        bgA = bgA+3
    end, 20, 50)

    setTimer(function()
        showText = true
        setTimer(function()
            fadeCamera(false, 3)		
            setTimer(function()
                isDead = false
                showText = false
                bgA = 0
                deathCam = nil
                setDeathRender(false)
                triggerServerEvent("respawnAfterWasted", localPlayer)
                fadeCamera(true)
                setElementData(localPlayer, "hideHUD", false)
            end, 4*1000, 1)
        end, 4*1000, 1)
	end, 2*1000, 1)
end
addEvent("drawWasted", true)
addEventHandler("drawWasted", getRootElement(), drawWasted)

function dxHalal()
    if (isDead) then
        dxDrawRectangle(0, sh*0.4-60, sw, 120, tocolor(0,0,0,bgA))
        if showText then
            dxDrawText("WASTED", (sw/2), (sh*0.4), _,_, tocolor(255,0,0,255), 3, "pricedown", "center", "center")
        end
    end
end

-- /pos: the server checks the admin level (5+), saves the position and answers with pos:saved
addCommandHandler("pos", function()
    triggerServerEvent("pos:request", resourceRoot)
end)

addEvent("pos:saved", true)
addEventHandler("pos:saved", resourceRoot, function(text, x, y, z)
    outputChatBox(text)
    setClipboard(text)
    local marker = createMarker(x, y, z, "checkpoint", 4, 100, 100, 255, 150)
    createBlipAttachedTo(marker, 0, 1, 255, 255, 0, 255, 1, 3000)
end)
