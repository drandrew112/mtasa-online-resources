uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local sw,sh = guiGetScreenSize()

local elementH = 30
local help_w = dxGetTextWidth("Press E to join a lobby", 1.5, "default")
local help_h = dxGetFontHeight(1.5, "default")

local w,h = sw*0.3, ((sw*0.)*0.6)+elementH*5
local sx,sy = 15, 20+help_h+sh*0.1
local image_h = w*0.6

show_jobmarker_panel = false
local c_job_id = false

function render_ui()
    if in_lobby or show_lobbypanel then return end
    if show_jobmarker_panel then
        dxDrawRectangle(15,15, help_w+10, help_h+10, tocolor(0,0,0,255))
        dxDrawText("Press E to join a lobby", 20,20, _,_, tocolor(255,255,255,255), 1.5, "default", "left", "top")

        local job = jobs[c_job_id]
        dxDrawRectangle(sx,sy, w,h, tocolor(0,0,0,255))
        
        dxDrawImage(sx,sy, w,image_h, job.lobby.bg_img)

        dxDrawRectangle(sx,sy+image_h-elementH, w,elementH, tocolor(0,0,0,150))
        dxDrawText(job.name, sx+w-5, sy+image_h-elementH/2, _,_, tocolor(255,255,255,255), 1.6, "sans", "right", "center")

        local index = 0
        dxDrawRectangle(sx,sy+image_h+(elementH*index), w,elementH, tocolor(50,50,50, 255))
        dxDrawText("Rating", sx+5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job.rating.."%", sx+w-5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 1
        dxDrawRectangle(sx,sy+image_h+(elementH*index), w,elementH, tocolor(40,40,40, 255))
        dxDrawText("By", sx+5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job.creator, sx+w-5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 2
        dxDrawRectangle(sx,sy+image_h+(elementH*index), w,elementH, tocolor(50,50,50, 255))
        dxDrawText("Opens at rank", sx+5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job.openrank, sx+w-5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 3
        dxDrawRectangle(sx,sy+image_h+(elementH*index), w,elementH, tocolor(40,40,40, 255))
        dxDrawText("Players", sx+5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job.min_players.."-"..job.max_players, sx+w-5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
        index = 4
        dxDrawRectangle(sx,sy+image_h+(elementH*index), w,elementH, tocolor(50,50,50, 255))
        dxDrawText("Type", sx+5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "left", "center")
        dxDrawText(job.type, sx+w-5, sy+image_h+(elementH*index)+elementH/2, _,_, tocolor(255,255,255,255), 1.6, "default", "right", "center")
    end
end
addEventHandler("onClientRender", getRootElement(), render_ui)

-- Controls
addEventHandler("onClientKey", getRootElement(),
function(key, isPress)
    if in_lobby then return end
    if isPress and show_jobmarker_panel and key=="e" then
        cancelEvent()
        triggerServerEvent("joinPlayerJob", localPlayer, localPlayer, c_job_id)
    end
end)

-- Job marker enter&leave

function ui_markerHit(player)
    if player == localPlayer then
        if getElementData(source, "job_marker") then
            local jobID = getElementData(source, "job_id")
            c_job_id = jobID
            show_jobmarker_panel = true
        end
    end
end
function ui_markerLeave(player)
    if player == localPlayer then
        if getElementData(source, "job_marker") then
            show_jobmarker_panel = false
            c_job_id = false
        end
    end
end

addEventHandler("onClientMarkerHit", getResourceRootElement(), ui_markerHit)
addEventHandler("onClientMarkerLeave", getResourceRootElement(), ui_markerLeave)