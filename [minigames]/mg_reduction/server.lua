-- mg_reduction server exports (sessions: kit/server.lua). Result: onReductionGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startReductionGame(player, ped, options) return MGS.start(player, ped, options) end
function stopReductionGame(player) return MGS.stop(player) end
function isReductionGameActive(player) return MGS.active(player) end
