-- Custom models (client-side): file base name -> replaced model id
local MODELS = {
    { id = 1210, txd = "assets/medical_bag.txd", dff = "assets/medic_bag.dff" },   -- medical bag
    { id = 1581,  txd = "assets/lifepak15.txd",   dff = "assets/lifepak15.dff" },   -- Lifepak 15
}

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, m in ipairs(MODELS) do
        local txd = engineLoadTXD(m.txd)
        if txd then engineImportTXD(txd, m.id) end

        local dff = engineLoadDFF(m.dff)
        if dff then engineReplaceModel(dff, m.id) end

        if not txd or not dff then
            outputDebugString("[med_bag] failed to load assets for model " .. m.id, 1)
        end
    end
end)
