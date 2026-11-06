-- mg_fast server exports (sessions: kit/server.lua). Result: onFastGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startFastGame(player, ped, options) return MGS.start(player, ped, options) end
function stopFastGame(player) return MGS.stop(player) end
function isFastGameActive(player) return MGS.active(player) end
