-- world_interiors / shared/config.lua
INT = {
    adminLevel = 4,          -- minimum admin level for /interiors (SuperAdmin)
    command    = "interiors",
    stockCommand = "intwatch",                      -- stock GTA interior browser (view only)
    stockFile    = "data/stock_interiors.json",     -- generated from source/interiors/interiors.map
    fadeMs     = 400,        -- fade out time before the teleport
    markerSize = 1.4,
    markerType = "cylinder",
    enterColor = { 80, 170, 255, 140 },
    exitColor  = { 255, 170, 60, 140 },
}
