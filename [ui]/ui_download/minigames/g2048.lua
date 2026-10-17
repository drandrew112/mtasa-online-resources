-- 2048: a szamok osszehuzos jateka.
if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

local U, T = MG.U, MG.T
local floor, random = math.floor, math.random

local N = 4
local G = { best = 0 }

-- sotet tema: a ertekkel egyre telitettebb, vilagito szinek
local COLORS = {
    [2] = { 58, 64, 82 }, [4] = { 70, 78, 104 }, [8] = { 40, 110, 190 }, [16] = { 30, 140, 170 },
    [32] = { 30, 150, 120 }, [64] = { 80, 160, 60 }, [128] = { 190, 160, 40 }, [256] = { 205, 125, 35 },
    [512] = { 205, 80, 50 }, [1024] = { 180, 50, 120 }, [2048] = { 130, 70, 220 },
}

local function emptyCells()
    local out = {}
    for y = 1, N do
        for x = 1, N do
            if G.grid[y][x] == 0 then out[#out + 1] = { x, y } end
        end
    end
    return out
end

local function spawn()
    local e = emptyCells()
    if #e == 0 then return end
    local c = e[random(#e)]
    G.grid[c[2]][c[1]] = (random() < 0.9) and 2 or 4
    G.pop[c[2] * 10 + c[1]] = getTickCount()
end

local function canMove()
    for y = 1, N do
        for x = 1, N do
            local v = G.grid[y][x]
            if v == 0 then return true end
            if x < N and G.grid[y][x + 1] == v then return true end
            if y < N and G.grid[y + 1][x] == v then return true end
        end
    end
    return false
end

local function reset()
    G.grid = {}
    for y = 1, N do
        G.grid[y] = {}
        for x = 1, N do G.grid[y][x] = 0 end
    end
    G.pop = {}
    G.score = 0
    G.over = false
    G.won = false
    G.keepPlaying = false
    spawn()
    spawn()
end

-- Egy sor osszehuzasa az elejere; visszaadja az uj sort, a nyert pontot es hogy valtozott-e.
local function slideLine(line)
    local vals = {}
    for i = 1, N do if line[i] ~= 0 then vals[#vals + 1] = line[i] end end
    local out, gained, i = {}, 0, 1
    while i <= #vals do
        if vals[i + 1] == vals[i] then
            out[#out + 1] = vals[i] * 2
            gained = gained + vals[i] * 2
            i = i + 2
        else
            out[#out + 1] = vals[i]
            i = i + 1
        end
    end
    for k = #out + 1, N do out[k] = 0 end
    local changed = false
    for k = 1, N do if out[k] ~= line[k] then changed = true end end
    return out, gained, changed
end

local function move(dir)
    local any = false
    for i = 1, N do
        local line = {}
        for k = 1, N do
            if dir == "left" then line[k] = G.grid[i][k]
            elseif dir == "right" then line[k] = G.grid[i][N + 1 - k]
            elseif dir == "up" then line[k] = G.grid[k][i]
            else line[k] = G.grid[N + 1 - k][i] end
        end
        local out, gained, changed = slideLine(line)
        if changed then
            any = true
            G.score = G.score + gained
            for k = 1, N do
                local gy, gx
                if dir == "left" then gy, gx = i, k
                elseif dir == "right" then gy, gx = i, N + 1 - k
                elseif dir == "up" then gy, gx = k, i
                else gy, gx = N + 1 - k, i end
                if out[k] ~= G.grid[gy][gx] and out[k] ~= 0 then G.pop[gy * 10 + gx] = getTickCount() end
                G.grid[gy][gx] = out[k]
            end
        end
    end
    if not any then return end
    spawn()
    G.best = math.max(G.best, G.score)
    if not G.won and not G.keepPlaying then
        for y = 1, N do for x = 1, N do if G.grid[y][x] >= 2048 then G.won = true end end end
    end
    if not canMove() then G.over = true end
end

local function tileColor(v)
    local c = COLORS[v] or { 150, 90, 255 }
    return tocolor(c[1], c[2], c[3])
end

local function draw(cx, top, areaW, areaH)
    if not G.grid then reset() end
    local hud = U(46)
    local size = floor(math.min(areaH - hud - U(40), areaW * 0.8))
    local pad = floor(size * 0.03)
    local cs = floor((size - pad * (N + 1)) / N)
    size = cs * N + pad * (N + 1)
    local x0, y0 = floor(cx - size / 2), floor(top + hud)

    MG.text(T("ui_download.mg.score", { score = G.score }), x0, top, size / 2, hud - U(8), tocolor(255, 255, 255), U(1.4), "default-bold", "left")
    MG.text(T("ui_download.mg.best", { best = G.best }), x0 + size / 2, top, size / 2, hud - U(8), tocolor(200, 200, 200), U(1.2), "default-bold", "right")

    MG.roundRect(x0, y0, size, size, U(8), tocolor(22, 24, 32, 245))
    local now = getTickCount()
    for y = 1, N do
        for x = 1, N do
            local tx = x0 + pad + (x - 1) * (cs + pad)
            local ty = y0 + pad + (y - 1) * (cs + pad)
            local v = G.grid[y][x]
            if v == 0 then
                MG.roundRect(tx, ty, cs, cs, U(6), tocolor(38, 41, 54, 255))
            else
                local sc = 1
                local t0 = G.pop[y * 10 + x]
                if t0 then
                    local k = (now - t0) / 140
                    if k < 1 then sc = 0.6 + 0.4 * k + math.sin(k * math.pi) * 0.12 end
                end
                local s = cs * sc
                local ox = (cs - s) / 2
                MG.roundRect(tx + ox, ty + ox, s, s, U(6), tileColor(v))
                local digits = #tostring(v)
                local scale = (digits <= 2 and 2.4 or digits == 3 and 2.0 or 1.6) * (cs / U(100))
                MG.text(tostring(v), tx, ty, cs, cs, v <= 4 and tocolor(190, 198, 220) or tocolor(255, 255, 255), scale, "default-bold")
            end
        end
    end

    if G.over then
        MG.roundRect(x0, y0, size, size, U(8), tocolor(10, 12, 18, 215))
        MG.text(T("ui_download.mg.game_over"), x0, y0 + size * 0.35, size, U(60), tocolor(255, 90, 90), U(3), "default-bold")
        MG.text(T("ui_download.mg.restart"), x0, y0 + size * 0.35 + U(70), size, U(30), tocolor(200, 205, 225), U(1.2), "default-bold")
    elseif G.won and not G.keepPlaying then
        MG.roundRect(x0, y0, size, size, U(8), tocolor(60, 35, 110, 220))
        MG.text(T("ui_download.mg.you_win"), x0, y0 + size * 0.35, size, U(60), tocolor(255, 255, 255), U(3), "default-bold")
        MG.text(T("ui_download.mg.win_continue"), x0, y0 + size * 0.35 + U(70), size, U(30), tocolor(255, 255, 255), U(1.2), "default-bold")
    end

    MG.text(T("ui_download.mg.controls_move") .. "   |   " .. T("ui_download.mg.controls_back"), 0, y0 + size + U(10), MG.sw, U(24), tocolor(190, 190, 190, 230), U(1.0), "default")
end

MG.register({
    id = "g2048",
    nameKey = "ui_download.mg.g2048_name",
    descKey = "ui_download.mg.g2048_desc",
    color = tocolor(246, 150, 90),
    reset = reset,
    update = function() end,
    draw = draw,
    key = function(act)
        if not G.grid then return end
        if act == "action" then
            if G.over then reset()
            elseif G.won then G.keepPlaying = true end
            return
        end
        if G.over or (G.won and not G.keepPlaying) then return end
        move(act)
    end,
    icon = function(cx, cy, s)
        MG.roundRect(cx - s * 0.5, cy - s * 0.5, s, s, s * 0.15, tocolor(130, 70, 220))
        MG.text("2048", cx - s * 0.5, cy - s * 0.5, s, s, tocolor(255, 255, 255), s / U(30), "default-bold")
    end,
})
