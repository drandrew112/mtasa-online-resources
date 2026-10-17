-- v_fps: /fps toggles an FPS counter on the middle of the left screen edge.
-- The render handler is only attached while the counter is visible.

local screenW, screenH = guiGetScreenSize()

local visible = false
local fps = 0
local frames = 0
local lastTick = 0
local avgFps = 0
local samples = {}      -- last AVG_SAMPLES per-second measurements (ring buffer)
local sampleIndex = 0
local AVG_SAMPLES = 10

local function renderFPS()
    frames = frames + 1
    local now = getTickCount()
    local elapsed = now - lastTick
    if elapsed >= 1000 then
        fps = math.floor(frames * 1000 / elapsed + 0.5)
        frames = 0
        lastTick = now

        sampleIndex = sampleIndex % AVG_SAMPLES + 1
        samples[sampleIndex] = fps
        local sum = 0
        for i = 1, #samples do
            sum = sum + samples[i]
        end
        avgFps = math.floor(sum / #samples + 0.5)
    end

    local text = "FPS: " .. fps .. " (avg " .. avgFps .. ")"
    local x, y = 12, screenH / 2
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 200), 1.2, "default-bold", "left", "center")
    dxDrawText(text, x, y, x, y, tocolor(255, 255, 255, 255), 1.2, "default-bold", "left", "center")
end

local function toggleFPS()
    visible = not visible
    if visible then
        fps, frames, lastTick = 0, 0, getTickCount()
        avgFps, samples, sampleIndex = 0, {}, 0
        addEventHandler("onClientRender", root, renderFPS)
    else
        removeEventHandler("onClientRender", root, renderFPS)
    end
end
addCommandHandler("fps", toggleFPS)
