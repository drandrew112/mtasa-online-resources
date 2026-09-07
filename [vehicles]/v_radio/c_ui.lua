uicore = exports.ui_core
local sx, sy = uicore:getScreenWH()
ui = function(z) return uicore:ui(z) end

radioOpen = false
selectedStation = 0
sound = nil

bindKey("q", "down", function()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    selectedStation = getElementData(veh, "radiostation_id") or 0
    radioOpen = true
    addEventHandler("onClientRender", root, drawRadioUI)
end)

bindKey("q", "up", function()
    radioOpen = false
    removeEventHandler("onClientRender", root, drawRadioUI)
end)

bindKey("mouse_wheel_up", "down", function()
    if not radioOpen then return end
    selectedStation = selectedStation + 1
    if selectedStation > #RADIO_STATIONS then selectedStation = 0 end
    applyStation()
end)

bindKey("mouse_wheel_down", "down", function()
    if not radioOpen then return end
    selectedStation = selectedStation - 1
    if selectedStation < 0 then selectedStation = #RADIO_STATIONS end
    applyStation()
end)

local hasIcon = {1,10}

function drawRadioUI()
    local cx, cy = sx / 2, sy / 2

    dxDrawRectangle(0, 0, sx, sy, tocolor(0,0,0,160))

    local radius = ui(350)
    local count = #RADIO_STATIONS + 1

    for i = 0, #RADIO_STATIONS do
        local angle = (i / count) * math.pi * 2 + math.pi / 2
        local x = cx + math.cos(angle) * radius
        local y = cy + math.sin(angle) * radius

        local size = (i == selectedStation) and ui(80) or ui(80)
        local bg_size = size*1.3

        local station_name = i == 0 and "" or (RADIO_STATIONS[i].name)
        local img = i == 0 and "images/station_off.png" or ("images/station_"..i..".png")
        local flag_img = i == 0 and "images/station_off.png" or ("images/flags/"..RADIO_STATIONS[i].country..".png")

        -- kijelölt kék körvonal
        if i == selectedStation then
            -- külső kék kör
            dxDrawCircle(x, y, bg_size/2 + 15, 0, 360,
                tocolor(0,140,255,140),
                tocolor(0,140,255,140),
                128
            )
            -- belső kivágás (áttetsző fekete)
            dxDrawCircle(x, y, bg_size/2 + 12, 0, 360,
                tocolor(0,0,0,140),
                tocolor(0,0,0,140),
                128
            )
        else
            -- külső kör
            dxDrawCircle(x, y, bg_size/2 + 7, 0, 360,
                tocolor(140,140,140,140),
                tocolor(140,140,140,140),
                128
            )
            -- belső kivágás
            dxDrawCircle(x, y, bg_size/2 + 5, 0, 360,
                tocolor(0,0,0,140),
                tocolor(0,0,0,140),
                128
            )
        end

        -- ikon
        if (i==0) or (RADIO_STATIONS[i].hasIcon) then -- radio off or hasIcon true
            dxDrawImage(x - size/2, y - size/2, size, size, img)
        else
            dxDrawText(station_name, x, y, _,_, tocolor(255,255,255,255), ui(1), "default", "center", "center")
        end
        -- flag
        if i ~= 0 then
            dxDrawImage(x + size/3, y + size/3, 30,20, flag_img)
        end
    end

    -- középső szöveg
    local stationName = "Radio off"
    if selectedStation ~= 0 and RADIO_STATIONS[selectedStation] then
        dxDrawImage(cx-20,cy-80,40,25, "images/flags/"..RADIO_STATIONS[selectedStation].country..".png")
        stationName = RADIO_STATIONS[selectedStation].name
    end

    dxDrawText(
        stationName,
        cx, cy - 80, _,_,
        tocolor(255,255,255,220),
        ui(1.5),
        "default-bold",
        "center",
        "bottom", false, false
    )

    -- vezérlés súgó a jobb alsó sarokban (ui_pause stílusú info sáv)
    local hint = "MOUSE WHEEL  Change station"
    local pad = ui(16)
    local barH = ui(30)
    local barW = dxGetTextWidth(hint, ui(1), "default-bold") + pad * 2
    dxDrawRectangle(sx - barW, sy - barH, barW, barH, tocolor(0, 0, 0, 200))
    dxDrawText(
        hint,
        sx - barW + pad, sy - barH, sx - pad, sy,
        tocolor(235, 235, 235, 255),
        ui(1),
        "default-bold",
        "right",
        "center"
    )
end


