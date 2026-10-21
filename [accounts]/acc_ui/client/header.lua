if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Logo + server name above the login/register panel (same look as ui_download).
-- "Welcome back, <name>!" while a remember-me login is saved.

Header = {}

local LOGO   = 96
local RADIUS = 16
local GAP    = 20

local logoSize = ui(LOGO)
local logoTex  = dxCreateTexture("freev.png", "argb", true, "clamp")
local shader   = dxCreateShader("rounded.fx")
if shader and logoTex then
    dxSetShaderValue(shader, "radius", ui(RADIUS))
    dxSetShaderValue(shader, "size", logoSize, logoSize)
    dxSetShaderValue(shader, "sourceTexture", logoTex)
end

-- anchor: the visible login/register panel ({X, Y, W}); called from render.lua
function Header.draw(anchor)
    if not (anchor and anchor.X) then return end
    local name = getSavedAccountName()
    local text = name and L("acc_ui.header.welcome_back", { name = name })
        or L("acc_ui.header.welcome")

    local scale, font = ui(2.0), "default-bold"
    local textW = dxGetTextWidth(text, scale, font)
    local gap = ui(18)
    local x = math.floor(anchor.X + anchor.W / 2 - (logoSize + gap + textW) / 2)
    local y = anchor.Y - ui(GAP) - logoSize

    dxDrawImage(x, y, logoSize, logoSize, shader or logoTex or "freev.png")
    dxDrawText(text, x + logoSize + gap, y, x + logoSize + gap + textW, y + logoSize,
        Theme.title, scale, font, "left", "center")
end
