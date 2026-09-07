local sw,sh = guiGetScreenSize()

local header_color      = tocolor(0,0,0, 0)
local secheader_color   = tocolor(0,100,150, 255)
local infoline_txtcolor = tocolor(0,170,220, 255)
local btn_color         = tocolor(20,20,20, 150)
local btnselect_color   = tocolor(255,255,255, 255)

local w,h               = sw*0.8,sh*0.8
local sepLine           = 3
local header_h          = 45+20
local infoline_h        = 30
local sectionW,elementH = w/3-sepLine,30
local image_h           = sectionW*0.6
local default_image     = "images/job_bg_default.jpg"

show_lobbypanel = false
local c_menu_id = 1
local c_selected_btn = 1

function render_ui_lobby()
    if getElementData(localPlayer, "paused") then return end
    if show_lobbypanel then
        --dxDrawRectangle(sw/2-w/2,sh/2-h/2, w,h, tocolor(0,0,0, 40))
        
        -- draw header
        dxDrawRectangle(sw/2-w/2,sh/2-h/2, w,header_h, header_color)
        dxDrawText(job_name, sw/2-w/2+5,sh/2-h/2+5, _,_, tocolor(255,255,255,255), 2.2, "default-bold", "left", "top")
        dxDrawText(job_desc, sw/2-w/2+5,sh/2-h/2+header_h-8, _,_, tocolor(255,255,255,255), 1.4, "default", "left", "bottom")
        
        -- draw LEFT section
        dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h, sectionW,elementH, secheader_color)
        dxDrawText("SETTINGS", sw/2-w/2+sectionW/2, sh/2-h/2+header_h+elementH/2, _,_, btntxtcolor, 1.6, "default-bold", "center", "center")
        
        for i,btn in ipairs(lobby_menus[c_menu_id].btns) do
            -- draw button
            local btnbgcolor = btn.bg or btn_color
            local btntxtcolor = tocolor(255,255,255, 255)
            if (c_selected_btn == i) then
                btnbgcolor = btnselect_color
                btntxtcolor = tocolor(0,0,0, 255)
            end
            dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), sectionW,elementH, btnbgcolor)
            dxDrawText(btn.text, sw/2-w/2+5, (sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)))+elementH/2, _,_, btntxtcolor, 1.6, "default", "left", "center")
            -- options
            if (btn.options) then
                local option_text = btn.options[btn.value].text
                if (c_selected_btn == i) then option_text = "< "..option_text.." >" end
                dxDrawText(option_text, sw/2-w/2+(sectionW-5), (sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)))+elementH/2, _,_, btntxtcolor, 1.6, "default", "right", "center")
            -- value
            elseif (btn.value) then
                --
            end
        end
        local btn_desc = lobby_menus[c_menu_id].btns[c_selected_btn].desc
        if (#btn_desc>0) then
            dxDrawRectangle(sw/2-w/2, sh/2-h/2+header_h+elementH+#lobby_menus[c_menu_id].btns*(elementH+sepLine)+sepLine, sectionW,infoline_h, btn_color)
            dxDrawText(btn_desc, sw/2-w/2+5,sh/2-h/2+header_h+elementH+#lobby_menus[c_menu_id].btns*(elementH+sepLine)+sepLine+elementH/2, _,_, tocolor(255,255,255,255), 1.5, "default", "left", "center")
        end
        
        -- draw CENTER section
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW), sh/2-h/2+header_h, sectionW,elementH, secheader_color)
        dxDrawText("PLAYERS "..#active_lobbys[lobby_id].players.." of "..job_min_players.."-"..job_max_players, sw/2-w/2+(sepLine+sectionW)+sectionW/2, sh/2-h/2+header_h+elementH/2, _,_, btntxtcolor, 1.6, "default-bold", "center", "center")
        
        for i=1, job_max_players do
            if (active_lobbys[lobby_id].players[i]) then
                dxDrawRectangle(sw/2-w/2+(sepLine+sectionW), sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), 5,elementH, tocolor(0,70,100, 255))
                dxDrawRectangle(sw/2-w/2+(sepLine+sectionW), sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), sectionW,elementH, tocolor(0,70,100, 150))
                dxDrawText(active_lobbys[lobby_id].players[i].name, sw/2-w/2+(sepLine+sectionW)+10, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.5, "default", "left", "center")
                dxDrawText(active_lobbys[lobby_id].players[i].level, sw/2-w/2+(sepLine+sectionW)+sectionW-10, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
                local level_w = dxGetTextWidth(active_lobbys[lobby_id].players[i].level, 1.6, "default", false)
                if active_lobbys[lobby_id].players[i].element == active_lobbys[lobby_id].host then -- is host
                    local pinfo_w = dxGetTextWidth("HOST", 1.2, "default", false)
                    dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)+sectionW-10-level_w-15-pinfo_w-5, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+5, 10+pinfo_w,elementH-10, tocolor(0,150,200, 200))
                    dxDrawText("HOST", sw/2-w/2+(sepLine+sectionW)+sectionW-10-level_w-15, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.2, "default", "right", "center")
                else
                    local pinfo_w = dxGetTextWidth("JOINED", 1.2, "default", false)
                    dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)+sectionW-10-level_w-15-pinfo_w-5, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+5, 10+pinfo_w,elementH-10, tocolor(0,200,0, 200))
                    dxDrawText("JOINED", sw/2-w/2+(sepLine+sectionW)+sectionW-10-level_w-15, sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine))+elementH/2, _,_, tocolor(255,255,255,255), 1.2, "default", "right", "center")
                end
            else
                dxDrawRectangle(sw/2-w/2+(sepLine+sectionW), sh/2-h/2+header_h+elementH+sepLine+((i-1)*(elementH+sepLine)), sectionW,elementH, btn_color)
            end
        end

        -- draw RIGHT section
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h, sectionW,elementH, secheader_color)
        dxDrawText("DETAILS", sw/2-w/2+(sepLine+sectionW)*2+sectionW/2, sh/2-h/2+header_h+elementH/2, _,_, btntxtcolor, 1.6, "default-bold", "center", "center")
        
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH, sectionW,image_h+elementH*4, tocolor(20,20,20, 255))
        
        dxDrawImage(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH, sectionW, image_h, job_bg)
        
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h-elementH, sectionW,elementH, tocolor(0,0,0, 150))
        dxDrawText(job_name, sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h-elementH/2, _,_, tocolor(255,255,255,255), 1.6, "sans", "right", "center")
        
        local index = 0
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h+elementH*index, sectionW,elementH, tocolor(50,50,50, 255))
        dxDrawText("Rating", sw/2-w/2+(sepLine+sectionW)*2+5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job_rating.."%", sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 1
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h+elementH*index, sectionW,elementH, tocolor(40,40,40, 255))
        dxDrawText("By", sw/2-w/2+(sepLine+sectionW)*2+5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job_creator, sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 2
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h+elementH*index, sectionW,elementH, tocolor(50,50,50, 255))
        dxDrawText("Opens at rank", sw/2-w/2+(sepLine+sectionW)*2+5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job_openrank, sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 3
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h+elementH*index, sectionW,elementH, tocolor(40,40,40, 255))
        dxDrawText("Players", sw/2-w/2+(sepLine+sectionW)*2+5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job_min_players.."-"..job_max_players, sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 4
        dxDrawRectangle(sw/2-w/2+(sepLine+sectionW)*2, sh/2-h/2+header_h+elementH+image_h+elementH*index, sectionW,elementH, tocolor(50,50,50, 255))
        dxDrawText("Type", sw/2-w/2+(sepLine+sectionW)*2+5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job_type, sw/2-w/2+(sepLine+sectionW)*2+sectionW-5, sh/2-h/2+header_h+elementH+image_h+elementH*index+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
    end
end
addEventHandler("onClientRender", getRootElement(), render_ui_lobby)


-- Controls

addEventHandler("onClientKey", getRootElement(),
function (key, isDown)
    if (isDown) then
        if getElementData(localPlayer, "paused") then return end
        if getElementData(localPlayer, "showChatInput") then return end

        if show_lobbypanel then
            if (key == "arrow_u") then
                if (c_selected_btn==1) then
                    c_selected_btn = #lobby_menus[c_menu_id].btns
                else
                    c_selected_btn = c_selected_btn-1
                end
                playSound("sounds/select.wav")
            elseif (key == "arrow_d") then
                if (c_selected_btn==#lobby_menus[c_menu_id].btns) then
                    c_selected_btn = 1
                else
                    c_selected_btn = c_selected_btn+1
                end
                playSound("sounds/select.wav")
            
            elseif (key == "arrow_l") then
                playSound("sounds/select.wav")
                if lobby_menus[c_menu_id].btns[c_selected_btn].options then
                    if (lobby_menus[c_menu_id].btns[c_selected_btn].value==1) then
                        lobby_menus[c_menu_id].btns[c_selected_btn].value = #lobby_menus[c_menu_id].btns[c_selected_btn].options
                    else
                        lobby_menus[c_menu_id].btns[c_selected_btn].value = lobby_menus[c_menu_id].btns[c_selected_btn].value-1
                    end
                end
            elseif (key == "arrow_r") then
                playSound("sounds/select.wav")
                if lobby_menus[c_menu_id].btns[c_selected_btn].options then
                    if (lobby_menus[c_menu_id].btns[c_selected_btn].value==#lobby_menus[c_menu_id].btns[c_selected_btn].options) then
                        lobby_menus[c_menu_id].btns[c_selected_btn].value = 1
                    else
                        lobby_menus[c_menu_id].btns[c_selected_btn].value = lobby_menus[c_menu_id].btns[c_selected_btn].value+1
                    end
                end

            elseif (key == "backspace" or key == "escape") then
                cancelEvent()
                playSound("sounds/select.wav")
                if (lobby_menus[c_menu_id].back == 0) then
                    leaveLobby()
                else
                    c_menu_id = lobby_menus[c_menu_id].back
                    c_selected_btn = 1
                end

            elseif (key == "enter") then
                playSound("sounds/click.wav")
                if (lobby_menus[c_menu_id].btns[c_selected_btn].set_menu) then
                    if ( lobby_menus[c_menu_id].btns[c_selected_btn].set_menu == 0 ) then
                        show_lobbypanel = false
                        uicore:toggleMoveControls(true)
                    else
                        c_menu_id = lobby_menus[c_menu_id].btns[c_selected_btn].set_menu
                        c_selected_btn = 1
                    end
                elseif lobby_menus[c_menu_id].btns[c_selected_btn].options then
                    lobby_menus[c_menu_id].btns[c_selected_btn].options[lobby_menus[c_menu_id].btns[c_selected_btn].value].action()
                elseif lobby_menus[c_menu_id].btns[c_selected_btn].action then
                    lobby_menus[c_menu_id].btns[c_selected_btn].action()
                end
            end
        end
    end
end)
