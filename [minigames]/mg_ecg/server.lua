-- mg_ecg server exports (sessions: kit/server.lua). Result: onEcgGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startEcgGame(player, ped, options) return MGS.start(player, ped, options) end
function stopEcgGame(player) return MGS.stop(player) end
function isEcgGameActive(player) return MGS.active(player) end
