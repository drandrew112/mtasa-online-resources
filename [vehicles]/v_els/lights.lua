-- vehicleLights3D tárolja, mely fények vannak létrehozva
local vehicleLights3D = {}

-- frissíti a jármű fényeket egyszerűen
function initVehicleLights(veh)
    if not isElement(veh) then return end
    local model = getElementModel(veh)
    if not sirenVehicles[model] then return end

    local cfg = vehicleLights[model]
    -- ha nincs egyedi fénykonfiguráció, a gyári szirénapontokból indulunk ki (2 pont)
    local count = (cfg and #cfg) or 2

    vehicleLights3D[veh] = {}

    removeVehicleSirens(veh)
    -- silent = true → némítja a gyári GTA szirénahangot, csak a fények maradnak.
    -- Csak a script által lejátszott sziréna szól.
    addVehicleSirens(veh, count, 6, false, true, true, true)

    if cfg then
        for i, lightCfg in ipairs(cfg) do
            setVehicleSirens(
                veh,
                i,                   -- siren point index
                lightCfg.offset[1],  -- posX
                lightCfg.offset[2],  -- posY
                lightCfg.offset[3],  -- posZ
                lightCfg.color[1],   -- R
                lightCfg.color[2],   -- G
                lightCfg.color[3],   -- B
                255,                 -- alpha
                255                    -- minAlpha
            )
            vehicleLights3D[veh][i] = true
        end
    end
end

-- jármű létrehozásakor vagy betöltéskor init
addEventHandler("onResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        initVehicleLights(veh)
    end
end)

addEventHandler("onVehicleEnter", root, function()
    initVehicleLights(source)
end)
