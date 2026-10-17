-- Pac-Man: sarga lenyel eszik a golyokat a kek falas labirintusban, a szellemek elol menekul.
if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

local U, T = MG.U, MG.T
local pi, cos, sin, abs, floor, random = math.pi, math.cos, math.sin, math.abs, math.floor, math.random

-- '#' fal, '.' golyo, 'o' nagy golyo, '-' szellem-ajto, 'P' jatekos, 'G' szellem-haz
local MAZE = {
    "###################",
    "#........#........#",
    "#o##.###.#.###.##o#",
    "#.................#",
    "#.##.#.#####.#.##.#",
    "#....#...#...#....#",
    "####.###.#.###.####",
    "   #.#.......#.#   ",
    "####.#.##-##.#.####",
    "    . .#GGG#. .    ",
    "####.#.#####.#.####",
    "   #.#.......#.#   ",
    "####.###.#.###.####",
    "#........#........#",
    "#.##.###.#.###.##.#",
    "#o.#.....P.....#.o#",
    "##.#.#.#####.#.#.##",
    "#....#...#...#....#",
    "#.######.#.######.#",
    "#.................#",
    "###################",
}
local W, H = #MAZE[1], #MAZE
local DOOR_X, DOOR_Y = 9, 8   -- 0-alapu oszlop / sor (0-based: x=9,y=8 a '-' mezo)
local EXIT_X, EXIT_Y = 9, 7   -- a ajto folotti mezo
-- (a MAZE sorai 1-alapuak a Lua tombben, a mezok 0-alapuak)

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local DIR_LIST = { "up", "left", "down", "right" }
local OPP = { up = "down", down = "up", left = "right", right = "left" }

local wall = {}      -- wall[y][x] = '#', '-' vagy nil
local pellets, pelletCount

local function cell(x, y)
    if y < 0 or y >= H then return "#" end
    x = x % W
    return MAZE[y + 1]:sub(x + 1, x + 1)
end

local function walkable(x, y, ghost)
    local c = cell(x, y)
    if c == "#" then return false end
    if c == "-" then return ghost == true end
    return true
end

local G = {}   -- jatek allapot

local GHOST_COLORS = {
    tocolor(255, 60, 60), tocolor(255, 150, 220), tocolor(60, 230, 255), tocolor(255, 170, 40),
}
local CORNERS = { { W - 2, 0 }, { 1, 0 }, { W - 2, H - 1 }, { 1, H - 1 } }

local function newEntity(x, y)
    return { x = x, y = y, dir = nil, prog = 0 }
end

