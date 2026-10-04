# rw_auto

Automatic (NPC) trains of Sunline Rail (see `../README.md` "Automatic trains").

- `server/auto.lua` - scheduler (58 s before departure: taken by a player? 55 s: create the
  train), driving (each stop = the network train's destination, line speed 105–120 km/h, the
  ATP brakes for stops / signals / trains ahead; early trains wait at the platform), doors,
  chaining (`chain` lines), removal at the terminus (passengers are put on the platform).
  Dead-end stop tracks (Cranberry 3 / 4) stop `AUTO.END_GAP` before the buffer.

Export: `getAutoTrains()`.
