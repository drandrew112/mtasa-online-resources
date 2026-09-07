local sw,sh = guiGetScreenSize()

local header_color      = tocolor(0,0,0, 0)
local secheader_color   = tocolor(0,100,150, 255)
local infoline_txtcolor = tocolor(0,170,220, 255)

local w,h               = sw*0.8,sh*0.8
local sepLine           = 3
local header_h          = 45+20
local infoline_h        = 30
local sectionW,elementH = w/3-sepLine,30

show_endJobPanel = false
endJobPanel_state = 1

local selected_option = 1
local vote_options = {"Random", 1,2,3,4,5, "Restart", "Freemode"}

function render_ui_endJob()
    if getElementData(localPlayer, "paused") then return end
    if show_endJobPanel then
        -- Player list
        if endJobPanel_state == 1 then
            --dxDrawRectangle(sw/2-w/2,sh/2-h/2, w,h, tocolor(0,0,0, 100))
            
            -- draw header
            dxDrawRectangle(sw/2-w/2,sh/2-h/2, w,header_h, header_color)
            dxDrawText(job_name, sw/2-w/2+5,sh/2-h/2+5, _,_, tocolor(255,255,255,255), 2, "default-bold", "left", "top")
            dxDrawText(job_desc, sw/2-w/2+5,sh/2-h/2+header_h-8, _,_, tocolor(255,255,255,255), 1.5, "default", "left", "bottom")
            
            -- draw CENTER section
            dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h, w,elementH, secheader_color)
            dxDrawText("PLAYERS", sw/2-w/2+5, sh/2-h/2+header_h+elementH/2, _,_, tocolor(255,255,255, 255), 1.6, "default-bold", "left", "center")
            
            for i,player in ipairs(active_lobbys[lobby_id].players) do
                dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), 5,elementH, tocolor(0,70,100, 255))
                dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), w,elementH, tocolor(0,70,100, 150))
                dxDrawText(player.name, sw/2-w/2+10, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.5, "default", "left", "center")
                dxDrawText(player.level, sw/2-w/2+w-10, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
                local level_w = dxGetTextWidth(active_lobbys[lobby_id].players[i].level, 1.6, "default", false)
                if active_lobbys[lobby_id].players[i].element == active_lobbys[lobby_id].host then -- is host
                    local pinfo_w = dxGetTextWidth("HOST", 1.2, "default", false)
                    dxDrawRectangle(sw/2-w/2+w-10-level_w-15-pinfo_w-5, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+5, 10+pinfo_w,elementH-10, tocolor(0,150,200, 200))
                    dxDrawText("HOST", sw/2-w/2+w-10-level_w-15, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.2, "default", "right", "center")
                else
                    local pinfo_w = dxGetTextWidth("JOINED", 1.2, "default", false)
                    dxDrawRectangle(sw/2-w/2+w-10-level_w-15-pinfo_w-5, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+5, 10+pinfo_w,elementH-10, tocolor(0,200,0, 200))
                    dxDrawText("JOINED", sw/2-w/2+w-10-level_w-15, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.2, "default", "right", "center")
                end
            end

        -- vote next job
        elseif endJobPanel_state == 2 then
            header_h = 45

            local votes = 0
            for i,v in ipairs(active_lobbys[lobby_id].players) do
                if v.voted then
                    votes = votes + 1
                end
            end
            dxDrawText("Vote on the next Job", sw/2-w/2,sh/2-h/2, _,_, tocolor(255,255,255, 255), 2.2, "default", "left", "top")
            dxDrawText(votes.."/"..#active_lobbys[lobby_id].players.." Votes", sw/2+w/2,sh/2-h/2, _,_, tocolor(255,255,255, 255), 2.2, "default", "right", "top")

            local rows = 3
            local cols = 3
            local padding = 4
            for i,v in ipairs(vote_options) do
                local gridW = (w - (cols - 1) * padding) / cols
                local gridH = gridW*0.6
                --outputDebugString("gridW, gridH: "..gridW..", "..gridH)

                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                
                local x = sw/2-w/2 + col * gridW + (col - 1) * (padding*2)
                local y = sh/2-h/2 + header_h + row * gridH + (row - 1) * (padding*2)

                if i >= 7 then gridH = gridH*0.3 end
                dxDrawRectangle(x, y, gridW, gridH, tocolor(0,0,0, 255))
                if i == 1 then
                    dxDrawImage(x, y, gridW, gridH, "images/job_random.jpg")
                    dxDrawRectangle(x,y+gridH-30, gridW,30, tocolor(0,0,0,150))
                    dxDrawText(v, x+gridW-5, y+gridH-15, _, _, tocolor(255,255,255,255), 1.5, "default-bold", "right", "center")
                elseif i <= 6 then
                    dxDrawImage(x, y, gridW, gridH, jobs[v].lobby.bg_img or "files/job_bg_default.jpg")
                    dxDrawRectangle(x,y+gridH-30, gridW,30, tocolor(0,0,0,150))
                    dxDrawText(jobs[v].name, x+gridW-5, y+gridH-15, _, _, tocolor(255,255,255,255), 1.5, "default-bold", "right", "center")
                else
                    dxDrawText(v, x + gridW / 2, y + gridH / 2, _, _, tocolor(255,255,255,255), 1.5, "default-bold", "center", "center")
                end
            end
            for i=1, #vote_options do
                if selected_option == i then
                    local gridW = (w - (cols - 1) * padding) / cols
                    local gridH = gridW*0.6
    
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    
                    local x = sw/2-w/2 + col * gridW + (col - 1) * (padding*2)
                    local y = sh/2-h/2 + header_h + row * gridH + (row - 1) * (padding*2)
                    if i >= 7 then gridH = gridH*0.3 end

                    local line_w = 4
                    dxDrawLine(x, y, x + gridW, y, tocolor(255, 255, 255, 255), line_w) -- Top
                    dxDrawLine(x, y, x, y + gridH, tocolor(255, 255, 255, 255), line_w) -- Left
                    dxDrawLine(x + gridW, y, x + gridW, y + gridH, tocolor(255, 255, 255, 255), line_w) -- Right
                    dxDrawLine(x, y + gridH, x + gridW, y + gridH, tocolor(255, 255, 255, 255), line_w) -- Bottom
                end
            end

        end
    end
end
addEventHandler("onClientRender", getRootElement(), render_ui_endJob)


-- Controls

addEventHandler("onClientKey", getRootElement(),
function (key, isDown)
    if (isDown) then
        if getElementData(localPlayer, "paused") then return end
        if getElementData(localPlayer, "showChatInput") then return end

        if show_endJobPanel then
            if endJobPanel_state == 1 then
            elseif endJobPanel_state == 2 then
                if key == "arrow_u" then -- up
                    if selected_option > 3 then
                        selected_option = selected_option - 3
                    end
                elseif key == "arrow_d" then -- down
                    if selected_option <= 3 then
                        selected_option = selected_option + 3
                    elseif selected_option <= 6 then
                        selected_option = #vote_options
                    end
                elseif key == "arrow_l" then -- left
                    if selected_option % 3 ~= 1 then
                        selected_option = selected_option - 1
                    end
                elseif key == "arrow_r" then -- right
                    if selected_option % 3 ~= 0 and selected_option ~= #vote_options then
                        selected_option = selected_option + 1
                    end
                elseif key == "enter" then
                    playSound("sounds/click.wav")
                    triggerServerEvent("onPlayerVote", localPlayer, localPlayer, lobby_id, vote_options[selected_option])

                -- Leave
                elseif (key == "backspace" or key == "escape") then
                    cancelEvent()
                    playSound("sounds/select.wav")
                
                end
            end
        end
    end
end)

-- handle vote events

addEvent("onVoteStart", true)
addEventHandler("onVoteStart", root, function()
    endJobPanel_state = 2
end)

addEvent("onVoteEnd", true)
addEventHandler("onVoteEnd", root, function()
    show_endJobPanel = false
    endJobPanel_state = 1
end)

