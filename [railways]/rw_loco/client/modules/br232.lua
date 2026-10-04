-- BR 232 (Streak model) cab desk. Black / dark blue housing, blue switch bands, white analog
-- instruments with black needles (no digital displays on this loco). Diesel: battery,
-- fuel pump, engine start / stop; lights; passenger doors (with coaches); Sifa acknowledge.
-- The train itself is a rw_customtracks network train: W / S move its controller (shown on
-- the CONTROL gauge, brake side negative), the DIR switch is the reverser (standing only), the
-- TARGET gauge shows the distance left of the movement authority (next red signal, train ahead,
-- destination) and the ATP lamp lights while the train protection brakes.
--
-- Everything static (housing, gauge faces, labels, bezels) is drawn once into a render
-- target; each frame only adds needles, levers and lamps.

local M = {}
local rt, rtW, rtH
local v = { volt = 0, fuel = 0, oil = 0, rpm = 0, temp = 18, load = 0, speed = 0, ctrl = 0, target = 0 }
local pressed = {}           -- [control] = tick until which it looks pressed
local lastT = getTickCount()

-- base-unit layout (900 x 270), scaled by Loco.s
local G = {
    volt  = { 60, 46, 30, { min = 0, max = 150, major = 50, minor = 10, title = "BATTERY", unit = "V" } },
    fuel  = { 146, 46, 30, { min = 0, max = 6, major = 2, minor = 0.5, title = "FUEL", unit = "bar" } },
    oil   = { 232, 46, 30, { min = 0, max = 8, major = 4, minor = 1, title = "OIL", unit = "bar" } },
    temp  = { 60, 124, 30, { min = 0, max = 120, major = 60, minor = 10, red = { 100, 120 }, title = "COOLANT", unit = "°C" } },
    rpm   = { 146, 124, 30, { min = 0, max = 1200, major = 600, minor = 100, div = 100, red = { 1050, 1200 }, title = "ENGINE", unit = "x100" } },
    load  = { 232, 124, 30, { min = 0, max = 100, major = 50, minor = 10, title = "LOAD", unit = "%" } },
    speed = { 420, 88, 72, { min = 0, max = 140, major = 20, minor = 5, labelStep = 20, red = { 120, 140 }, unit = "km/h" } },
    ctrl  = { 305, 46, 30, { min = -100, max = 100, major = 100, minor = 25, title = "CONTROL", unit = "%" } },
    target = { 305, 124, 30, { min = 0, max = 2000, major = 1000, minor = 250, div = 100, red = { 0, 250 }, title = "TARGET", unit = "x100 m" } },
}

local LAMPS = {
    { id = "bat",    label = "BATTERY", x = 560, y = 112, color = { 255, 255, 240 } },
    { id = "fuel",   label = "FUEL",    x = 620, y = 112, color = { 255, 255, 240 } },
    { id = "eng",    label = "ENGINE",  x = 680, y = 112, color = { 60, 255, 120 } },
    { id = "doorl",  label = "DOOR L",  x = 740, y = 112, color = { 255, 200, 40 } },
    { id = "doorr",  label = "DOOR R",  x = 800, y = 112, color = { 255, 200, 40 } },
    { id = "closed", label = "CLOSED",  x = 860, y = 112, color = { 60, 255, 120 } },
    { id = "sifa",   label = "SIFA",    x = 560, y = 40,  color = { 255, 255, 255 } },
    { id = "atp",    label = "ATP",     x = 740, y = 40,  color = { 255, 170, 30 } },
    { id = "rev",    label = "REVERSE", x = 800, y = 40,  color = { 255, 255, 240 } },
    { id = "emerg",  label = "EMERG.",  x = 860, y = 40,  color = { 255, 50, 40 } },
}

local CONTROLS = {
    { id = "battery", kind = "toggle", label = "BATTERY",   x = 48 },
    { id = "fuel",    kind = "toggle", label = "FUEL PUMP", x = 122 },
    { id = "start",   kind = "button", label = "START",     x = 202, color = { 40, 170, 70 } },
    { id = "stop",    kind = "button", label = "STOP",      x = 262, color = { 200, 40, 35 } },
    { id = "lights",  kind = "toggle", label = "LIGHTS",    x = 330 },
    { id = "rev",     kind = "toggle", label = "DIR",       x = 384 },
    { id = "doorl",   kind = "button", label = "DOORS L",   x = 432, color = { 230, 180, 30 } },
    { id = "doorc",   kind = "button", label = "CLOSE",     x = 496, color = { 230, 230, 230 } },
    { id = "doorr",   kind = "button", label = "DOORS R",   x = 560, color = { 230, 180, 30 } },
    { id = "sifa",    kind = "button", label = "SIFA",      x = 650, color = { 245, 245, 245 }, big = true },
}

