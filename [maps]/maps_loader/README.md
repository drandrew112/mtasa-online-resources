# maps_loader

Every custom map of the server, loaded by one resource (replaces the old `map_*` resources,
`DOUBLE_ZEBRA*`, `lights_desert_radar`).

- `maps/<name>/<name>.map` - map editor format (objects, removeWorldObject, markers)
- `maps/<name>/settings.json` - optional: `indoor` boxes, `lod: "none"`, `disabled` (see `config.lua`)
- `maps/index.json` - the maps loaded on start; `/maploader update` (admin 5+) rewrites it from the
  folders and prints counts, duplicates and problems; restart `maps_loader` to apply
- the models of the maps are in `v_modloader/objects` (always loaded): volan 14802, int_lspd
  3976 / 4230 / 14846, zebra 7557, sf_garage 11326 / 11387 / 11389

How the objects are made:

- the server reads the maps once, drops objects that are already in an earlier map (same model,
  position, rotation) and sends the list to the clients; there are no server-side map elements
- clients create a map's objects only while the camera is within drawdistance far clip + 150 m of it
- objects inside an `indoor` box exist only while the camera is within `margin` m of the box
  (`keep` models always exist - e.g. the LSPD interior shell with its floors)
- `removeWorldObject` is applied on the client, reference counted
- low LOD clones: `exports.drawdistance:registerLowLOD(object)` for exterior objects with a bounding
  radius of at least `LOD_MIN_RADIUS` (10 m); small props and indoor objects get none

Other resources:

- `loadMapInDimension(name, dim [, { interiorOnly = true }])` / `unloadMapFromDimension(name, dim)`
  (server, reference counted per calling resource, released when that resource stops) - used by the
  work_atc training (int_sacontrol) and the work_ems tutorial (ls_allsaints)
- `extras/sacontrol`: the SA Control wall signs (were in map_int_sacontrol)
- `extras/technoparty`: radio stream + two dancing peds of ls_technoparty, only within 250 m (were in map_ls_technoparty)
- the old sf_garage radio and the /open garage door command are gone (v_customs will use the map)

Event maps (e.g. `ls_xmas_tree`):

- `settings.json` `"event": true` - the map is listed in `index.json` but its objects and world removals
  exist on the clients only while it is switched on
- server exports `setEventMapEnabled(name, bool)`, `isEventMapEnabled(name)`, `getEventMaps()`;
  console / admin 5+ command `/maploader event <map> on|off`
- the state is not saved: after a `maps_loader` restart every event map is off; the server event
  `onMapsLoaderStart` (root) tells event_core to switch the active ones back on
