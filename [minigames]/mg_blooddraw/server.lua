-- mg_blooddraw server exports (sessions: kit/server.lua). Result: onBloodDrawGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startBloodDrawGame(player, ped, options) return MGS.start(player, ped, options) end
function stopBloodDrawGame(player) return MGS.stop(player) end
function isBloodDrawGameActive(player) return MGS.active(player) end