local function loadMaze()
    pellets, pelletCount = {}, 0
    G.pstart = nil
    G.houses = {}
    for y = 0, H - 1 do
        pellets[y] = {}
        for x = 0, W - 1 do
            local c = cell(x, y)
            if c == "." or c == "o" then
                pellets[y][x] = c
                pelletCount = pelletCount + 1
            elseif c == "P" then
                G.pstart = { x, y }
            elseif c == "G" then
                G.houses[#G.houses + 1] = { x, y }
            end
        end
    end
end

local function resetPositions()
    local p = G.pstart
    G.pac = newEntity(p[1], p[2])
    G.pac.want = nil
    G.ghosts = {}
    for i = 1, 4 do
        local h = G.houses[((i - 1) % #G.houses) + 1]
        local gh = newEntity(h[1], h[2])
        gh.i = i
        gh.state = "house"
        gh.release = (i - 1) * 3.0 / (1 + (G.level - 1) * 0.15)
        G.ghosts[i] = gh
    end
    G.ghosts[1].release = 0.8
    G.frightened = 0
    G.chain = 0
    G.readyTimer = 1.8
    G.deadTimer = nil
    G.modeClock = 0
end

local function newLevel()
    loadMaze()
    resetPositions()
end

local function reset()
    G.score = 0
    G.lives = 3
    G.level = 1
    G.over = false
    G.won = false
    G.best = G.best or 0
    newLevel()
end

-- ---------------------------------------------------------------- mozgas
local function nextTile(e, dir)
    local d = DIRS[dir]
    return (e.x + d[1]) % W, e.y + d[2]
end

local function canGo(e, dir, ghost)
    local d = DIRS[dir]
    return walkable(e.x + d[1], e.y + d[2], ghost)
end

-- Elore halad az entity; arrive(e) hivodik, ha uj mezore ert.
local function advance(e, dist, ghost, arrive)
    while dist > 0 do
        if not e.dir then
            arrive(e)
            if not e.dir then return end
        end
        local need = 1 - e.prog
        if dist < need then
            e.prog = e.prog + dist
            return
        end
        dist = dist - need
        e.x, e.y = nextTile(e, e.dir)
        e.prog = 0
        arrive(e)
        if not e.dir then return end
    end
end

local function pacArrive(e)
    local p = pellets[e.y] and pellets[e.y][e.x]
    if p then
        pellets[e.y][e.x] = nil
        pelletCount = pelletCount - 1
        if p == "o" then
            G.score = G.score + 50
            G.frightened = math.max(3, 7 - (G.level - 1) * 0.6)
            G.chain = 0
            for _, gh in ipairs(G.ghosts) do
                if gh.state == "chase" then gh.state = "fright" end
            end
        else
            G.score = G.score + 10
        end
    end
    if e.want and canGo(e, e.want) then
        e.dir = e.want
    elseif e.dir and not canGo(e, e.dir) then
        e.dir = nil
    end
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function ghostTarget(gh)
    local pac = G.pac
    local scatter = (G.modeClock % 27) < 6
    if scatter and gh.state == "chase" and G.level < 4 then
        return CORNERS[gh.i][1], CORNERS[gh.i][2]
    end
    local tx, ty = pac.x, pac.y
    local d = pac.dir and DIRS[pac.dir] or { 0, 0 }
    if gh.i == 2 then
        tx, ty = tx + d[1] * 4, ty + d[2] * 4
    elseif gh.i == 3 then
        tx, ty = tx - d[1] * 2 + (random() - 0.5) * 8, ty - d[2] * 2 + (random() - 0.5) * 8
    elseif gh.i == 4 and dist2(gh.x, gh.y, pac.x, pac.y) < 49 then
        return CORNERS[4][1], CORNERS[4][2]
    end
    return tx, ty
end

-- BFS tavolsag a haz ajtajatol (a halott szellemek ezen mennek haza)
local homeDist
local function buildHomeDist()
    homeDist = {}
    local q, qi = { { EXIT_X, EXIT_Y } }, 1
    homeDist[EXIT_Y * W + EXIT_X] = 0
    while qi <= #q do
        local c = q[qi]; qi = qi + 1
        local base = homeDist[c[2] * W + c[1]]
        for _, d in pairs(DIRS) do
            local nx, ny = (c[1] + d[1]) % W, c[2] + d[2]
            if walkable(nx, ny, false) and homeDist[ny * W + nx] == nil then
                homeDist[ny * W + nx] = base + 1
                q[#q + 1] = { nx, ny }
            end
        end
    end
end

local function ghostArrive(gh)
    if gh.state == "dead" then
        if gh.x == EXIT_X and gh.y == EXIT_Y then
            -- visszaer a hazba: ujraeled
            gh.x, gh.y = DOOR_X, DOOR_Y + 1
            gh.state = "house"
            gh.release = 1.5
            gh.dir, gh.prog = nil, 0
            return
        end
        local best, bd
        for _, name in ipairs(DIR_LIST) do
            if canGo(gh, name, true) then
                local nx, ny = nextTile(gh, name)
                local dd = homeDist[ny * W + nx]
                if dd and (not bd or dd < bd) then best, bd = name, dd end
            end
        end
        gh.dir = best
        return
    end

    local opts = {}
    for _, name in ipairs(DIR_LIST) do
        if name ~= OPP[gh.dir or ""] and canGo(gh, name, false) then opts[#opts + 1] = name end
    end
    if #opts == 0 then
        -- zsakutca: megfordul
        local back = gh.dir and OPP[gh.dir]
        gh.dir = (back and canGo(gh, back, false)) and back or nil
        return
    end
    if gh.state == "fright" or random() < 0.12 then
        gh.dir = opts[random(#opts)]
        return
    end
    local tx, ty = ghostTarget(gh)
    local best, bd
    for _, name in ipairs(opts) do
        local nx, ny = nextTile(gh, name)
        local dd = dist2(nx, ny, tx, ty)
        if not bd or dd < bd then best, bd = name, dd end
    end
    gh.dir = best
end

local function loseLife()
    G.lives = G.lives - 1
    G.deadTimer = 1.5
end

local function update(dt)
    if not G.pac then return end
    if G.over then return end

    if G.deadTimer then
        G.deadTimer = G.deadTimer - dt
        if G.deadTimer <= 0 then
            G.deadTimer = nil
            if G.lives <= 0 then
                G.over = true
                G.best = math.max(G.best, G.score)
            else
                resetPositions()
            end
        end
        return
    end
    if G.won then return end
    if G.readyTimer > 0 then
        G.readyTimer = G.readyTimer - dt
        return
    end

    G.modeClock = G.modeClock + dt
    if G.frightened > 0 then
        G.frightened = G.frightened - dt
        if G.frightened <= 0 then
            for _, gh in ipairs(G.ghosts) do
                if gh.state == "fright" then gh.state = "chase" end
            end
        end
    end

    local speed = 6.2 + (G.level - 1) * 0.35
    advance(G.pac, speed * dt, false, pacArrive)

    for _, gh in ipairs(G.ghosts) do
        if gh.state == "house" then
            gh.release = gh.release - dt
            if gh.release <= 0 then
                gh.x, gh.y = EXIT_X, EXIT_Y
                gh.prog = 0
                gh.dir = (random() < 0.5) and "left" or "right"
                gh.state = G.frightened > 0 and "fright" or "chase"
            end
        else
            local gs = speed * 0.88
            if gh.state == "fright" then gs = speed * 0.55
            elseif gh.state == "dead" then gs = speed * 1.8 end
            advance(gh, gs * dt, true, ghostArrive)
        end

        -- utkozes
        if gh.state ~= "house" and not G.deadTimer then
            local px = G.pac.x + (G.pac.dir and DIRS[G.pac.dir][1] * G.pac.prog or 0)
            local py = G.pac.y + (G.pac.dir and DIRS[G.pac.dir][2] * G.pac.prog or 0)
            local gx = gh.x + (gh.dir and DIRS[gh.dir][1] * gh.prog or 0)
            local gy = gh.y + (gh.dir and DIRS[gh.dir][2] * gh.prog or 0)
            if dist2(px, py, gx, gy) < 0.45 then
                if gh.state == "fright" then
                    gh.state = "dead"
                    G.chain = G.chain + 1
                    G.score = G.score + 100 * 2 ^ G.chain
                elseif gh.state == "chase" then
                    loseLife()
                end
            end
        end
    end

    if pelletCount <= 0 then
        G.won = true
        G.winTimer = 2.0
    end
end

local function afterWinTick(dt)
    if G.won and G.winTimer then
        G.winTimer = G.winTimer - dt
        if G.winTimer <= 0 then
            G.winTimer = nil
            G.won = false
            G.level = G.level + 1
            newLevel()
        end
    end
end

-- ---------------------------------------------------------------- rajzolas
local BLUE = tocolor(30, 60, 255)
local BLUE_FILL = tocolor(10, 20, 90)
local YELLOW = tocolor(255, 224, 0)

local function drawGhost(cx, cy, r, gh)
    local col = GHOST_COLORS[gh.i]
    if gh.state == "fright" then
        local blink = G.frightened < 2 and floor(getTickCount() / 200) % 2 == 0
        col = blink and tocolor(240, 240, 240) or tocolor(40, 60, 255)
    end
    if gh.state ~= "dead" then
        MG.pie(cx, cy - r * 0.1, r, col, pi, pi * 2, 14)
        MG.rect(cx - r, cy - r * 0.1, r * 2, r * 1.0, col)
        -- labak
        local wob = floor(getTickCount() / 150) % 2
        for k = 0, 2 do
            local fx = cx - r + (k + 0.5) * (r * 2 / 3)
            MG.pie(fx, cy + r * 0.9 + (k + wob) % 2 * 0, r / 3, col, 0, pi, 6)
        end
    end
    -- szemek
    local ex = gh.dir and DIRS[gh.dir][1] * r * 0.15 or 0
    local ey = gh.dir and DIRS[gh.dir][2] * r * 0.15 or 0
    if gh.state == "fright" then
        MG.pie(cx - r * 0.35, cy - r * 0.2, r * 0.16, tocolor(255, 220, 200), nil, nil, 8)
        MG.pie(cx + r * 0.35, cy - r * 0.2, r * 0.16, tocolor(255, 220, 200), nil, nil, 8)
    else
        for _, sx in ipairs({ -0.38, 0.38 }) do
            MG.pie(cx + r * sx, cy - r * 0.2, r * 0.3, tocolor(255, 255, 255), nil, nil, 10)
            MG.pie(cx + r * sx + ex, cy - r * 0.2 + ey, r * 0.15, tocolor(20, 40, 200), nil, nil, 8)
        end
    end
end

local function drawPac(cx, cy, r, dirName, mouth)
    local ang = ({ right = 0, down = pi / 2, left = pi, up = pi * 1.5 })[dirName or "right"]
    if mouth < 0.02 then
        MG.pie(cx, cy, r, YELLOW, nil, nil, 20)
    else
        MG.pie(cx, cy, r, YELLOW, ang + mouth, ang + pi * 2 - mouth, 22)
    end
end

local function drawBoard(x0, y0, cs)
    -- hatter
    MG.rect(x0 - cs * 0.3, y0 - cs * 0.3, W * cs + cs * 0.6, H * cs + cs * 0.6, tocolor(0, 0, 0, 240))
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local c = cell(x, y)
            local px, py = x0 + x * cs, y0 + y * cs
            if c == "#" then
                MG.rect(px, py, cs, cs, BLUE_FILL)
                -- vilagos el a szomszedos ures mezok fele
                local t = math.max(2, cs * 0.09)
                if y > 0 and cell(x, y - 1) ~= "#" then MG.rect(px, py, cs, t, BLUE) end
                if y < H - 1 and cell(x, y + 1) ~= "#" then MG.rect(px, py + cs - t, cs, t, BLUE) end
                if x > 0 and cell(x - 1, y) ~= "#" then MG.rect(px, py, t, cs, BLUE) end
                if x < W - 1 and cell(x + 1, y) ~= "#" then MG.rect(px + cs - t, py, t, cs, BLUE) end
            elseif c == "-" then
                MG.rect(px, py + cs * 0.42, cs, cs * 0.16, tocolor(255, 160, 220))
            end
            local p = pellets[y][x]
            if p == "." then
                MG.pie(px + cs / 2, py + cs / 2, cs * 0.1, tocolor(255, 210, 160), nil, nil, 8)
            elseif p == "o" and floor(getTickCount() / 250) % 2 == 0 then
                MG.pie(px + cs / 2, py + cs / 2, cs * 0.26, tocolor(255, 210, 160), nil, nil, 12)
            end
        end
    end
end

local function entityPos(e, x0, y0, cs)
    local d = e.dir and DIRS[e.dir] or { 0, 0 }
    local fx, fy = e.x + d[1] * e.prog, e.y + d[2] * e.prog
    return x0 + (fx + 0.5) * cs, y0 + (fy + 0.5) * cs, fx
end

local function draw(cx, top, areaW, areaH)
    if not G.pac then reset() end
    local hud = U(46)
    local cs = math.floor(math.min((areaH - hud) / (H + 0.6), (areaW * 0.9) / (W + 0.6)))
    local bw, bh = W * cs, H * cs
    local x0 = math.floor(cx - bw / 2)
    local y0 = math.floor(top + hud)

    -- HUD
    MG.text(T("ui_download.mg.score", { score = floor(G.score) }), x0, top, bw / 3, hud - U(8), tocolor(255, 255, 255), U(1.4), "default-bold", "left")
    MG.text(T("ui_download.mg.level", { level = G.level }), x0 + bw / 3, top, bw / 3, hud - U(8), tocolor(200, 200, 200), U(1.2), "default-bold")
    MG.text(T("ui_download.mg.lives", { lives = math.max(G.lives, 0) }), x0 + bw * 2 / 3, top, bw / 3, hud - U(8), tocolor(255, 224, 0), U(1.4), "default-bold", "right")

    drawBoard(x0, y0, cs)

    local r = cs * 0.42
    -- jatekos
    if not G.over then
        local px, py, fx = entityPos(G.pac, x0, y0, cs)
        if fx > -0.4 and fx < W - 0.6 then
            local mouth
            if G.deadTimer then
                mouth = pi * (1 - math.max(G.deadTimer, 0) / 1.5) -- eltunik
                mouth = math.min(mouth, pi)
            else
                mouth = (G.pac.dir and (abs(sin(getTickCount() / 90)) * 0.7) or 0.35)
            end
            drawPac(px, py, r, G.pac.dir or G.pac.want or "right", mouth)
        end
    end
    -- szellemek
    if not G.deadTimer or G.deadTimer > 1.0 then
        for _, gh in ipairs(G.ghosts) do
            local gx, gy, fx = entityPos(gh, x0, y0, cs)
            if fx > -0.4 and fx < W - 0.6 then drawGhost(gx, gy, r, gh) end
        end
    end

    if G.readyTimer > 0 and not G.over then
        MG.text(T("ui_download.mg.ready"), x0, y0 + cs * 11.1, bw, cs, tocolor(255, 224, 0), U(1.6), "default-bold")
    end
    if G.won then
        MG.text(T("ui_download.mg.level_clear"), x0, y0 + cs * 11.1, bw, cs, tocolor(120, 255, 120), U(1.8), "default-bold")
    end
    if G.over then
        MG.rect(x0, y0, bw, bh, tocolor(0, 0, 0, 190))
        MG.text(T("ui_download.mg.game_over"), x0, y0 + bh * 0.38, bw, U(60), tocolor(255, 70, 70), U(3), "default-bold")
        MG.text(T("ui_download.mg.score", { score = floor(G.score) }), x0, y0 + bh * 0.38 + U(60), bw, U(30), tocolor(255, 255, 255), U(1.5), "default-bold")
        MG.text(T("ui_download.mg.best", { best = floor(G.best) }), x0, y0 + bh * 0.38 + U(90), bw, U(30), tocolor(200, 200, 200), U(1.2), "default")
        MG.text(T("ui_download.mg.restart"), x0, y0 + bh * 0.38 + U(130), bw, U(30), tocolor(255, 224, 0), U(1.2), "default-bold")
    end

    MG.text(T("ui_download.mg.controls_move") .. "   |   " .. T("ui_download.mg.controls_back"), 0, y0 + bh + U(8), MG.sw, U(24), tocolor(190, 190, 190, 230), U(1.0), "default")
end

local def = {
    id = "pacman",
    nameKey = "ui_download.mg.pacman_name",
    descKey = "ui_download.mg.pacman_desc",
    color = tocolor(255, 224, 0),
    reset = function() buildHomeDist(); reset() end,
    update = function(dt)
        if not G.pac then return end
        update(dt)
        afterWinTick(dt)
    end,
    draw = draw,
    key = function(act)
        if act == "action" then
            if G.over then reset() end
            return
        end
        if not G.pac or G.over then return end
        local e = G.pac
        e.want = act
        -- menet kozbeni azonnali visszafordulas
        if e.dir and OPP[e.dir] == act and G.readyTimer <= 0 then
            local d = DIRS[e.dir]
            e.x, e.y = (e.x + d[1]) % W, e.y + d[2]
            e.prog = 1 - e.prog
            e.dir = act
        elseif not e.dir and canGo(e, act) and G.readyTimer <= 0 then
            e.dir = act
        end
    end,
    icon = function(cx, cy, s)
        MG.pie(cx, cy, s * 0.5, YELLOW, 0.55, pi * 2 - 0.55, 22)
        MG.pie(cx + s * 0.95, cy, s * 0.1, tocolor(255, 210, 160), nil, nil, 8)
    end,
}
MG.register(def)
