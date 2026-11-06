if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Chest drain: site (click), anaesthesia (hold), incision (drag above the lower rib), blunt dissection
-- (timed clicks), tube (hold and push along the arrow), fixation (SPACE).

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local STEPS = { "site", "anaesthesia", "incision", "dissection", "tube", "fixation" }

-- lateral chest view: ribs 2..9 as bands, ICS k between rib k and k+1
local function ribY(g, n) return g.chest[2] + g.chest[4] * (0.06 + (n - 2) * 0.115) end
local RIB_T = 0.045

local function borders(g, y)
    -- pectoralis major lateral border (front) and latissimus dorsi anterior border (back) at height y
    local c = g.chest
    local u = (y - c[2]) / c[4]
    local front = c[1] + c[3] * (0.30 + 0.12 * u)
    local back = c[1] + c[3] * (0.74 - 0.12 * u)
    if g.options.side == "left" then front, back = c[1] + c[3] - (front - c[1]), c[1] + c[3] - (back - c[1]) end
    return math.min(front, back), math.max(front, back)
end

local function nippleY(g) return (ribY(g, 5) + ribY(g, 6)) / 2 + g.chest[4] * RIB_T / 2 end

-- -> intercostal space number at y, or nil on a rib
local function icsAt(g, y)
    for n = 2, 8 do
        local top, nextTop = ribY(g, n) + g.chest[4] * RIB_T, ribY(g, n + 1)
        if y > top and y < nextTop then return n end
    end
end

local function safeSite(g, x, y)
    local ics = icsAt(g, y)
    if not ics or ics < 4 or ics > 5 or y > nippleY(g) + sc(4) then return false end
    local a, b = borders(g, y)
    return x > a and x < b
end

local function stepIndex(g)
    for i, s in ipairs(STEPS) do if s == g.stage then return i end end
    return #STEPS + 1
end

