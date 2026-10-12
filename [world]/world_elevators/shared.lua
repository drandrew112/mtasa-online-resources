if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

elevators = {
    {
        name = L.text("world_elevators.shared.ls_police_station"),
        floors = {
            {
                name = L.text("world_elevators.shared.roof"),
                x = 1578.79248,
                y = -1675.79443,
                z = 19.88281,
            },
            {
                name = L.text("world_elevators.shared.gnd"),
                x = 1581.19812,
                y = -1675.14746,
                z = 16.20031,
            },
            {
                name = L.text("world_elevators.shared.garage"),
                x = 1582.53467,
                y = -1677.79980,
                z = 5.89437,
            },
        }
    }
}
