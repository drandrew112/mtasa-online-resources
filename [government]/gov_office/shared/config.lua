-- gov_office / shared/config.lua

OFFICE = {
    -- the interior (world_interiors); the inside dimension is fixed
    id        = "gov_office_ls",
    interior  = 3,
    dimension = 1,
    -- player (centre) height: world_interiors puts the marker 1 m lower, on the ground
    enter = { x = 1481.13, y = -1767.50, z = 18.80, rot = 0 },          -- Los Santos city hall, outside
    exit  = { x = 388.57, y = 174.39, z = 1008.38, rot = 0 },           -- inside

    -- government computers
    pcModel   = 2190,     -- PC_1 (monitor + keyboard)
    pcMax     = 60,
    pcRange   = 2.0,      -- interact menu range
    pcMenuOffset = { 0, 0, -0.5 },   -- from ui_interactobject's anchor (top of the collision box + 0.2 m)
    editRange = 80,       -- a computer may be placed this far from the inside marker at most

    -- placement editor (/govpcs)
    command    = "govpcs",
    rotStep    = 15,      -- degrees per wheel tick
    rotFine    = 1,       -- with Shift held
    heightStep = 0.02,    -- metres per wheel tick with Ctrl held
    rayLength  = 25,
}
