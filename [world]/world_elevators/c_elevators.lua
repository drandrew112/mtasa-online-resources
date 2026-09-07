uicore = exports.ui_core
setDevelopmentMode(true)

local sw,sh = guiGetScreenSize()

local elevator_id = nil
local showSelector = false

function initSelector()
    if elevator_id then
        for i,floor in ipairs( elevators[elevator_id].floors ) do
            outputChatBox("init elev "..elevator_id.." | floor: "..floor.name.." "..i)
            table.insert( btns, { text = floor.name, floor_id = i } )
        end
        showSelector = true
        uicore:toggleMoveControls(false)
    end
end
function clearSelector()
    uicore:toggleMoveControls(true)
    showSelector = false
    btns = nil
    btns = {}
    selectedBtn = 1
end

btns = {}
selectedBtn = 1

local btnW, btnH = sw*0.3, 35

function render()
    if showSelector then
        dxDrawRectangle(10,10, (btnW)+10,(#btns*btnH)+65, tocolor(0,0,0,150))
        dxDrawRectangle(15,15, btnW, 50, tocolor(100,100,200,255))
        dxDrawText("ELEVATOR", 15+(btnW/2),15+23, _,_, tocolor(255,255,255,255), 1.7, "pricedown", "center", "center")
        for i,btn in ipairs(btns) do
            if (selectedBtn == i) then
                dxDrawRectangle(15,70+((i-1)*btnH), btnW,btnH, tocolor(255,255,255,200))
                dxDrawText(btn.text, 20,(70+((i-1)*btnH))+btnH/2, _,_, tocolor(20,20,20,255), 1.7, "default", "left", "center")
            else
                dxDrawRectangle(15,70+((i-1)*btnH), btnW,btnH, tocolor(20,20,20,200))
                dxDrawText(btn.text, 20,(70+((i-1)*btnH))+btnH/2, _,_, tocolor(255,255,255,255), 1.7, "default", "left", "center")
            end
        end
    elseif showHelp then
        dxDrawText("Press E to use elevator", sw/2,30, _,_, tocolor(255,255,255,255), 1.5, "default", "center", "center")
    end
end
addEventHandler("onClientRender", getRootElement(), render)

addEventHandler("onClientKey", getRootElement(),
function (key, isDown)
    if (isDown and showSelector) then
        if (key == "arrow_u") then
            if (selectedBtn==1) then
                selectedBtn = #btns
            else
                selectedBtn = selectedBtn-1
            end
        elseif (key == "arrow_d") then
            if (selectedBtn==#btns) then
                selectedBtn = 1
            else
                selectedBtn = selectedBtn+1
            end
        elseif (key == "enter") then
            showSelector = false
            fadeCamera(false)
            showHelp = false
            setTimer(function()
                local floor_id = btns[selectedBtn].floor_id
                local floor = elevators[elevator_id].floors[floor_id]
                local x,y,z = floor.x,floor.y,floor.z
                setElementPosition(localPlayer, x,y,z)
                fadeCamera(true)
                uicore:toggleMoveControls(true)
                clearSelector()
            end, 2000, 1)
        end
    end
end)

function toggleSelector()
    if showSelector then
        clearSelector()
    else
        initSelector()
    end
end

addEventHandler("onClientColShapeHit", getResourceRootElement(),
function ()
    if getElementData(source, "elevator") then
        elevator_id = getElementData(source, "elevator_id")
        showHelp = true
        bindKey("e", "down", toggleSelector)
    end
end)

addEventHandler("onClientColShapeLeave", getResourceRootElement(),
function ()
    if getElementData(source, "elevator") then
        unbindKey("e", "down", toggleSelector)
        clearSelector()
        showHelp = false
        elevator_id = nil
    end
end)

