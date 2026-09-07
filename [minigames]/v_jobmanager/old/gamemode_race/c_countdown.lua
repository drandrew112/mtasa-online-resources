local sw,sh = guiGetScreenSize()

local show_countdown = false
local countdown = false

addEventHandler("onClientRender", getRootElement(), function()
    if show_countdown then
        local text = "?"
        if countdown == 0 then
            text = "GO!"
        else
            text = tostring(countdown)
        end
        outputDebugString(text)
        dxDrawText(text, sw/2, sh*0.3, _,_, tocolor(255,255,255,255), 4, "pricedown", "center", "center")
    end
end)


addEvent("race_countdown", true)
addEventHandler("race_countdown", getRootElement(), function(active_job_id, race_id, _countdown)
    show_countdown = true
    countdown = _countdown
    if countdown == 0 then
        setTimer(function() show_countdown = false end, 1000, 1)
    end
    outputDebugString("client: "..tostring(show_countdown).." countdown: "..countdown)
end)
