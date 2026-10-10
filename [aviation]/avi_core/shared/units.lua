-- Aviation units. The GTA world unit is the metre; ATC shows feet, knots and feet / minute.

local FT_PER_M = 3.28084
local KT_PER_MS = 1.943844

function metresToFeet(m) return (tonumber(m) or 0) * FT_PER_M end
function feetToMetres(ft) return (tonumber(ft) or 0) / FT_PER_M end
function msToKnots(ms) return (tonumber(ms) or 0) * KT_PER_MS end
function knotsToMs(kt) return (tonumber(kt) or 0) / KT_PER_MS end
