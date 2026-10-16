-- APC - Approach Controller training (SASF_APP): a departure climbing through the TMA, an arrival
-- on a STAR and an arrival on radar vectors. Tower and radar are closed: outside the TMA the pilots fly
-- on their own. Texts: work_atc.trn.apc.*

TRN.modules.apc = {}

function TRN.modules.apc.onSpawn(H, role)
    H.focus(role)
end

function TRN.modules.apc.build(H)
    local S, cmd = H.S, H.cmd

    -- the aircraft is the trainee's now, or it already left the TMA
    local function arrived(role)
        return function() return H.mine(role) or H.handedOff(role) end
    end
    local function did(role, ...)
        local actions = { ... }
        return function() return cmd(role, unpack(actions)) or H.handedOff(role) end
    end
    local function gone(role)
        return function() return H.handedOff(role) end
    end

    local function goAroundNote(role)
        return function()
            local a = H.ac(role)
            if a and a.proc and tostring(a.proc):sub(1, 3) == "GA " then return H.note("note_go_around") end
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
        },
        -- the airspace of approach (the scope itself is known from the SCOPE module)
        airspace = {
            { text = S("airspace_intro"), next = true, needScope = true },
            { text = S("airspace_runways"), next = true, needScope = true, rect = H.scopeRect("runways") },
            { text = S("airspace_fixes"), next = true, needScope = true, rect = H.scopeRect("tools"), leave = H.serverNext },
        },
        departure = {
            { text = S("dep_wait"), needScope = true, fast = true, rect = H.labelRect("dep"), check = arrived("dep") },
            { text = S("dep_climb"), needScope = true, rect = H.menuItem("dep", "Cleared altitude"),
              enter = function() H.focus("dep") end, check = did("dep", "cfl") },
            { text = S("dep_direct"), needScope = true, rect = H.menuItem("dep", "Direct to"),
              check = did("dep", "dct", "hdg") },
            { text = S("dep_leave"), needScope = true, fast = true, rect = H.labelRect("dep"), check = gone("dep"),
              leave = H.serverNext },
        },
        arrival = {
            { text = S("arr_wait"), needScope = true, fast = true, rect = H.labelRect("arr"), check = arrived("arr") },
            { text = S("arr_descend"), needScope = true, rect = H.menuItem("arr", "Cleared altitude"),
              enter = function() H.focus("arr") end, check = did("arr", "cfl") },
            { text = S("arr_approach"), needScope = true, rect = H.menuItem("arr", "Cleared approach"),
              note = goAroundNote("arr"), check = did("arr", "approach") },
            { text = S("arr_leave"), needScope = true, fast = true, rect = H.labelRect("arr"), note = goAroundNote("arr"),
              check = gone("arr"), leave = H.serverNext },
        },
        vectors = {
            { text = S("vec_wait"), needScope = true, fast = true, rect = H.labelRect("vec"), check = arrived("vec") },
            { text = S("vec_heading"), needScope = true, rect = H.menuItem("vec", "Fly heading", "Turn left heading", "Turn right heading"),
              enter = function() H.focus("vec") end, check = did("vec", "hdg") },
            { text = S("vec_descend"), needScope = true, rect = H.menuItem("vec", "Cleared altitude"),
              check = did("vec", "cfl") },
            { text = S("vec_approach"), needScope = true, rect = H.menuItem("vec", "Cleared approach"),
              note = goAroundNote("vec"), check = did("vec", "approach") },
            { text = S("vec_leave"), needScope = true, fast = true, rect = H.labelRect("vec"), note = goAroundNote("vec"),
              check = gone("vec"), leave = H.serverNext },
        },
        alerts = {
            { text = S("alerts_rules", H.payParams), next = true, needScope = true },
            { text = S("alerts_pay", H.payParams), next = true, needScope = true },
            { text = S("alerts_logout"), needScope = true, rect = H.scopeRect("logout") },
        },
    }
end
