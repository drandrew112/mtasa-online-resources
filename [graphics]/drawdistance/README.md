# drawdistance

Increases how far the world is drawn.

- **World / peds / vehicles** – raises `setFarClipDistance`, `setFogDistance`,
  `setPedsLODDistance` and `setVehiclesLODDistance`.
- **Mapped objects** – objects loaded from other resources' `.map` files have no
  LOD models, so GTA drops them at a short distance. For each one the resource
  builds a low-LOD twin (`createObject(..., true)` + `setLowLODElement`) and
  pushes the model's LOD switch distance out with `engineSetModelLODDistance`.

Start this resource **before** the maps you want it to affect. Resources that
were already running when it starts are picked up too.

## Exports (client)

Used by `ui_pause` → Graphics settings. Each `set*` clamps to its range and
returns the value actually applied.

| Export | Range | Default | Notes |
| --- | --- | --- | --- |
| `setFarClip(d)` / `getFarClip()` | 400–3400 | 1400 | Fog is kept 200 units behind the far clip. |
| `setModelLOD(d)` / `getModelLOD()` | 200–2800 | 400 | LOD switch distance for the cloned mapped objects. |
| `setPedLOD(d)` / `getPedLOD()` | 200–500 | 500 | The engine hard-clamps peds to 500. |
| `setVehicleLOD(d)` / `getVehicleLOD()` | 200–500 | 500 | The engine hard-clamps vehicles to 500. |
| `resetDrawDistance()` | – | – | All four back to their defaults. |

```lua
exports.drawdistance:setFarClip(2000)
```

Version 2.0.0
