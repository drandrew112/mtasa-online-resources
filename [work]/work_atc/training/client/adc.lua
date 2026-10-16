-- ADC - Aerodrome Controller training (tower, SASF_TWR): a departure from the stand to the CTR
-- boundary and an arrival from the final to the stand. Texts: work_atc.trn.adc.*

TRN.modules.adc = {}

-- the new aircraft in the middle of the scope
function TRN.modules.adc.onSpawn(H, role)
    if role == "dep" then H.focus("dep", 2) else H.focus("arr", 0.8) end
end

function TRN.modules.adc.build(H)
    local S, cmd, phase = H.S, H.cmd, H.phase

    -- out of the tower's hands: gone, or airborne and controlled by nobody / somebody else
    local function depLost()
        local a = H.ac("dep")
        return a == nil or (not a.gnd and a.ctl ~= TRN.T.info.position)
    end

    -- what the departure is asking for while it taxies
    local function depRequestNote()
        local a = H.ac("dep")
        if not a then return nil end
        if a.phase == "hold" and a.req then
            return H.note("note_holding", { rwy = a.holdRwy or "?", req = a.req })
        end
        return H.note("note_phase", { phase = a.phase or "?" })
    end

    local function goAroundNote()
        local a = H.ac("arr")
        if a and a.proc and tostring(a.proc):sub(1, 3) == "GA " then
            return H.note("note_go_around")
        end
    end

    return {
        console = {
            { text = S("console_walk"), check = function() return H.loginOpen() or H.scopeVisible() end },
            { text = S("console_login"),
              rect = function()
                  local lg = H.scope().login
                  return lg and lg.rows and lg.rows[TRN.T.info.position] or nil
              end,
              note = function()
                  if not H.loginOpen() then return H.note("note_open_console") end
              end },
            -- the server moves on once the tutorial login is done
        },
        -- the scope, the labels and the menu are known from the SCOPE module
        label = {
            { text = S("label_wait"), needScope = true, fast = true, check = function() return H.ac("dep") ~= nil end },
            { text = S("label_menu"), needScope = true, check = function() return H.menuOpenFor("dep") end,
              rect = H.labelRect("dep"), enter = function() H.focus("dep", 2) end },
            { text = S("label_menu_info"), next = true, needScope = true, rect = H.menuRect("dep"), leave = H.serverNext },
        },
        delivery = {
            { text = S("delivery_ifr"), needScope = true, check = function() return cmd("dep", "ifr") end,
              rect = H.menuItem("dep", "IFR clearance") },
            { text = S("delivery_push"), needScope = true, check = function() return cmd("dep", "push") end,
              rect = H.menuItem("dep", "Pushback approved") },
            { text = S("delivery_pushing"), needScope = true, fast = true, rect = H.labelRect("dep"),
              check = function()
                  local a = H.ac("dep")
                  return a ~= nil and a.req == "TAXI" and a.ready == true
              end, leave = H.serverNext },
        },
        ground = {
            { text = S("ground_taxi"), needScope = true, check = function() return cmd("dep", "taxi") end,
              rect = H.menuItem("dep", "Taxi") },
            { text = S("ground_rules"), needScope = true, fast = true, rect = H.labelRect("dep"), note = depRequestNote,
              check = function()
                  local p = phase("dep")
                  return p == "hold" or p == "lined" or p == "takeoff" or p == "air" or cmd("dep", "takeoff")
              end },
            { text = S("ground_takeoff"), needScope = true, rect = H.requestItem("dep"), note = depRequestNote,
              check = function() return cmd("dep", "takeoff") end, leave = H.serverNext },
        },
        air = {
            { text = S("air_wait"), needScope = true, fast = true, rect = H.labelRect("dep"),
              check = function() return phase("dep") == "air" or depLost() end },
            { text = S("air_leave"), needScope = true, fast = true, rect = H.labelRect("dep"), check = depLost,
              leave = H.serverNext },
        },
        arrival = {
            { text = S("arr_wait"), needScope = true, check = function() return H.ac("arr") ~= nil end },
            { text = S("arr_land"), needScope = true, fast = true, rect = H.menuItem("arr", "Cleared to land"),
              note = goAroundNote, enter = function() H.focus("arr", 0.8) end,
              check = function()
                  local a = H.ac("arr")
                  return cmd("arr", "land") or (a ~= nil and (a.landClr or H.LANDED[a.phase] == true))
              end },
            { text = S("arr_vacate"), needScope = true, fast = true, rect = H.labelRect("arr"), note = goAroundNote,
              check = function() return H.LANDED[phase("arr") or ""] == true end },
            { text = S("arr_taxi"), needScope = true, rect = H.menuItem("arr", "Taxi to stand"),
              enter = function() H.focus("arr", 1.6) end,
              check = function() return cmd("arr", "taxi") or phase("arr") == "taxi_in" or phase("arr") == "parked" end },
            { text = S("arr_parked"), needScope = true, fast = true, rect = H.labelRect("arr"),
              check = function() return phase("arr") == "parked" end, leave = H.serverNext },
        },
        alerts = {
            { text = S("alerts_emrg"), next = true, needScope = true, rect = H.labelRect("arr"),
              enter = function() H.focus("arr", 1.6) end,
              leave = function() triggerServerEvent("atc:trn:restoreSquawk", resourceRoot) end },
            { text = S("alerts_fines", H.payParams), next = true, needScope = true },
            { text = S("alerts_pay", H.payParams), next = true, needScope = true },
            { text = S("alerts_logout"), needScope = true, rect = H.scopeRect("logout") },
            -- the server moves on at the logout (the receipt comes with it)
        },
    }
end
