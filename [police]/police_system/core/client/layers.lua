-- police_system / core/client/layers.lua
-- The render scheduler: every UI piece is a layer that is only in onClientRender while it is active. With no
-- active layer the handler itself is detached (no idle per-frame work). Layers draw in `order`.

local Layers = { list = {}, sorted = {}, attached = false }
POL.layers = Layers

local function render()
    for i = 1, #Layers.sorted do
        local l = Layers.sorted[i]
        local ok, err = pcall(l.fn)
        if not ok then outputDebugString("[police_system] layer " .. l.name .. ": " .. tostring(err), 1) end
    end
end

local function rebuild()
    local s = {}
    for _, l in pairs(Layers.list) do if l.on then s[#s + 1] = l end end
    table.sort(s, function(a, b) return a.order < b.order end)
    Layers.sorted = s
    if #s > 0 and not Layers.attached then
        Layers.attached = true
        addEventHandler("onClientRender", root, render)
    elseif #s == 0 and Layers.attached then
        Layers.attached = false
        removeEventHandler("onClientRender", root, render)
    end
end

function Layers.add(name, fn, order)
    Layers.list[name] = { name = name, fn = fn, order = order or 0, on = false }
end

function Layers.set(name, on)
    local l = Layers.list[name]
    if not l or l.on == (on and true or false) then return end
    l.on = on and true or false
    rebuild()
end

function Layers.isOn(name) return Layers.list[name] and Layers.list[name].on or false end

-- A canvas: a render target redrawn only when its content changes; per frame just one dxDrawImage.
-- cv:paint(w, h, fn) draws fn(w, h) into it; cv:draw(x, y) draws the image. Restored after a device loss by the
-- owner (onClientRestore -> paint again).
function POL.canvas()
    local cv = { rt = nil, w = 0, h = 0 }
    function cv:paint(w, h, fn)
        w, h = math.floor(w), math.floor(h)
        if not self.rt or self.w ~= w or self.h ~= h then
            if self.rt and isElement(self.rt) then destroyElement(self.rt) end
            self.rt = dxCreateRenderTarget(w, h, true)
            self.w, self.h = w, h
        end
        if not self.rt then return end
        dxSetRenderTarget(self.rt, true)
        dxSetBlendMode("modulate_add")
        fn(w, h)
        dxSetBlendMode("blend")
        dxSetRenderTarget()
    end
    function cv:draw(x, y)
        if not self.rt then return end
        dxSetBlendMode("add")
        dxDrawImage(x, y, self.w, self.h, self.rt)
        dxSetBlendMode("blend")
    end
    function cv:free()
        if self.rt and isElement(self.rt) then destroyElement(self.rt) end
        self.rt = nil
    end
    return cv
end
