local CASE_MODEL = 2969

addEventHandler("onClientResourceStart", resourceRoot, function()
    local txd = engineLoadTXD("assets/case.txd")
    if txd then
        engineImportTXD(txd, CASE_MODEL)
    else
        outputDebugString("bt_items: assets/case.txd failed to load", 1)
    end

    local dff = engineLoadDFF("assets/case.dff")
    if dff then
        engineReplaceModel(dff, CASE_MODEL)
    else
        outputDebugString("bt_items: assets/case.dff failed to load", 1)
    end
end)
