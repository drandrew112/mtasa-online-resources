-- Snake: kigyoval gyujtogetunk, jobbra/balra/fel/le.
if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

local U, T = MG.U, MG.T
local floor, random = math.floor, math.random

local COLS, ROWS = 24, 16
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }

local G = { best = 0 }

local function placeFood()
    local used = {}
    for _, s in ipairs(G.body) do used[s[2] * COLS + s[1]] = true end
    if #G.body >= COLS * ROWS then G.food = nil; return end
    repeat
        G.food = { random(0, COLS - 1), random(0, ROWS - 1) }
    until not used[G.food[2] * COLS + G.food[1]]
end

local function reset()
    G.body = { { 8, 8 }, { 7, 8 }, { 6, 8 } } -- [1] = fej
    G.dir = "right"
    G.queue = {}
    G.acc = 0
    G.score = 0
    G.over = false
    G.started = false
    placeFood()
end

local function interval()
    return math.max(0.06, 0.15 - (#G.body - 3) * 0.003)
end

local function step()
    if #G.queue > 0 then
        local d = table.remove(G.queue, 1)
        if d ~= OPP[G.dir] then G.dir = d end
    end
    local head = G.body[1]
    local d = DIRS[G.dir]
    local nx, ny = head[1] + d[1], head[2] + d[2]
    local grow = G.food and nx == G.food[1] and ny == G.food[2]

    local last = #G.body
    if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then G.over = true end
    if not G.over then
        for i = 1, grow and last or last - 1 do -- a farok elmozdul, ha nem nottunk
            local s = G.body[i]
            if s[1] == nx and s[2] == ny then G.over = true; break end
        end
    end
    if G.over then
        G.best = math.max(G.best, G.score)
        return
    end

    table.insert(G.body, 1, { nx, ny })
    if grow then
        G.score = G.score + 10
        placeFood()
    else
        table.remove(G.body)
    end
end

local function update(dt)
    if not G.body or G.over or not G.started then return end
    G.acc = G.acc + dt
    local iv = interval()
    while G.acc >= iv and not G.over do
        G.acc = G.acc - iv
        step()
    end
end

local function draw(cx, top, areaW, areaH)
    if not G.body then reset() end
    local hud = U(46)
    local cs = floor(math.min((areaH - hud - U(30)) / ROWS, (areaW * 0.9) / COLS))
    local bw, bh = cs * COLS, cs * ROWS
    local x0, y0 = floor(cx - bw / 2), floor(top + hud)

    MG.text(T("ui_download.mg.score", { score = G.score }), x0, top, bw / 2, hud - U(8), tocolor(255, 255, 255), U(1.4), "default-bold", "left")
    MG.text(T("ui_download.mg.best", { best = math.max(G.best, G.score) }), x0 + bw / 2, top, bw / 2, hud - U(8), tocolor(200, 200, 200), U(1.2), "default-bold", "right")

    MG.rect(x0 - 4, y0 - 4, bw + 8, bh + 8, tocolor(90, 200, 90, 230))
    MG.rect(x0, y0, bw, bh, tocolor(8, 14, 10, 245))
    for y = 0, ROWS - 1 do
        for x = (y % 2), COLS - 1, 2 do
            MG.rect(x0 + x * cs, y0 + y * cs, cs, cs, tocolor(14, 24, 16, 245))
        end
    end

    if G.food then
        local pulse = 1 + math.sin(getTickCount() / 180) * 0.08
        MG.pie(x0 + (G.food[1] + 0.5) * cs, y0 + (G.food[2] + 0.5) * cs, cs * 0.32 * pulse, tocolor(255, 70, 70), nil, nil, 14)
        MG.rect(x0 + (G.food[1] + 0.5) * cs - 1, y0 + G.food[2] * cs + cs * 0.1, 2, cs * 0.2, tocolor(120, 220, 90))
    end

    local n = #G.body
    for i = n, 1, -1 do
        local s = G.body[i]
        local t = 1 - (i - 1) / math.max(n, 1) * 0.5
        local col = (i == 1) and tocolor(150, 255, 110) or tocolor(floor(40 * t), floor(200 * t), floor(60 * t))
        MG.roundRect(x0 + s[1] * cs + 1, y0 + s[2] * cs + 1, cs - 2, cs - 2, cs * 0.25, col)
    end
    -- szemek
    local h = G.body[1]
    local d = DIRS[G.dir]
    local hx, hy = x0 + (h[1] + 0.5) * cs, y0 + (h[2] + 0.5) * cs
    local px, py = -d[2], d[1] -- meroleges
    for _, sgn in ipairs({ -1, 1 }) do
        local ex = hx + d[1] * cs * 0.15 + px * sgn * cs * 0.2
        local ey = hy + d[2] * cs * 0.15 + py * sgn * cs * 0.2
        MG.pie(ex, ey, cs * 0.11, tocolor(10, 10, 10), nil, nil, 8)
    end

    if not G.started and not G.over then
        MG.text(T("ui_download.mg.snake_start"), x0, y0, bw, bh, tocolor(255, 255, 255), U(1.6), "default-bold")
    end
    if G.over then
        MG.rect(x0, y0, bw, bh, tocolor(0, 0, 0, 180))
        MG.text(T("ui_download.mg.game_over"), x0, y0 + bh * 0.3, bw, U(60), tocolor(255, 70, 70), U(3), "default-bold")
        MG.text(T("ui_download.mg.score", { score = G.score }), x0, y0 + bh * 0.3 + U(60), bw, U(30), tocolor(255, 255, 255), U(1.5), "default-bold")
        MG.text(T("ui_download.mg.restart"), x0, y0 + bh * 0.3 + U(110), bw, U(30), tocolor(255, 224, 0), U(1.2), "default-bold")
    end

    MG.text(T("ui_download.mg.controls_move") .. "   |   " .. T("ui_download.mg.controls_back"), 0, y0 + bh + U(14), MG.sw, U(24), tocolor(190, 190, 190, 230), U(1.0), "default")
end

MG.register({
    id = "snake",
    nameKey = "ui_download.mg.snake_name",
    descKey = "ui_download.mg.snake_desc",
    color = tocolor(110, 230, 90),
    reset = reset,
    update = update,
    draw = draw,
    key = function(act)
        if not G.body then return end
        if act == "action" then
            if G.over then reset() else G.started = true end
            return
        end
        if G.over then return end
        G.started = true
        local last = G.queue[#G.queue] or G.dir
        if act ~= last and act ~= OPP[last] and #G.queue < 2 then
            G.queue[#G.queue + 1] = act
        end
    end,
    icon = function(cx, cy, s)
        local c = tocolor(110, 230, 90)
        local seg = s * 0.34
        local pts = { { -1.3, 0.5 }, { -0.45, 0.5 }, { 0.4, 0.5 }, { 0.4, -0.35 }, { 1.2, -0.35 } }
        for i = 1, #pts do
            MG.roundRect(cx + pts[i][1] * seg * 1.3 - seg / 2, cy + pts[i][2] * seg * 1.3 - seg / 2, seg, seg, seg * 0.25, c)
        end
        MG.pie(cx + 1.2 * seg * 1.3 + seg * 1.2, cy - 0.35 * seg * 1.3, seg * 0.28, tocolor(255, 70, 70), nil, nil, 10)
    end,
})