local function drawStatic(ctx)
    local s = ctx.s
    local W, H = rtW, rtH
    local light, dark = tocolor(70, 82, 104), tocolor(8, 10, 14)
    -- housing
    Gfx.box(0, 0, W, H, tocolor(28, 34, 46), light, dark, math.max(2, 3 * s))
    -- upper instrument field
    Gfx.box(10 * s, 8 * s, W - 20 * s, 168 * s, tocolor(13, 17, 25), dark, tocolor(50, 60, 78), math.max(1, 2 * s))
    -- lamp field + Sifa plate
    Gfx.box(520 * s, 14 * s, 368 * s, 154 * s, tocolor(18, 23, 33), dark, tocolor(50, 60, 78), math.max(1, 2 * s))
    Gfx.box(596 * s, 22 * s, 104 * s, 40 * s, tocolor(8, 9, 12), tocolor(60, 66, 80), tocolor(4, 4, 6), math.max(1, 2 * s))
    Gfx.text("SIFA", 596 * s, 22 * s, 104 * s, 40 * s, tocolor(210, 215, 225), ctx.font(true, 20), "center", "center")
    local smallB = ctx.font(true, 9)
    local small = ctx.font(false, 8)
    local numBig = ctx.font(true, 13)
    local tiny = ctx.font(false, 7)
    for id, g in pairs(G) do
        local o = g[4]
        o.s = s
        o.font = id == "speed" and numBig or ctx.font(true, 8)
        o.smallFont = id == "speed" and smallB or tiny
        o.titleFont = small
        Gfx.gaugeFace(g[1] * s, g[2] * s, g[3] * s, o)
    end
    Gfx.text("BR 232", 380 * s, 164 * s, 80 * s, 12 * s, tocolor(150, 160, 180), smallB, "center", "center")
    for _, l in ipairs(LAMPS) do
        Gfx.lampBezel(l.x * s, l.y * s, 11 * s)
        Gfx.text(l.label, l.x * s - 30 * s, l.y * s + 15 * s, 60 * s, 12 * s, tocolor(190, 198, 214), small, "center", "top")
    end
    -- blue switch band
    Gfx.box(10 * s, 184 * s, W - 20 * s, 78 * s, tocolor(30, 70, 140), tocolor(80, 125, 200), tocolor(14, 32, 70), math.max(1, 2 * s))
    Gfx.rect(10 * s, 200 * s, W - 20 * s, 1 * s, tocolor(20, 48, 100))
    for _, c in ipairs(CONTROLS) do
        Gfx.text(c.label, (c.x - 34) * s, 186 * s, 68 * s, 13 * s, tocolor(235, 240, 255), smallB, "center", "top")
        if c.kind == "toggle" then Gfx.toggleBase(c.x * s, 232 * s, s) end
    end
    Gfx.rect(716 * s, 188 * s, 1 * s, 70 * s, tocolor(20, 48, 100))
    local hint = ctx.font(false, 9)
    local keys = LOCO.KEYS
    Gfx.text(("%s  cursor\n%s  Sifa\n%s  timetable"):format(keys.cursor:upper(), keys.sifa:upper(), keys.timetable:upper()),
        728 * s, 204 * s, 160 * s, 54 * s, tocolor(220, 230, 250), hint, "left", "top")
end

local function buildRT(ctx)
    local p = ctx.L.panel
    local w, h = math.floor(p.w), math.floor(p.h)
    if not rt or rtW ~= w or rtH ~= h then
        if rt and isElement(rt) then destroyElement(rt) end
        rt = dxCreateRenderTarget(w, h, true)
        rtW, rtH = w, h
    end
    if not rt then return end
    dxSetRenderTarget(rt, true)
    dxSetBlendMode("modulate_add")
    drawStatic(ctx)
    dxSetBlendMode("blend")
    dxSetRenderTarget()
end

local function approach(cur, target, rate, dt)
    local d = target - cur
    local step = rate * dt
    if math.abs(d) <= step then return target end
    return cur + (d > 0 and step or -step)
end

local function simulate(ctx, dt)
    local st = ctx.state()
    local eng = st.eng or "off"
    local train = ctx.train()
    local throttle = train and math.max(0, train.ctrl) or 0
    if ctx.isLocked() then throttle = 0 end
    v.ctrl = approach(v.ctrl, train and train.ctrl * 100 or 0, 250, dt)
    local remaining = train and train.authority and train.authority.remaining or 2000
    v.target = approach(v.target, math.min(2000, remaining), 1500, dt)
    local crankJitter = eng == "cranking" and math.sin(getTickCount() / 70) * 4 or 0
    v.volt = approach(v.volt, st.bat and (eng == "cranking" and 86 + crankJitter or (eng == "running" and 112 or 108)) or 0, 120, dt)
    v.fuel = approach(v.fuel, st.fuel and 4.6 or 0, 2.5, dt)
    local rpmT = eng == "running" and (420 + throttle * 560) or (eng == "cranking" and 160 + crankJitter * 10 or 0)
    v.rpm = approach(v.rpm, rpmT, eng == "running" and 300 or 400, dt)
    v.oil = approach(v.oil, eng == "running" and (3.2 + v.rpm / 1000 * 2.5) or (eng == "cranking" and 1 or 0), 2, dt)
    v.temp = approach(v.temp, eng == "running" and (74 + throttle * 8) or 18, eng == "running" and 0.6 or 0.15, dt)
    v.load = approach(v.load, eng == "running" and throttle * 100 or 0, 60, dt)
    v.speed = approach(v.speed, ctx.speed(), 80, dt)
