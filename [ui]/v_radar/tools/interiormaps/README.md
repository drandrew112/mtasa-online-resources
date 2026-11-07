# Interior map generator (minimap building plans)

Generates `v_radar/interiors/*.png` + `interiors/index.json` from live collision, measured on a
claude-mcp probe client (a connected game client). Not part of meta.xml, never downloaded by players.

## Steps

1. Find the walkable floor heights: `levels.lua` (via `mcp.lua(...)`, params `X0,Y0,X1,Y1,STEP,ZTOP,ZBOT`)
   prints the roofed floor z of every point in a grid.
2. Teleport the probe near the building (`python mcp.py teleport_probe '{"position":{...},"interior":N}'`),
   collision only exists close to the probe and in its interior.
3. Scan each floor level: `python doscan.py <name> x0 y0 x1 y1 floorZ` (0.2 m grid, 30 m tiles because MTA aborts
   long scripts). `CEIL=12` env for halls with high ceilings (default: ceiling within 4.5 m counts as indoors).
   Per cell: wall hits at floor+1.1 and floor+1.9 m (doors / lift doors skipped by model), floor below, ceiling above.
   `python debugimg.py <name>` writes a quick colour preview.
4. Add the map to `render.py` (`build(id, [scans...], crop, footprint=..., keep=...)` + zones) and run it:
   it writes the PNGs (10 px / m, north up) and index.json.
5. Add every new PNG to v_radar `meta.xml` (`<file src="interiors/<id>.png" type="client" />`).

Colours: walls darker grey, floors light grey (second level a bit darker), no furniture, outside the rooms
transparent (the minimap draws a dark background there). `cut=[...]` removes rooms nobody can enter.

## index.json

`x`, `y` = world position of the image's top-left (north-west) corner, `width`/`height` = metres covered,
`interior` = game interior (0 = free-roam building), `zones` = boxes of the player position where the map is
active (z separates floors / roofs), `zoom` = minimap zoom multiplier inside (1 = default ~80 m wide, 2 = twice as close; edit it by hand, render.py keeps the existing values), optional `dimension`.

## Business interiors

`render_biz.py` builds `biz_<template>` maps (office_standard / office_exclusive / weed_farm / casino) from scans `biz_os`, `biz_ox`, `biz_wf`, `biz_ca` and merges them into index.json (other maps untouched). Zones have no dimension, so every unit dimension (30000+) uses the same map. biz_int client/blips.lua adds the exit door + PC blips for map `biz_<template>`.
