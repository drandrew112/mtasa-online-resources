local MODEL_ID = 14802
local ASSETS = "assets/volan"

local function loadModel()
    local txd = engineLoadTXD(ASSETS .. ".txd")
    if txd then
        engineImportTXD(txd, MODEL_ID)
    else
        outputDebugString("[map_ls_busstation] failed to load " .. ASSETS .. ".txd", 1)
    end

    local col = engineLoadCOL(ASSETS .. ".col")
    if col then
        engineReplaceCOL(col, MODEL_ID)
    else
        outputDebugString("[map_ls_busstation] failed to load " .. ASSETS .. ".col", 1)
    end

    local dff = engineLoadDFF(ASSETS .. ".dff")
    if dff then
        engineReplaceModel(dff, MODEL_ID)
    else
        outputDebugString("[map_ls_busstation] failed to load " .. ASSETS .. ".dff", 1)
    end

    engineSetModelLODDistance(MODEL_ID, 300)
end

addEventHandler("onClientResourceStart", resourceRoot, loadModel)

addEventHandler("onClientResourceStop", resourceRoot, function()
    engineRestoreModel(MODEL_ID)
    engineRestoreCOL(MODEL_ID)
end)
