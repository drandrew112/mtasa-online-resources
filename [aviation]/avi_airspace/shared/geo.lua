-- Polygon helpers ({ {x, y}, ... } in world metres).

function pointInPolygon(x, y, poly)
    local inside = false
    local n = #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i][1], poly[i][2]
        local xj, yj = poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

function polygonCentre(poly)
    local sx, sy = 0, 0
    for _, p in ipairs(poly) do sx, sy = sx + p[1], sy + p[2] end
    return sx / #poly, sy / #poly
end
