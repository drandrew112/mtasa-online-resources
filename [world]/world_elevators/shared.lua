
function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

elevators = {
    {
        name = "LS Police Station",
        floors = {
            {
                name = "Garage",
                x = 1582.53467,
                y = -1677.79980,
                z = 5.89437,
            },
            {
                name = "Gnd",
                x = 1581.19812,
                y = -1675.14746,
                z = 16.20031,
            },
            {
                name = "Roof",
                x = 1578.79248,
                y = -1675.79443,
                z = 19.88281,
            }
        }
    }
}