GAME = {
    cursor = true,

    init = function(g)
        local ax, ay, aw, ah = MGK.area()
        g.chest = { ax + sc(20), ay + sc(10), aw * 0.6, ah - sc(30) }
        g.list = { ax + aw * 0.68, ay + sc(20), aw * 0.30 }
        g.stage, g.mistimed, g.anaes = "site", 0, 0
        -- close-up (incision / dissection / tube): two ribs
        local c = g.chest
        g.zoom = { upper = { c[2] + c[4] * 0.22, c[2] + c[4] * 0.36 }, lower = { c[2] + c[4] * 0.62, c[2] + c[4] * 0.76 } }
        g.dir = g.options.side == "left" and { -0.45, -0.89 } or { 0.45, -0.89 }
    end,

    click = function(g, button, state, cx, cy)
        if button ~= "left" then return end
        local c = g.chest
        if g.stage == "site" and state == "down" and MGK.inRect(cx, cy, c[1], c[2], c[3], c[4]) then
            g.site = { cx, cy }
            g.wrongSpot = not safeSite(g, cx, cy)
            g.stage = "anaesthesia"
        elseif g.stage == "incision" then
            if state == "down" then g.cut = { cx, cy } return end
            local s = g.cut
            g.cut = nil
            if not s then return end
            local len, my = math.abs(cx - s[1]), (cy + s[2]) / 2
            local z = g.zoom
            if len < sc(50) then g.msg = { g.now, "too_short" } return end
            if (my >= z.upper[1] and my <= z.upper[2]) or (my >= z.lower[1] and my <= z.lower[2]) then g.msg = { g.now, "on_rib" } return end
            if my < z.upper[1] or my > z.lower[2] then g.msg = { g.now, "off_space" } return end
            g.vessel = my <= z.upper[2] + sc(18)
            g.incision = { math.min(cx, s[1]), my, len }
            g.stage = "dissection"
            g.dissectStart, g.hits = g.now, 0
        elseif g.stage == "dissection" and state == "down" then
            local k = ((g.now - g.dissectStart) / 1000 % DRAIN.DISSECT_PERIOD) / DRAIN.DISSECT_PERIOD
            if math.abs(k - 0.75) <= DRAIN.DISSECT_WINDOW then g.hits = g.hits + 1 g.flash = { g.now, true }
            else g.mistimed = g.mistimed + 1 g.flash = { g.now, false } end
            if g.hits >= DRAIN.DISSECT_HITS then
                g.stage = "tube"
                g.tubeStart = { g.incision[1] + g.incision[3] / 2, g.incision[2] }
                g.tube = 0
            end
        end
    end,

    key = function(g, key, press)
        if key ~= DRAIN.KEY_FIX then return false end
        if press and g.stage == "fixation" then g.stage = "done" end
        return true
    end,

    update = function(g, dt)
        local cx, cy = MGK.cursor()
        if not cx then return end
        if g.stage == "anaesthesia" and MGK.isDown("left") and MGK.dist(cx, cy, g.site[1], g.site[2]) <= sc(24) then
            g.anaes = g.anaes + dt
            if g.anaes >= DRAIN.ANAESTHESIA then g.stage = "incision" end
        elseif g.stage == "tube" and MGK.isDown("left") then
            local dx, dy = cx - g.tubeStart[1], cy - g.tubeStart[2]
            local along = dx * g.dir[1] + dy * g.dir[2]
            local len = MGK.dist(0, 0, dx, dy)
            if len > sc(20) and along / len < 1 - DRAIN.TUBE_DEV then g.kink = true end
            g.tube = clamp(math.max(g.tube, along / sc(DRAIN.TUBE_LEN)), 0, 1)
            if g.tube >= 1 then g.stage = "fixation" end
        end
    end,

    done = function(g) return g.stage == "done" end,

    score = function(g)
        local steps = stepIndex(g) - 1
        local p = 100 - (g.wrongSpot and 35 or 0) - (g.vessel and 25 or 0) - g.mistimed * 5 - (g.kink and 10 or 0) - (6 - steps) * 12
        return p, { wrongSpot = g.wrongSpot == true, vessel = g.vessel == true, mistimed = g.mistimed, kink = g.kink == true, steps = steps }
    end,

    draw = function(g, ax, ay, aw, ah, now)
        local c = g.chest
        local closeUp = g.stage == "incision" or g.stage == "dissection" or g.stage == "tube" or g.stage == "fixation" or g.stage == "done"
        MGK.round(c[1], c[2], c[3], c[4], sc(30), COL.skin)
        if not closeUp then
            for n = 2, 9 do
                local y = ribY(g, n)
                dxDrawRectangle(c[1] + sc(10), y, c[3] - sc(20), c[4] * RIB_T, COL.skinDark)
                MGK.text(tostring(n), c[1] + sc(14), y - sc(4), sc(30), c[4] * RIB_T + sc(8), tocolor(120, 80, 55, 255), 0.8)
            end
            -- landmarks: pectoralis / latissimus borders, nipple line, axilla
            for _, frac in ipairs({ 0, 1 }) do
                local px, py
                for i = 0, 10 do
                    local y = c[2] + c[4] * (0.02 + i * 0.07)
                    local a, b = borders(g, y)
                    local x = frac == 0 and a or b
                    if px then MGK.line(px, py, x, y, tocolor(110, 70, 50, 230), sc(3)) end
                    px, py = x, y
                end
            end
            local ny = nippleY(g)
            for x = c[1] + sc(10), c[1] + c[3] - sc(20), sc(16) do MGK.line(x, ny, x + sc(8), ny, tocolor(255, 255, 255, 140), 1.5) end
            MGK.text(L("mg_chestdrain.client.nipple_line"), c[1] + c[3] - sc(200), ny - sc(24), sc(190), sc(20), COL.white, 0.85, "right")
            MGK.text(L("mg_chestdrain.client.axilla"), c[1], c[2] + sc(6), c[3], sc(20), tocolor(90, 60, 40, 255), 0.9, "center")
            if g.site then
                MGK.circle(g.site[1], g.site[2], sc(6), COL.accent)
                if g.stage == "anaesthesia" then
                    MGK.ring(g.site[1], g.site[2], sc(24), tocolor(255, 255, 255, 120), 1.5, true)
                    MGK.bar(g.site[1] - sc(40), g.site[2] + sc(30), sc(80), sc(8), g.anaes / DRAIN.ANAESTHESIA, COL.accent)
                end
            end
        else
            -- close-up: two ribs, the vessels under the upper one
            local z = g.zoom
            dxDrawRectangle(c[1] + sc(10), z.upper[1], c[3] - sc(20), z.upper[2] - z.upper[1], tocolor(232, 226, 210, 255))
            dxDrawRectangle(c[1] + sc(10), z.lower[1], c[3] - sc(20), z.lower[2] - z.lower[1], tocolor(232, 226, 210, 255))
            MGK.line(c[1] + sc(10), z.upper[2] + sc(5), c[1] + c[3] - sc(10), z.upper[2] + sc(5), tocolor(170, 40, 40, 255), sc(3))
            MGK.line(c[1] + sc(10), z.upper[2] + sc(10), c[1] + c[3] - sc(10), z.upper[2] + sc(10), tocolor(50, 80, 170, 255), sc(3))
            MGK.text(L("mg_chestdrain.client.upper_rib"), c[1] + sc(20), z.upper[1], sc(200), z.upper[2] - z.upper[1], tocolor(120, 110, 95, 255), 0.9)
            MGK.text(L("mg_chestdrain.client.lower_rib"), c[1] + sc(20), z.lower[1], sc(200), z.lower[2] - z.lower[1], tocolor(120, 110, 95, 255), 0.9)
            local cx, cy = MGK.cursor()
            if g.cut and cx then MGK.line(g.cut[1], g.cut[2], cx, cy, tocolor(110, 23, 23, 255), sc(3)) end
            if g.incision then
                local i = g.incision
                MGK.line(i[1], i[2], i[1] + i[3], i[2], tocolor(110, 23, 23, 255), sc(5))
            end
            if g.stage == "dissection" then
                local k = ((now - g.dissectStart) / 1000 % DRAIN.DISSECT_PERIOD) / DRAIN.DISSECT_PERIOD
                local mx, my = g.incision[1] + g.incision[3] / 2, g.incision[2]
                local r0 = sc(18)
                MGK.ring(mx, my, r0, COL.good, 2)
                MGK.ring(mx, my, r0 * 4 * (1 - k), COL.white, 2)
                MGK.text(L("mg_chestdrain.client.dissect_count", { n = g.hits, total = DRAIN.DISSECT_HITS }), mx - sc(100), my + sc(30), sc(200), sc(24), COL.text, 1.0, "center")
                if g.flash and now - g.flash[1] < 250 then MGK.circle(mx, my, r0, g.flash[2] and tocolor(63, 179, 122, 120) or tocolor(224, 82, 70, 120)) end
            elseif g.stage == "tube" or g.stage == "fixation" or g.stage == "done" then
                local s = g.tubeStart
                local L1 = sc(DRAIN.TUBE_LEN)
                if g.stage == "tube" then
                    for k = 0, 1, 0.1 do MGK.circle(s[1] + g.dir[1] * L1 * k, s[2] + g.dir[2] * L1 * k, sc(2), tocolor(255, 255, 255, 120)) end
                    MGK.line(s[1] + g.dir[1] * L1, s[2] + g.dir[2] * L1, s[1] + g.dir[1] * (L1 - sc(14)) - g.dir[2] * sc(8), s[2] + g.dir[2] * (L1 - sc(14)) + g.dir[1] * sc(8), COL.white, 2)
                end
                MGK.line(s[1], s[2], s[1] + g.dir[1] * L1 * g.tube, s[2] + g.dir[2] * L1 * g.tube, tocolor(220, 235, 240, 230), sc(7))
            end
        end
        if g.msg and now - g.msg[1] < 1300 then
            MGK.text(L("mg_chestdrain.client." .. g.msg[2]), c[1], c[2] + c[4] - sc(34), c[3], sc(28), COL.bad, 1.1, "center")
        end
        -- checklist
        local l = g.list
        local cur = stepIndex(g)
        for i, st in ipairs(STEPS) do
            local y = l[2] + (i - 1) * sc(40)
            local mark = i < cur and "✓" or (i == cur and "›" or "·")
            local col = i < cur and COL.good or (i == cur and COL.text or COL.dim)
            MGK.text(mark .. "  " .. L("mg_chestdrain.step." .. st), l[1], y, l[3], sc(32), col, 1.1)
        end
        local warn = {}
        if g.wrongSpot then warn[#warn + 1] = L("mg_chestdrain.client.warn_spot") end
        if g.vessel then warn[#warn + 1] = L("mg_chestdrain.client.warn_vessel") end
        if g.kink then warn[#warn + 1] = L("mg_chestdrain.client.warn_kink") end
        for i, txt in ipairs(warn) do MGK.text(txt, l[1], l[2] + sc(260) + (i - 1) * sc(30), l[3], sc(26), COL.bad, 0.95) end
    end,

    title = function(g) return L("mg_chestdrain.client.title_" .. g.options.side) end,
    status = function(g) return L("mg_chestdrain.client.landmark") end,
    hint = function(g) return L("mg_chestdrain.hint." .. (g.stage == "done" and "fixation" or g.stage), { key = DRAIN.KEY_FIX:upper() }) end,
}

---------------------------------------------------------------- exports

function startChestDrainGame(ped, options) return MGK.begin(ped, options, nil) end
function stopChestDrainGame() if not MGK.active() then return false end MGK.finish("cancelled", false) return true end
function isChestDrainGameActive() return MGK.active() end
