uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end
local sw,sh = guiGetScreenSize()
local safe_x,safe_y = uicore:getSafeZone()

local messages = {}
local input_text = ""
setElementData(localPlayer, "showChat", true)
setElementData(localPlayer, "showChatInput", false)
local max_char = 45
local max_messages = math.ceil((sh/2-200)/25)
local hide_message = 15 -- secs
outputDebugString("chat/max_char="..max_char)
outputDebugString("chat/max_messages="..max_messages)
outputDebugString("chat/hide_message="..hide_message)

function addMessage(sender, text)
    local msg_id = #messages+1
    table.insert( messages, msg_id, { sender=getPlayerName(sender), text=text, show=true, timer = nil } )
    messages[msg_id].timer = setTimer(function()
        messages[msg_id].show = false
    end, hide_message*1000, 1)
end
addEvent("addMessage", true)
addEventHandler("addMessage", getRootElement(), addMessage)

function renderChat()
    if (isChatVisible()) then showChat(false) end -- disable default chat

    if getElementData(localPlayer, "showChat") then
        -- draw messages
        for i, message in ipairs(ReverseTable(messages)) do
            if (i < max_messages) then
                if message.show or getElementData(localPlayer, "showChatInput") then
                    dxDrawText(
                        "#FFFFFF"..message.sender..": #dcdcdc"..message.text,
                        sw-safe_x, sh/2-((i-1)*25), _,_,
                        tocolor(255,255,255,255),
                        1.5, "default", "right", "bottom",
                        false, false, false, true
                    )
                end
            end
        end
        if getElementData(localPlayer, "showChatInput") then
            -- show input box
            local input_width = max_char*10
            dxDrawRectangle(
                sw-safe_x-(input_width), sh*0.5+10, (input_width),30,
                tocolor(0,0,0, 180)
            )
            dxDrawLine(
                sw-safe_x-(input_width), sh*0.5+10 +30-1,
                sw-safe_x, sh*0.5+10 +30-1,
                tocolor(255,255,255, 255),
                2
            )
            -- text
            local text_w = dxGetTextWidth(input_text, 1.5, "default", false)
            dxDrawText(
                input_text,
                sw-safe_x-(input_width)+5, sh*0.5+10+30/2, _,_,
                tocolor(255,255,255, 255),
                1.5, "default", "left", "center"
            )
            dxDrawLine(
                sw-safe_x-(input_width)+5+text_w, sh*0.5+10 +30-5,
                sw-safe_x-(input_width)+5+text_w+10, sh*0.5+10 +30-5,
                tocolor(255,255,255, 255),
                3
            )
        end
    end
end
addEventHandler("onClientRender", getRootElement(), renderChat)

-- input backend
addEventHandler("onClientCharacter", getRootElement(), function (char)
    if getElementData(localPlayer, "showChat") and getElementData(localPlayer, "showChatInput") then
        cancelEvent()
        if ( #input_text <= max_char ) then
            input_text = input_text..char
        end
    end
end)

addEventHandler("onClientKey", getRootElement(), function (btn, isPress)
    if isPress and getElementData(localPlayer, "showChat") and getElementData(localPlayer, "showChatInput") then
        cancelEvent()
        if btn=="backspace" then
            if (#input_text>0) then
                input_text = input_text:sub(1, #input_text - 1)
            end

        -- Send message
        elseif btn=="enter" then
            setElementData(localPlayer, "showChatInput", false)
            uicore:toggleMoveControls(true)
            if (input_text ~= "") then
                if (input_text[1] == "/") then
                    args = input_text:gmatch("%S+")
                    cmd = string.sub(args[1], 2, -1)
                    outputDebugString("cmd="..cmd)
                else
                    triggerServerEvent("sendMessageToAll", localPlayer, localPlayer, input_text)
                end
            end
            input_text = ""
        -- Close input
        elseif btn=="escape" then
            setElementData(localPlayer, "showChatInput", false)
            uicore:toggleMoveControls(true)
            input_text = ""
        end
    end
end)

bindKey("t", "down", function()
    -- Ha barmelyik panel nyitva van, a chatet ne lehessen megnyitni.
    if getElementData(localPlayer, "showChatInput") then return end
    if getElementData(localPlayer, "interactionMenuOpen")
    or getElementData(localPlayer, "socialPanelOpen")
    or getElementData(localPlayer, "phoneOpen")
    or getElementData(localPlayer, "reportPanelOpen") then
        return
    end
    uicore:toggleMoveControls(false)
    input_text = ""
    setTimer(setElementData, 10,1, localPlayer, "showChatInput", true)
end)

