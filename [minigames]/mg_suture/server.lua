-- mg_suture server exports (sessions: kit/server.lua). Result: onSutureGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startSutureGame(player, ped, options) return MGS.start(player, ped, options) end
function stopSutureGame(player) return MGS.stop(player) end
function isSutureGameActive(player) return MGS.active(player) end
