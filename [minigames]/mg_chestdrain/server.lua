-- mg_chestdrain server exports (sessions: kit/server.lua). Result: onChestDrainGameFinish
--   (success, percent, reason, sessionId, details), source = player.

-- ped: optional patient (the player is placed next to it and animated); options: shared.lua
function startChestDrainGame(player, ped, options) return MGS.start(player, ped, options) end
function stopChestDrainGame(player) return MGS.stop(player) end
function isChestDrainGameActive(player) return MGS.active(player) end
