if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end
local sw,sh = guiGetScreenSize()
local safe_x,safe_y = uicore:getSafeZone()

local messages = {} -- { lines = { colour coded line, ... }, time = tick }
local input_text = ""
setElementData(localPlayer, "showChat", true)
setElementData(localPlayer, "showChatInput", false)
local max_char = 150 -- same as MAX_CHARS in s_chat.lua
local hide_message = 30 -- secs
local fade_time = 1000 -- ms, fade-out at the end of hide_message
local keep_messages = 100 -- older messages are dropped

local FONT_SCALE = 1.5
local LINE_H = 25
local PAD = 8
local CHAT_W = math.min(620, math.floor(sw*0.45)) -- messages wrap at this width, input box is this wide
local INPUT_H = 30
local input_y = math.floor(sh*0.78) -- top of the input box
local messages_bottom = input_y - 10 -- bottom of the newest message line
local max_lines = math.floor((messages_bottom - sh*0.35)/LINE_H)
outputDebugString("chat/max_char="..max_char)
outputDebugString("chat/max_lines="..max_lines)
outputDebugString("chat/hide_message="..hide_message)

local function textWidth(text)
    return dxGetTextWidth(text, FONT_SCALE, "default", true)
end

local function lastColour(text)
    local colour
    for code in text:gmatch("#%x%x%x%x%x%x") do colour = code end
    return colour
end

-- colour coded text -> lines no wider than width; every line continues the colour of the previous one
local function wrapText(text, width)
    local lines, line, colour = {}, "", ""
    local function push(l)
        lines[#lines+1] = l
        colour = lastColour(l) or colour
    end
    for word in text:gmatch("%S+") do
        local candidate = (line == "") and word or (line.." "..word)
        if line ~= "" and textWidth(candidate) > width then
            push(line)
            line = colour..word
        else
            line = candidate
        end
        -- a single word wider than the line: cut it
        while textWidth(line) > width do
            local k = utf8.len(line) - 1
            while k > 1 and textWidth(utf8.sub(line, 1, k)) > width do k = k-1 end
            push(utf8.sub(line, 1, k))
            line = colour..utf8.sub(line, k+1)
        end
    end
    if line ~= "" then push(line) end
    return lines
end

function addMessage(sender, text)
    local name = getElementData(sender, "displayName") or getPlayerName(sender)
    messages[#messages+1] = {
        lines = wrapText(L("v_chat.chat.text", { sender = name, text = text }), CHAT_W - PAD*2),
        time = getTickCount(),
    }
    if #messages > keep_messages then table.remove(messages, 1) end
end
addEvent("addMessage", true)
addEventHandler("addMessage", getRootElement(), addMessage)

function renderChat()
    if (isChatVisible()) then showChat(false) end -- disable default chat

    if getElementData(localPlayer, "showChat") then
        local inputOpen = getElementData(localPlayer, "showChatInput")
        local now = getTickCount()
        local right = sw-safe_x
        local left = right - CHAT_W

        -- visible lines, newest first
        local visible = {}
        for m = #messages, 1, -1 do
            local message = messages[m]
            local alpha = 255
            if not inputOpen then
                local left_ms = hide_message*1000 - (now - message.time)
                if left_ms <= 0 then break end -- older ones are hidden too
                alpha = math.min(255, math.floor(255*left_ms/fade_time))
            end
            for l = #message.lines, 1, -1 do
                if #visible >= max_lines then break end
                visible[#visible+1] = { text = message.lines[l], alpha = alpha }
            end
            if #visible >= max_lines then break end
        end

        -- dark backdrop behind the messages while typing
        if inputOpen and #visible > 0 then
            local top = messages_bottom - #visible*LINE_H - PAD
            dxDrawRectangle(left, top, CHAT_W, messages_bottom + PAD - top, tocolor(0,0,0, 130))
        end

        for i, line in ipairs(visible) do
            dxDrawText(
                line.text,
                right - PAD, messages_bottom-((i-1)*LINE_H), _,_,
                tocolor(255,255,255,line.alpha),
                FONT_SCALE, "default", "right", "bottom",
                false, false, false, true
            )
        end

        if inputOpen then
            -- show input box
            dxDrawRectangle(left, input_y, CHAT_W, INPUT_H, tocolor(0,0,0, 180))
            dxDrawLine(left, input_y+INPUT_H-1, right, input_y+INPUT_H-1, tocolor(255,255,255, 255), 2)
            -- character counter
            local counter = L.len(input_text).."/"..max_char
            local counter_w = dxGetTextWidth(counter, 1, "default") + 10
            dxDrawText(counter, right-5, input_y+INPUT_H/2, _,_, tocolor(160,160,160, 255), 1, "default", "right", "center")
            -- text: only the end that fits in the box
            local shown = input_text
            local area_w = CHAT_W - 10 - counter_w - 12
            -- dxGetTextWidth, not L.width: L.width would cache every trimmed variant
            while shown ~= "" and dxGetTextWidth(shown, FONT_SCALE, "default") > area_w do
                shown = utf8.sub(shown, 2)
            end
            local text_w = L.width(shown, FONT_SCALE, "default", false)
            dxDrawText(
                shown,
                left+5, input_y+INPUT_H/2, _,_,
                tocolor(255,255,255, 255),
                FONT_SCALE, "default", "left", "center"
            )
            dxDrawLine(
                left+5+text_w, input_y+INPUT_H-5,
                left+5+text_w+10, input_y+INPUT_H-5,
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
        if ( L.len(input_text) < max_char ) then
            input_text = input_text..char
        end
    end
end)

addEventHandler("onClientKey", getRootElement(), function (btn, isPress)
    if isPress and getElementData(localPlayer, "showChat") and getElementData(localPlayer, "showChatInput") then
        cancelEvent()
        if btn=="backspace" then
            if (#input_text>0) then
                input_text = L.sub(input_text, 1, -2)
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
    -- v_introduce: a szerver bemutato alatt csak akkor, ha eppen a chatet tanitja
    local introAllow = getElementData(localPlayer, "intro.allow")
    if type(introAllow) == "table" and not introAllow.chat then return end
    if getElementData(localPlayer, "interactionMenuOpen")
    or getElementData(localPlayer, "socialPanelOpen")
    or getElementData(localPlayer, "phoneOpen")
    or getElementData(localPlayer, "reportPanelOpen")
    or getElementData(localPlayer, "adminPanelOpen") then
        return
    end
    uicore:toggleMoveControls(false)
    input_text = ""
    setTimer(setElementData, 10,1, localPlayer, "showChatInput", true)
end)

