-- world_interiors / shared/config.lua
INT = {
    adminLevel = 4,          -- minimum admin level for /interiors (SuperAdmin)
    command    = "interiors",
    stockCommand = "intwatch",                      -- stock GTA interior browser (view only)
    stockFile    = "data/stock_interiors.json",     -- generated from source/interiors/interiors.map
    fadeMs     = 400,        -- fade out time before the teleport
    cooldownMs = 1000,       -- extra wait after a transfer before the next one
    key        = "e",        -- press inside a marker to go through

    -- 3D label above the markers (same look as the work_core labels)
    labelDistance     = 20,
    labelFullDistance = 6,
    labelMinScale     = 0.55,
    labelHeight       = 0.4,     -- above the given point (the marker base sits 1 unit lower)
    markerSize = 1.4,
    markerType = "cylinder",
    enterColor = { 80, 170, 255, 140 },
    exitColor  = { 255, 170, 60, 140 },
}
