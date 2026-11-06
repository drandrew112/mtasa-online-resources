-- mg_irrigation server exports (sessions: kit/server.lua). Result: onIrrigationGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startIrrigationGame(player, ped, options) return MGS.start(player, ped, options) end
function stopIrrigationGame(player) return MGS.stop(player) end
function isIrrigationGameActive(player) return MGS.active(player) end
