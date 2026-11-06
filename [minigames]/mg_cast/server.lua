-- mg_cast server exports (sessions: kit/server.lua). Result: onCastGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startCastGame(player, ped, options) return MGS.start(player, ped, options) end
function stopCastGame(player) return MGS.stop(player) end
function isCastGameActive(player) return MGS.active(player) end
