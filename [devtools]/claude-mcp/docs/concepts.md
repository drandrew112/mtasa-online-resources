# Concepts

## Conventions

| | |
|---|---|
| coordinates | metres; x = west→east, y = south→north, z = up; map −3000…3000 |
| heading | MTA `rotation.z`, **counter-clockwise**: 0 = north, 90 = west, 180 = south, 270 = east. Every entity also reports `compass` and a `forward` vector |
| vehicles | `rotation.x` = pitch (+ nose up), `rotation.y` = roll (+ right side down); computed from the terrain by placement |
| peds | only the heading matters (set with MTA's ped rotation fix) |
| objects | the heading turns the model's +Y axis; which side is the "front" depends on the model — check with the overlay arrow |
| model size | `size.x` width, `size.y` length (+y = front), `size.z` height |
| lateral offsets | + = right of the reference heading |
| lanes | right-hand traffic; lane 1 = curb (rightmost) lane of the travel direction |
| locations | every location parameter accepts `"player"`, an entity id, `{x,y,z}`, `[x,y,z]` or `{node: id}` |

## Capability map

`get_capability_map` (also the MCP resource `mta://capability-map`) returns
modules, every tool with purpose / read-vs-mutating / parameters / returns /
side effects / probe requirement / limitations / related tools, the standard
workflows and the tool-to-tool relationships derived from them, conventions,
entity types, poses, inspection and validation methods, data sources, visual
feedback requirements and the live connection status. Filter with `module` or
`tool`; `schemas: true` adds full JSON input schemas. The map is generated from
the same definitions that register the MCP tools, so it cannot drift.

## World map

- `get_world_map`: bounds, cities, zones with approximate centres (server
  `getZoneName` grid), road-network statistics and road density per 750 m area,
  the probe position and workspaces. Cheap — no geometry.
- `inspect_world_map_area`: coarse grid of a region (zone / city per cell, road
  nodes, intersections, average road height).
- `get_current_location_context`: "what is around me" — position, heading, zone,
  ground, nearest road node and road line (with your alignment to it),
  intersections, nearby elements with distance and compass direction, world-model
  summary and area type.
- `get_area_summary` / `inspect_area`: summary vs. structured inspection.

### Area inspection

`inspect_area` combines MTA elements, a raycast-grid scan and the road graph.
The scan casts a vertical ray from high above (top surface: roofs, canopies,
bridges) and, where that is high, a second ray from just above the reference
height (ground under overhangs). Output:

- `worldModels`: id, dff name, kind (name heuristic or surface evidence),
  position, rotation, LOD id, hit counts, hit extent; `detail: "high"` also
  measures real model bounds and world-space bounds for the main models.
- `surfaces` (percent per class, plus `covered`), `materials`, `terrain`
  (min/max/mean height, mean slope), `areaType` (heuristic), `directions`
  (open / blocked headings at ~1.2 m with the blocking model), `collisionLoaded`.

Surface classes: road, sidewalk, concrete, grass, dirt, sand, rock, water,
structure, vehicle, ped, default, other. Many Los Santos road and building
models use the `DEFAULT` collision material; those hits are re-classified by
the model name (`laeroad33` → road).

## Road network

`assets/vehiclenodes.lua` (the v_radar GPS data) holds 30 586 nodes in 64
areas (`id = area * 65536 + index`) with neighbour links. It has **no lane,
width or one-way data**; links listed in one direction only are reported as
`outgoing only` / `incoming only`.

The MCP server indexes it as a graph: node map, undirected + directed
adjacency, segments, a 64 m spatial grid for nearest node / segment queries,
road stretches (degree-2 chains between intersections) and A* paths with
turn-by-turn steps.

Live geometry is authoritative: `get_road_cross_section` (and `live: true` on
road tools) raycasts across the road at a node to measure the road surface span
(edges, width, centre offset), sidewalks with curb height, the road models and
a lane estimate (two-way when the node is near the centre; lanes ≈ width / 4 m
per direction). Road placement uses this measurement.

Typical chain: `inspect_area` → `get_nearest_road_node` → `get_road_segment` →
`spawn_entity {placement: {mode: "road", node, towardNode, lane}}` →
`inspect_entity` → `validate_workspace`.

## Model discovery

| | source |
|---|---|
| vehicles | `veh_manager:getModelName` (project names win, e.g. 416 = "Mercedes Sprinter (HU)"), GTA name, `getVehicleType` category, seats, original handling |
| peds | `getValidPedModels`; sex from the project's female list (med_scenemanager), every record has `sex` + `sexSource`; dff names from the client |
| objects | dff names of every model id from the client (`engineGetModelNameFromID`), searchable |
| geometry | `get_model_info` measures a hidden local copy: bounding box, size, radius, base offset, vehicle wheels / dummies / components (cached) |

Nothing is invented: unknown fields are omitted. Object `kind` values are a
name heuristic and say so (`kindSource`).

## Entity lifecycle

`spawn_entity` → `inspect_entity` → `modify_entity` / `place_entity` /
`orient_entity` / `set_entity_transform` → `validate_workspace` →
`delete_entity` / `clear_workspace`.

- Ids: `<prefix>_<type>_<nnn>` (prefix `tmp` in the default workspace, the
  workspace name otherwise) or a custom `id`.
- Mutations return the state read back from MTA plus `live` probe data
  (bounding box, ground gap, wheel contact).
- Workspace entities are frozen by default and vehicles damage-proof.
- `adopt_element` brings an existing element under a semantic id.

## Semantic placement

| mode | meaning |
|---|---|
| `ground` | snap to the terrain at a point (vehicles get pitch/roll from 4 ground samples; steps > 0.3 m are ignored and reported) |
| `road` | node / segment / nearest road to a point; `lane`, `lanePosition` (lane, curb, shoulder, center, sidewalk, offset), `facing`, `alongOffset`, `lateralOffset` |
| `node` | offset `along` / `lateral` in a road node's travel frame |
| `near` | next to a target on a side with a clearance `gap` computed from both bounding boxes; `facing` same / opposite / perpendicular / towards / away |
| `relative` | local `{right, forward, up}` offset from a target |
| `raw` | exact transform |

`headingOffset` skews the final heading (crash angles). `compute_placement`
dry-runs any placement. `orient_entity` rotates semantically (face towards,
parallel, perpendicular, align to road...).

## Workspaces

Named groups of temporary entities with a dimension / interior, optional centre
and radius, id prefix and frozen default. `inspect_workspace` gives bounds and
live data; `clear_workspace` removes everything (the normal world is never
touched). `export_workspace` writes generic JSON (re-importable with
`import_workspace`), MTA `.map` XML or Lua code — always values read back from
MTA at export time.

## Validation

`validate_workspace` returns `{valid, errors[], warnings[], info[], entities[]}`.
Each diagnostic has `entity`, `type`, `message` and often `value` /
`suggestion`.

| check | detects |
|---|---|
| validity | missing element, blown vehicle, dead ped |
| dimension | entity vs. workspace dimension / interior |
| bounds | outside the map, below / far above it |
| health | vehicle health < 250 without damage-proof |
| ground | wheel gaps / sunk wheels, ped / object base gap (lying peds tolerated), no ground, vehicle on sidewalk |
| world_collision | box edges / diagonals intersect world geometry (model named) or foreign objects |
| overlap | OBB overlaps between entities (lying ped under a vehicle = error) and with foreign elements (attached ones ignored) |
| water | submerged entities |
| clearance | free directions around standing / lying peds |
| scene_bounds | outside the workspace radius |
| road_alignment | vehicle heading vs. nearest road and distance from the road line (MCP server) |

## Visual feedback

- `capture_screenshot`: what the probe client shows now.
- `capture_view`: computed cameras (orbit / front / back / left / right / top /
  free) around an entity, point, road node or a whole workspace; candidate views
  are ray-tested so the camera does not end up inside a building.
- `capture_views`: several computed views in one call, taken in parallel (one
  bridge job per view, spread over the probe clients).
- `set_debug_overlay`: ids, bounding boxes, heading arrows, lines, points, road
  nodes and paths drawn in the game (and in screenshots).

Screenshots need "Allow screen upload" and a non-minimized window. They are
returned as MCP images and saved under `screenshots/`.
During the shot the custom UI (v_radar minimap, ui_core overlays) is hidden
through the shared `hideHUD` element data and the chat is hidden; both are
restored afterwards (`hideHud: false` keeps them). The GTA HUD is never touched.
Shots are taken in daylight by default: the probe client is held at 12:00 with
clear weather for the shot only and its real time / weather is restored right
after (`daylight: false` keeps the current time / weather).

## Several probe clients

Every ready game client in the primary probe's dimension / interior is a
worker. Each bridge job is bound to one probe the first time it needs one and
keeps it until it ends; the least busy probe wins (fewest running jobs, camera
not in use by another job, closest to the query point). Parallel tool calls
therefore run on different clients. The primary probe (`select_probe`,
`/mcp probe` or the `probePlayer` setting) is still the one meant by
`player` / `probe` / `camera`, by the player and camera tools and by
current-view screenshots. A job that moves a probe camera owns it until it
ends; others that need it wait (`PROBE_BUSY` after 45 s). Screenshot work skips
minimized windows. `get_status` lists the workers under `probes`.
