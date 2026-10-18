-- Custom stretcher model: assets/stretcher.txd + stretcher.dff replace STRETCHER.OBJECT_MODEL.
-- Switch it off with STRETCHER.enable_stretcher_model = false (shared/config.lua): the stock trolley is used.

local txd, dff

local function unload()
    if dff and isElement(dff) then destroyElement(dff) end
    if txd and isElement(txd) then destroyElement(txd) end
    dff, txd = nil, nil
end

local function load()
    if not STRETCHER.enable_stretcher_model then return end

    txd = engineLoadTXD("assets/stretcher.txd")
    dff = engineLoadDFF("assets/stretcher.dff")
    if not (txd and dff) then
        outputDebugString("[med_stretcher] stretcher assets failed to load, using the default model", 2)
        unload()
        return
    end

    engineImportTXD(txd, STRETCHER.OBJECT_MODEL)
    if not engineReplaceModel(dff, STRETCHER.OBJECT_MODEL) then
        outputDebugString("[med_stretcher] engineReplaceModel failed, using the default model", 2)
        engineRestoreModel(STRETCHER.OBJECT_MODEL)
        unload()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, load)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if dff then engineRestoreModel(STRETCHER.OBJECT_MODEL) end
    unload()
end)
