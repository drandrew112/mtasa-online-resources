# Data cache

Some world data is expensive to produce (a surface map of a city takes a few
minutes of probe scanning) but rarely changes. The `cache` module keeps such data
on disk so later tasks and sessions reuse it instead of regenerating it.

- Location: `cache/` next to `meta.xml` (`MCP_CACHE_DIR` overrides it), ignored by git.
- One file per entry: `cache/<kind>/<key>.json` = `{ meta, data }`, plus
  `cache/index.json` with the metas only (rebuilt from the files if missing).
- It survives MCP and MTA restarts. Delete an entry after map edits that make it stale.
- `get_status` reports the cache stats (entries, kinds, bytes).

## Tools

| tool | |
|---|---|
| `cache_list` | entries (key, kind, description, params, complete, items, bytes, created / updated); filter by kind / prefix |
| `cache_get` | one entry; `metaOnly`; surface maps: `region` (+ `surfaces`) returns cells `[x, y, groundZ, surface]`; arrays: `offset` / `limit` / `region` |
| `cache_put` | store any JSON under a key and kind (e.g. hand-verified spots, kind `locations`); `overwrite` to replace |
| `cache_delete` | remove an entry |
| `build_surface_map` | surface class + ground z grid of a city (`los_santos`, `san_fierro`, `las_venturas`) or a rectangle, default 20 m, cached as `surface_map.<area>.<step>m` |
| `find_surface_patches` | connected patches of surface classes in a cached map (grass = parks / lawns, sand = beaches, sidewalk = plazas) near the road network |

Always check `cache_list` before generating data.

## Surface maps

`build_surface_map` scans blocks of `blockCells` x `blockCells` cells (default
10 x 10 = 200 m at 20 m). The first point of every block is its centre, so the bridge
focuses the probe camera there and collision streams in. Rays use `topmost`, so
roofs count as `structure`. Ocean cells are `water`, and cells that got no hit are `?`.
A block where nothing was hit is marked `unloaded` and is retried by the next call.

Each call scans at most `maxBlocks` blocks (default 80) and saves progress. Repeat the
call while `complete` is false. An existing complete map returns immediately, and
`refresh: true` rescans it.

Data layout: `{ bounds, step, nx, ny, classes[], s[] (class index, -1 = not scanned),
z[], blocks }`. Cell `(i, j)` is at `x = minX + (i + 0.5) * step`,
`y = minY + (j + 0.5) * step`, with index `j * nx + i`.

## Patch search

`find_surface_patches { city, surfaces: ["grass"], minCells: 9, maxRoadDistance: 40,
maxHeightRange: 6, minSpacing, avoid: [{x, y, radius}] }` flood-fills the cached map
(4-neighbour) and returns patches, largest first. Each patch has a spot deep inside it,
where all 8 neighbours belong to the patch, chosen near the road and the centroid.
It also has the size in cells and m², the height range and the nearest road node.
The search is instant and needs no probe.

The map is coarse. A grass patch can be a park, a large lawn or a golf course, so verify
the spot (`get_area_summary`, `find_safe_position`, `capture_view`) before using it.
Store verified spots with `cache_put` for reuse.