end

local function frac(id, val)
    local o = G[id][4]
    return (val - o.min) / (o.max - o.min)
end

local function click(ctx, c)
    pressed[c.id] = getTickCount() + 180
    if c.id == "battery" then ctx.send("battery")
    elseif c.id == "fuel" then ctx.send("fuel")
    elseif c.id == "start" then ctx.send("start")
    elseif c.id == "stop" then ctx.send("stop")
    elseif c.id == "lights" then ctx.send("lights")
    elseif c.id == "doorl" then ctx.send("doors", "left")
    elseif c.id == "doorr" then ctx.send("doors", "right")
    elseif c.id == "doorc" then ctx.send("doors", "closed")
    elseif c.id == "sifa" then if Sifa then Sifa.acknowledge() end
    elseif c.id == "rev" then exports.rw_customtracks:netCab("rev") end
end

function M.render(ctx)
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastT) / 1000)
    lastT = now
    simulate(ctx, dt)
    if not rt then buildRT(ctx) end
    local p = ctx.L.panel
    local s = ctx.s
    local x0, y0 = p.x, p.y
    if rt then
        dxSetBlendMode("add")
        dxDrawImage(x0, y0, rtW, rtH, rt)
        dxSetBlendMode("blend")
    end

    -- needles
    for id, g in pairs(G) do
        local val = v[id] or 0
        Gfx.needle(x0 + g[1] * s, y0 + g[2] * s, g[3] * s, frac(id, val), s)
    end

    -- lamps (no power = all dark)
    local st = ctx.state()
    local eng = st.eng or "off"
    local doors = ctx.doors()
    local blink = math.floor(now / 350) % 2 == 0
    local sifaState = Sifa and Sifa.state or "idle"
    local on = {
        bat = st.bat, fuel = st.fuel,
        eng = eng == "running" or (eng == "cranking" and blink),
        doorl = doors == "left" or doors == "both",
        doorr = doors == "right" or doors == "both",
        closed = doors == "closed",
        sifa = sifaState == "lamp" or (sifaState == "alarm" and blink) or sifaState == "brake",
        emerg = (Sifa and Sifa.braking) or false,
    }
    local train = ctx.train()
    on.atp = train and (train.atp or (train.authority and train.authority.remaining < 250 and blink)) or false
    on.rev = train and train.rev < 0 or false
    for _, l in ipairs(LAMPS) do
        local lit = on[l.id] and (st.bat or l.id == "emerg")
        Gfx.lamp(x0 + l.x * s, y0 + l.y * s, 9 * s, l.color, lit)
    end

    -- controls
    for _, c in ipairs(CONTROLS) do
        local cx, cy = x0 + c.x * s, y0 + 232 * s
        if c.kind == "toggle" then
            local val = (c.id == "battery" and st.bat) or (c.id == "fuel" and st.fuel) or (c.id == "lights" and st.lights)
                or (c.id == "rev" and not on.rev)
            Gfx.toggleLever(cx, cy, val, s)
            ctx.hit(cx - 16 * s, cy - 24 * s, 32 * s, 48 * s, function() click(ctx, c) end)
        else
            local r = (c.big and 19 or 15) * s
            local isPressed = (pressed[c.id] or 0) > now
            local lit = c.id == "sifa" and (sifaState ~= "idle")
            Gfx.button(cx, cy, r, c.color, isPressed, lit)
            local hover = ctx.cursorIn(cx - r, cy - r, r * 2, r * 2)
            if hover then dxDrawCircle(cx, cy, r + 3 * s, 0, 360, tocolor(255, 255, 255, 60), tocolor(255, 255, 255, 0), 24) end
            ctx.hit(cx - r, cy - r, r * 2, r * 2, function() click(ctx, c) end)
        end
    end
end

function M.layout(ctx)
    rt = rt and isElement(rt) and rt or nil
    if rt then buildRT(ctx) end
end

function M.restore(ctx)
    buildRT(ctx)
end

function M.enter(ctx)
    lastT = getTickCount()
    local st = ctx.state()
    if st.eng == "running" then v.rpm, v.oil, v.temp = 420, 4, 70 end
    buildRT(ctx)
end

function M.leave()
    if rt and isElement(rt) then destroyElement(rt) end
    rt = nil
end

registerLocoModule("br232", M)
