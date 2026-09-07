--[[
    v_phone / client/core/shader.lua
    Texture cache + a rounded-rectangle draw helper backed by fx/rounded.fx.

    MTA resolves a shader element's values at frame-flush time, so a single
    shader reused for several draws in one frame would make them all use the
    last values. Hence: one shader instance per call-site `key`.
]]

PhoneShader = {}

local WHITE = "img/white.png"
PhoneShader.WHITE = WHITE

local textures = {}   -- path -> texture | false
local shaders  = {}   -- key  -> shader  | false

function PhoneShader.texture(path)
    if not path then return nil end
    if textures[path] == nil then
        textures[path] = dxCreateTexture(path, "argb", true, "clamp") or false
    end
    return textures[path] or nil
end

--- Draw `path` (or a solid fill if omitted) as a rounded rectangle, tinted by
--  the given colour.
--  @param key    stable string, unique per element drawn in a frame
function PhoneShader.rounded(key, x, y, w, h, radius, path, r, g, b, a)
    local tex = PhoneShader.texture(path or WHITE)
    r, g, b, a = r or 255, g or 255, b or 255, a or 255

    local shader = shaders[key]
    if shader == nil then
        shader = dxCreateShader("fx/rounded.fx") or false
        shaders[key] = shader
    end

    if not shader or not tex then
        if tex then
            dxDrawImage(x, y, w, h, tex, 0, 0, 0, tocolor(r, g, b, a))
        else
            dxDrawRectangle(x, y, w, h, tocolor(r, g, b, a))
        end
        return
    end

    dxSetShaderValue(shader, "sourceTexture", tex)
    dxSetShaderValue(shader, "size", { w, h })
    dxSetShaderValue(shader, "radius", radius)
    dxDrawImage(x, y, w, h, shader, 0, 0, 0, tocolor(r, g, b, a))
end
